import CryptoKit
import Foundation
import Observation

/// One person's sync account on this device: their setup and playback progress.
///
/// Methods that return something, such as a connection code, throw. The rest run in the
/// background of the Sync screen and report through `status` and `errorMessage`.
@MainActor @Observable
public final class AccountSync {
    public private(set) var isConnected = false
    public private(set) var isSyncing = false
    public private(set) var status = Status.off
    public private(set) var errorMessage: String?
    public private(set) var lastSync: Date?
    public private(set) var needsChoice = false
    public private(set) var devices: [SyncDevice] = []
    /// Runs before the library and setup switch to another person's, so playback can stop.
    @ObservationIgnored public var beforeProfileChange: (() -> Void)?
    public var displayName: String? { connection?.displayName }
    public var endpoint: String? { connection?.endpoint }
    public var recoveryKey: String? { connection?.key }
    /// Marks this device in the device list, where every iPhone is called "iPhone".
    public var currentDeviceID: String? { connection?.deviceID }
    public var choiceSummary: String {
        if let choice, choice.initial {
            return "Choose whether to bring this device's setup and playback into this account, or use the account's saved data."
        }
        return "Choose only the conflicting settings, or whether a title removed on one device and played on another stays. Independent changes are kept."
    }
    public var conflictingProgressIDs: [String] { choice?.progress?.merge?.conflictingIDs.sorted() ?? [] }

    /// What Keychain keeps for a connected account.
    struct Connection: Codable, Sendable {
        let endpoint: String
        let token: String
        let accountID: String
        let displayName: String
        let deviceID: String
        let key: String
        /// The setup from before connecting, restored on disconnect.
        var localSettings: SyncedSettings?
        var requiresInitialChoice: Bool?
        var libraryProfileID: String {
            SHA256.hash(data: Data("\(endpoint)|\(accountID)".utf8)).map { String(format: "%02x", $0) }.joined()
        }
        var isValid: Bool { AccountSyncClient.endpointURL(endpoint) != nil && AccountSyncCipher.isValidKey(key) }
    }
    /// What versions with shared setups also kept in a saved connection: each group's
    /// categories, beside the key this version no longer keeps.
    private struct RetiredGroups: Decodable {
        struct Group: Decodable { let categories: [String] }
        let groups: [Group]?
    }
    struct Storage {
        var load: () throws -> Data?
        var save: (Data) throws -> Void
        var remove: () throws -> Void
    }
    /// The account's own encrypted document: its settings.
    private struct AccountSetup: Codable, Equatable {
        var settings: SyncedSettings
        private enum CodingKeys: String, CodingKey { case settings, groups }
        init(settings: SyncedSettings) { self.settings = settings }
        /// Ignores the shared setups' keys an earlier version kept here.
        init(from decoder: Decoder) throws {
            settings = try decoder.container(keyedBy: CodingKeys.self).decode(SyncedSettings.self, forKey: .settings)
        }
        /// Versions with shared setups can't read the document without its list of them.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(settings, forKey: .settings)
            try container.encode([String](), forKey: .groups)
        }
    }
    /// What was last agreed with the server, to tell local edits from remote ones.
    private struct Baselines: Codable {
        var setup: AccountSetup?
        var progress: PlaybackSyncSnapshot?
        var lastSync: Date?
        var initialImport: InitialImport?
        var pendingProgressBase: PlaybackSyncSnapshot?
        var pendingProgressIDs: Set<String> = []
        /// Categories this device last took from a shared setup, until the next sync makes
        /// its values for them the account's.
        var formerlyShared: Set<SyncCategory>?
        enum CodingKeys: String, CodingKey {
            case setup = "profile", progress, lastSync, initialImport, pendingProgressBase, pendingProgressIDs, formerlyShared
        }
    }
    private struct InitialImport: Codable {
        var settings: SyncedSettings
        var progress: PlaybackSyncSnapshot
    }
    /// A pending decision between this device's version and the server's.
    private struct Choice {
        var settings: SettingsChoice?
        var progress: ProgressChoice?
        /// The first choice after connecting, between whole setups rather than conflicting fields.
        var initial: Bool
        /// Restored after relaunch: the server versions must be fetched before choosing.
        var requiresRefresh = false
    }
    private struct SettingsChoice {
        var local: SyncedSettings
        var remote: SyncedSettings
        var merge: SyncedSettings.Merge?
        var revision: String?
    }
    private struct ProgressChoice {
        var local: PlaybackSyncSnapshot
        var remote: PlaybackSyncSnapshot
        var merge: PlaybackSyncMerge?
        var revision: String?
        var base: PlaybackSyncSnapshot?
    }
    private static let setupPath = "documents/configuration"
    private static let progressPath = "documents/progress"
    private static let setupResource = "configuration"
    private static let progressResource = "progress"
    private static func baselineKey(_ profileID: String) -> String { "accountSyncBaseline.\(profileID)" }

    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let localSetup: AccountSyncLocalSetup
    @ObservationIgnored private let storage: Storage
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var connection: Connection?
    @ObservationIgnored private var baselines = Baselines()
    @ObservationIgnored private var choice: Choice?
    /// Replaced on disconnect, so results that arrive late are dropped.
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var observer: AccountSyncDefaultsObserver?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var isCheckQueued = false
    @ObservationIgnored private var lastObservedSettings: SyncedSettings?
    @ObservationIgnored private var lastObservedProgress: PlaybackSyncSnapshot?

    public convenience init(addons: AddonStore, library: LibraryStore, defaults: UserDefaults = .standard) {
        self.init(addons: addons, library: library, defaults: defaults, storage: Self.keychainStorage, session: .shared)
    }
    public convenience init(addons: AddonStore, library: LibraryStore, defaults: UserDefaults = .standard,
                            temporaryConnection: Bool) {
        if temporaryConnection {
            let memory = AccountSyncMemoryConnection()
            self.init(addons: addons, library: library, defaults: defaults,
                      storage: Storage(load: { memory.data }, save: { memory.data = $0 }, remove: { memory.data = nil }),
                      session: .shared)
        } else {
            self.init(addons: addons, library: library, defaults: defaults)
        }
    }
    #if DEBUG
    /// UI checks show how a connected account's states read, without a server.
    public func showForTesting(status: Status, needsChoice: Bool) {
        isConnected = true
        self.status = status
        self.needsChoice = needsChoice
    }
    #endif

    init(addons: AddonStore, library: LibraryStore, defaults: UserDefaults, storage: Storage, session: URLSession) {
        self.library = library
        localSetup = AccountSyncLocalSetup(addons: addons, defaults: defaults)
        self.storage = storage
        self.session = session
        restoreConnection()
        rememberObserved()
        observer = AccountSyncDefaultsObserver { [weak self] in
            Task { @MainActor [weak self] in self?.queueLocalCheck() }
        }
    }

    /// Activates the saved account's library and setup. Credentials that can't be read
    /// fall back to this device's own data rather than leave an account's showing.
    private func restoreConnection() {
        do {
            guard let data = try storage.load() else {
                try activateProfiles(for: nil)
                return
            }
            let saved = try JSONDecoder().decode(Connection.self, from: data)
            guard saved.isValid else { throw SyncError.invalidKey }
            connection = saved
            try activateProfiles(for: saved)
            isConnected = true
            status = .ready
            try restoreBaselines(saved)
            try retireSharedSetups(savedData: data, connection: saved)
            if saved.requiresInitialChoice == true || baselines.setup == nil {
                let initial = baselines.initialImport
                choice = Choice(settings: SettingsChoice(local: initial?.settings ?? saved.localSettings ?? SyncedSettings(),
                                                         remote: SyncedSettings()),
                                progress: ProgressChoice(local: initial?.progress ?? PlaybackSyncSnapshot(),
                                                         remote: PlaybackSyncSnapshot()),
                                initial: true, requiresRefresh: true)
                needsChoice = true
                status = .choosingInitialSetup
            }
        } catch {
            if connection == nil {
                // The failure that brought us here is the one reported below.
                try? localSetup.activate(profileID: nil)
                library.activateProfile(id: nil)
            } else {
                choice = Choice(settings: SettingsChoice(local: localSetup.current, remote: SyncedSettings()),
                                progress: ProgressChoice(local: library.playbackSyncSnapshot, remote: PlaybackSyncSnapshot()),
                                initial: true, requiresRefresh: true)
                needsChoice = true
            }
            fail(error)
        }
    }

    // MARK: Connecting

    public func connect(code string: String, deviceName: String = "loge", recoveryKey: String? = nil) async {
        guard !isConnected else { return }
        await run { id in
            let code = try AccountSyncCode(decoding: string)
            guard code.kind == .account || code.kind == .device else { throw SyncError.wrongCode }
            guard code.kind != .device || code.key != nil else { throw SyncError.recoveryRequired }
            let suppliedKey = code.key ?? recoveryKey
            let key = suppliedKey ?? AccountSyncCipher.generateKey()
            // Checked before redeeming, so a mistyped key doesn't use up the invitation.
            guard AccountSyncCipher.isValidKey(key) else { throw SyncError.invalidKey }
            let identity = try await AccountSyncClient(endpoint: code.endpoint, session: session)
                .redeem(code: code.code, deviceName: String(deviceName.prefix(80)), hasRecoveryKey: suppliedKey != nil)
            try ensureCurrent(id)
            let proposed = Connection(endpoint: code.endpoint, token: identity.token, accountID: identity.accountID,
                                      displayName: identity.displayName, deviceID: identity.deviceID, key: key,
                                      localSettings: try localSetup.current.validated(), requiresInitialChoice: true)
            let client = try client(proposed)
            let setupDocument = try await client.fetch(Self.setupPath)
            let progressDocument = try await client.fetch(Self.progressPath)
            try ensureCurrent(id)
            let remoteSetup = try openSetup(setupDocument, key: key)
            let remoteProgress = try openProgress(progressDocument, key: key)
            beforeProfileChange?()
            let localSettings = try localSetup.current.validated()
            let localProgress = try library.playbackSyncSnapshot.validated()
            try localSetup.rememberBeforeConnecting(localSettings)
            let pendingBaselines = Baselines(initialImport: InitialImport(settings: localSettings, progress: localProgress))
            try saveBaselines(pendingBaselines, connection: proposed)
            try storage.save(JSONEncoder().encode(proposed))
            connection = proposed
            isConnected = true
            try activateProfiles(for: proposed)
            baselines = pendingBaselines
            choice = Choice(settings: SettingsChoice(local: localSettings, remote: remoteSetup?.settings ?? SyncedSettings(),
                                                     revision: setupDocument?.revision),
                            progress: ProgressChoice(local: localProgress, remote: remoteProgress, revision: progressDocument?.revision),
                            initial: true)
            needsChoice = true
            status = .choosingInitialSetup
        }
    }

    public func disconnect() throws {
        let localSettings = try connection?.localSettings?.validated()
        try storage.remove()
        generation = UUID()
        pending?.cancel()
        pending = nil
        connection = nil
        baselines = Baselines()
        choice = nil
        needsChoice = false
        devices = []
        isConnected = false
        isSyncing = false
        lastSync = nil
        errorMessage = nil
        status = .off
        beforeProfileChange?()
        try activateProfiles(for: nil)
        if let localSettings { try localSetup.apply(localSettings) }
        localSetup.forgetBeforeConnecting()
        rememberObserved()
    }

    // MARK: Syncing

    public func sync() async {
        if choice?.initial == true {
            if choice?.requiresRefresh == true { await refreshInitialChoice() }
            return
        }
        guard let connection else { return }
        await run { id in
            status = .syncing
            let client = try client(connection)
            let identity = try await client.me()
            try ensureCurrent(id)
            guard identity.accountID == connection.accountID, identity.deviceID == connection.deviceID else {
                throw SyncError.unauthorized
            }
            if choice?.settings == nil { try await syncSetup(client: client, id: id) }
            try await syncProgress(client: client, id: id)
            lastSync = .now
            baselines.lastSync = lastSync
            try saveBaselines()
            if !needsChoice { status = .upToDate }
        }
    }

    private func syncSetup(client: AccountSyncClient, id: UUID) async throws {
        guard let connection else { return }
        let cipher = try AccountSyncCipher(key: connection.key, resource: Self.setupResource)
        try await retryingConflicts {
            let document = try await client.fetch(Self.setupPath)
            try ensureCurrent(id)
            let incoming = try openSetup(document, key: connection.key)?.settings ?? SyncedSettings()
            let local = localSetup.current
            let merged = SyncedSettings.merged(base: setupBase(remote: incoming), local: local, remote: incoming)
            guard merged.conflicts.isEmpty else {
                chooseSettings(SettingsChoice(local: local, remote: incoming, merge: merged, revision: document?.revision))
                return
            }
            let setup = AccountSetup(settings: merged.settings)
            var revision = document?.revision
            // Written once after leaving a shared setup even if nothing changed, so the
            // document stops carrying the shared setups' keys.
            if setup.settings != incoming || document == nil || baselines.formerlyShared != nil {
                revision = try await client.put(cipher.seal(setup), resource: Self.setupPath, revision: document?.revision)
                try ensureCurrent(id)
            }
            baselines.setup = setup
            baselines.formerlyShared = nil
            let latest = localSetup.current
            let rebased = SyncedSettings.merged(base: local, local: latest, remote: merged.settings)
            if rebased.conflicts.isEmpty {
                try localSetup.apply(rebased.settings)
            } else {
                chooseSettings(SettingsChoice(local: latest, remote: merged.settings, merge: rebased, revision: revision))
            }
            try saveBaselines()
        }
    }

    private func syncProgress(client: AccountSyncClient, id: UUID) async throws {
        guard let connection else { return }
        let cipher = try AccountSyncCipher(key: connection.key, resource: Self.progressResource)
        try await retryingConflicts {
            let document = try await client.fetch(Self.progressPath)
            try ensureCurrent(id)
            let remote = try openProgress(document, key: connection.key)
            let local = try library.playbackSyncSnapshot.validated()
            var base = baselines.progress ?? remote
            if let original = baselines.pendingProgressBase {
                base = base.replacing(baselines.pendingProgressIDs, from: original, references: [local, remote])
            }
            // Independent titles keep syncing while a title both removed and played waits for a choice.
            let merge = PlaybackSyncSnapshot.merged(base: base, local: local, remote: remote)
            let result = merge.resolving(useLocal: false)
            var revision = document?.revision
            if result != remote || document == nil {
                revision = try await client.put(cipher.seal(result), resource: Self.progressPath, revision: document?.revision)
                try ensureCurrent(id)
            }
            let current = library.playbackSyncSnapshot
            // Against what was just uploaded, so progress saved meanwhile isn't taken for another
            // device's. Conflicts stay against the older base, or choosing here would settle them.
            let uploaded = local.replacing(merge.conflictingIDs, from: base, references: [remote])
            let localResult = PlaybackSyncSnapshot.merged(base: uploaded, local: current, remote: result)
            try library.applyPlaybackSyncSnapshot(localResult.snapshot)
            baselines.progress = result
            if localResult.conflictingIDs.isEmpty {
                baselines.pendingProgressBase = nil
                baselines.pendingProgressIDs = []
                if var remaining = choice, remaining.progress != nil {
                    remaining.progress = nil
                    choice = remaining.settings == nil ? nil : remaining
                    needsChoice = choice != nil
                }
            } else {
                baselines.pendingProgressBase = base
                baselines.pendingProgressIDs = localResult.conflictingIDs
                var pendingChoice = choice ?? Choice(initial: false)
                pendingChoice.progress = ProgressChoice(local: current, remote: result, merge: localResult,
                                                        revision: revision, base: base)
                choice = pendingChoice
                needsChoice = true
                status = .choosingPlayback
            }
        }
    }

    // MARK: Choosing

    public func resolve(useLocal: Bool) async {
        if choice?.requiresRefresh == true { await refreshInitialChoice(); return }
        guard let connection, let selected = choice else { return }
        await run { id in
            do {
                try await resolve(selected, useLocal: useLocal, connection: connection, id: id)
            } catch SyncError.conflict {
                guard generation == id else { return }
                // The next choice revalidates the captured revisions and refreshes its preview.
                status = .choosingAgain(.anotherDevice)
                errorMessage = SyncError.conflict.localizedDescription
            }
        }
    }

    /// What one resolve works against, captured once so every step compares the same versions.
    private struct Resolution {
        let client: AccountSyncClient
        let connection: Connection
        let id: UUID
        /// This device's settings and playback when the choice was made.
        let settings: SyncedSettings
        let progress: PlaybackSyncSnapshot
    }

    private func resolve(_ selected: Choice, useLocal: Bool, connection: Connection, id: UUID) async throws {
        var selected = selected
        let context = Resolution(client: try client(connection), connection: connection, id: id,
                                 settings: localSetup.current, progress: library.playbackSyncSnapshot)
        if !selected.initial, previewLocalChanges(&selected, in: context) { return }
        // Check every captured revision before writing either resource. A fresh
        // revision is never permission to overwrite a stale choice.
        if try await previewRemoteChanges(&selected, in: context) { return }
        if let settings = selected.settings {
            guard try await commit(settings, useLocal: useLocal, into: &selected, in: context) else { return }
        }
        if let progress = selected.progress {
            guard try await commit(progress, useLocal: useLocal, into: &selected, in: context) else { return }
        }
        if selected.initial {
            self.connection?.requiresInitialChoice = false
            baselines.initialImport = nil
            try persistConnection()
        }
        choice = nil
        needsChoice = false
        lastSync = .now
        baselines.lastSync = lastSync
        try saveBaselines()
        status = .upToDate
    }

    /// - Returns: Whether this device changed since the choice was shown, so it was previewed again.
    private func previewLocalChanges(_ selected: inout Choice, in context: Resolution) -> Bool {
        let settings = context.settings, progress = context.progress
        if var pending = selected.settings, settings != pending.local {
            pending.local = settings
            pending.merge = SyncedSettings.merged(base: setupBase(remote: pending.remote), local: settings, remote: pending.remote)
            selected.settings = pending
        } else if var pending = selected.progress, progress != pending.local {
            pending.local = progress
            pending.merge = PlaybackSyncSnapshot.merged(base: pending.base ?? baselines.progress ?? pending.remote,
                                                        local: progress, remote: pending.remote)
            selected.progress = pending
        } else {
            return false
        }
        choice = selected
        status = .choosingAgain(.thisDevice)
        return true
    }

    /// - Returns: Whether the server changed since the choice was shown, so it was previewed again.
    private func previewRemoteChanges(_ selected: inout Choice, in context: Resolution) async throws -> Bool {
        let client = context.client, connection = context.connection, id = context.id
        let settings = context.settings, progress = context.progress
        if var pending = selected.settings {
            let latest = try await client.fetch(Self.setupPath)
            try ensureCurrent(id)
            if latest?.revision != pending.revision {
                pending.remote = try openSetup(latest, key: connection.key)?.settings ?? SyncedSettings()
                pending.revision = latest?.revision
                if !selected.initial {
                    pending.local = settings
                    pending.merge = SyncedSettings.merged(base: setupBase(remote: pending.remote),
                                                          local: settings, remote: pending.remote)
                }
                selected.settings = pending
                choice = selected
                status = .choosingAgain(.anotherDevice)
                return true
            }
        }
        if var pending = selected.progress {
            let latest = try await client.fetch(Self.progressPath)
            try ensureCurrent(id)
            if latest?.revision != pending.revision {
                pending.remote = try openProgress(latest, key: connection.key)
                pending.revision = latest?.revision
                if !selected.initial {
                    pending.local = progress
                    pending.merge = PlaybackSyncSnapshot.merged(base: pending.base ?? baselines.progress ?? pending.remote,
                                                                local: progress, remote: pending.remote)
                }
                selected.progress = pending
                choice = selected
                status = .choosingAgain(.anotherDevice)
                return true
            }
        }
        return false
    }

    /// Writes the chosen settings, then applies them unless this device changed them meanwhile.
    /// - Returns: Whether the settings are settled; otherwise a new choice is pending.
    private func commit(_ pending: SettingsChoice, useLocal: Bool, into selected: inout Choice,
                        in context: Resolution) async throws -> Bool {
        let client = context.client, connection = context.connection, starting = context.settings, id = context.id
        let chosen = useLocal ? pending.local : pending.remote
        let settings = pending.merge.map { $0.settings.replacing($0.conflicts, from: chosen) } ?? chosen
        let setup = AccountSetup(settings: settings)
        let cipher = try AccountSyncCipher(key: connection.key, resource: Self.setupResource)
        let revision = try await client.put(cipher.seal(setup), resource: Self.setupPath, revision: pending.revision)
        try ensureCurrent(id)
        baselines.setup = setup
        baselines.formerlyShared = nil
        let current = localSetup.current
        let rebased = SyncedSettings.merged(base: starting, local: current, remote: setup.settings)
        guard rebased.conflicts.isEmpty else {
            selected.settings = SettingsChoice(local: current, remote: setup.settings, merge: rebased, revision: revision)
            selected.initial = false
            choice = selected
            status = .choosingAgain(.syncing)
            try saveBaselines()
            return false
        }
        try localSetup.apply(rebased.settings)
        selected.settings = nil
        return true
    }

    /// Writes the chosen playback state, then applies it unless this device played meanwhile.
    /// - Returns: Whether playback is settled; otherwise a new choice is pending.
    private func commit(_ pending: ProgressChoice, useLocal: Bool, into selected: inout Choice,
                        in context: Resolution) async throws -> Bool {
        let client = context.client, connection = context.connection, starting = context.progress, id = context.id
        let progress = pending.merge?.resolving(useLocal: useLocal) ?? (useLocal ? pending.local : pending.remote)
        let cipher = try AccountSyncCipher(key: connection.key, resource: Self.progressResource)
        let revision = try await client.put(cipher.seal(progress), resource: Self.progressPath, revision: pending.revision)
        try ensureCurrent(id)
        baselines.progress = progress
        let current = library.playbackSyncSnapshot
        let rebased = PlaybackSyncSnapshot.merged(base: starting, local: current, remote: progress)
        try library.applyPlaybackSyncSnapshot(rebased.snapshot)
        guard rebased.conflictingIDs.isEmpty else {
            baselines.pendingProgressBase = starting
            baselines.pendingProgressIDs = rebased.conflictingIDs
            selected.progress = ProgressChoice(local: current, remote: progress, merge: rebased,
                                               revision: revision, base: pending.base)
            selected.initial = false
            choice = selected
            status = .choosingAgain(.syncing)
            try saveBaselines()
            return false
        }
        baselines.pendingProgressBase = nil
        baselines.pendingProgressIDs = []
        return true
    }

    private func refreshInitialChoice() async {
        guard let connection, var selected = choice, selected.initial else { return }
        await run(clearingError: false) { id in
            let client = try client(connection)
            let setupDocument = try await client.fetch(Self.setupPath)
            let progressDocument = try await client.fetch(Self.progressPath)
            try ensureCurrent(id)
            selected.settings?.remote = try openSetup(setupDocument, key: connection.key)?.settings ?? SyncedSettings()
            selected.settings?.revision = setupDocument?.revision
            selected.progress?.remote = try openProgress(progressDocument, key: connection.key)
            selected.progress?.revision = progressDocument?.revision
            selected.requiresRefresh = false
            choice = selected
            status = .choosingInitialSetup
        }
    }

    private func chooseSettings(_ pending: SettingsChoice) {
        var updated = choice ?? Choice(initial: false)
        updated.settings = pending
        choice = updated
        needsChoice = true
        status = .choosingSettings
    }

    // MARK: Devices

    public func makeDeviceCode() async throws -> String {
        guard let connection, !isSyncing, !needsChoice else { throw SyncError.notReady }
        let id = generation
        let invitation = try await client(connection).inviteDevice()
        try ensureCurrent(id)
        return try AccountSyncCode(kind: .device, endpoint: connection.endpoint, code: invitation.code,
                                   key: connection.key).encoded()
    }

    /// Throws rather than reporting through `status`: a device list that can't load says
    /// nothing about whether the account syncs.
    public func refreshDevices() async throws {
        guard let connection else { return }
        let id = generation
        let devices = try await client(connection).devices()
        guard generation == id else { return }
        self.devices = devices
    }

    public func revokeDevice(id deviceID: String) async throws {
        guard let connection else { return }
        let id = generation
        try await client(connection).revokeDevice(deviceID)
        guard generation == id else { return }
        if deviceID == connection.deviceID { try disconnect() }
        else { devices.removeAll { $0.id == deviceID } }
    }

    // MARK: Plumbing

    /// Runs one operation at a time and reports its failure. A disconnect while it runs
    /// changes `generation`, so a late result can't touch the next connection's state.
    private func run(clearingError: Bool = true, _ operation: (UUID) async throws -> Void) async {
        guard !isSyncing else { return }
        let id = generation
        isSyncing = true
        if clearingError { errorMessage = nil }
        // Runs after `fail`, so a failed operation doesn't schedule an immediate retry.
        defer { if generation == id { finish() } }
        do { try await operation(id) } catch { if generation == id { fail(error) } }
    }

    private func ensureCurrent(_ id: UUID) throws {
        guard generation == id else { throw CancellationError() }
    }

    /// Writes are revision-checked: refetch and merge again when another device wrote first.
    private func retryingConflicts(_ attempt: () async throws -> Void) async throws {
        for remaining in (0..<3).reversed() {
            do { return try await attempt() }
            catch SyncError.conflict where remaining > 0 { continue }
        }
    }

    private func activateProfiles(for connection: Connection?) throws {
        try localSetup.activate(profileID: connection?.libraryProfileID)
        library.activateProfile(id: connection?.libraryProfileID)
    }

    private func openSetup(_ document: AccountSyncDocument?, key: String) throws -> AccountSetup? {
        guard let document else { return nil }
        let setup: AccountSetup = try AccountSyncCipher(key: key, resource: Self.setupResource).open(document)
        return AccountSetup(settings: try setup.settings.validated())
    }

    private func openProgress(_ document: AccountSyncDocument?, key: String) throws -> PlaybackSyncSnapshot {
        guard let document else { return PlaybackSyncSnapshot() }
        return try AccountSyncCipher(key: key, resource: Self.progressResource)
            .open(document, as: PlaybackSyncSnapshot.self).validated()
    }

    private func client(_ connection: Connection) throws -> AccountSyncClient {
        try AccountSyncClient(endpoint: connection.endpoint, token: connection.token, session: session)
    }

    private func persistConnection() throws {
        guard let connection else { return }
        try storage.save(JSONEncoder().encode(connection))
    }

    private func saveBaselines() throws {
        guard let connection else { return }
        try saveBaselines(baselines, connection: connection)
    }

    private func saveBaselines(_ value: Baselines, connection: Connection) throws {
        let document = try AccountSyncCipher(key: connection.key, resource: "baseline").seal(value)
        localSetup.defaults.set(try JSONEncoder().encode(document), forKey: Self.baselineKey(connection.libraryProfileID))
    }

    private func restoreBaselines(_ connection: Connection) throws {
        guard let data = localSetup.defaults.data(forKey: Self.baselineKey(connection.libraryProfileID)) else { return }
        let document = try JSONDecoder().decode(AccountSyncDocument.self, from: data)
        baselines = try AccountSyncCipher(key: connection.key, resource: "baseline").open(document)
        lastSync = baselines.lastSync
    }

    /// The setup as last agreed with the server. Categories this device took from a shared
    /// setup count as the server's own, so what the device shows now wins over the account's
    /// older copy of them instead of asking or replacing it.
    private func setupBase(remote: SyncedSettings) -> SyncedSettings {
        let base = baselines.setup?.settings ?? remote
        guard let formerlyShared = baselines.formerlyShared else { return base }
        return base.replacing(categories: formerlyShared, from: remote)
    }

    /// Shared setups were removed. A device that was in one keeps the setup it shows: its
    /// categories become the account's own again, marked so the next sync keeps this device's
    /// values for them. The groups' keys leave Keychain with the rewritten connection;
    /// baselines are saved first, so a failed Keychain write retries all of it next launch.
    private func retireSharedSetups(savedData data: Data, connection: Connection) throws {
        guard let groups = (try? JSONDecoder().decode(RetiredGroups.self, from: data))?.groups, !groups.isEmpty
        else { return }
        let categories = Set(groups.flatMap { $0.categories.compactMap(SyncCategory.init) })
        baselines.formerlyShared = (baselines.formerlyShared ?? []).union(categories)
        try saveBaselines()
        try storage.save(JSONEncoder().encode(connection))
    }

    private func rememberObserved() {
        lastObservedSettings = localSetup.current
        lastObservedProgress = library.playbackSyncSnapshot
    }

    /// Saving progress writes several defaults keys at once; one check covers them all.
    private func queueLocalCheck() {
        guard isConnected, !isCheckQueued else { return }
        isCheckQueued = true
        Task { [weak self] in
            self?.isCheckQueued = false
            self?.localChanged()
        }
    }

    private func localChanged() {
        // Snapshots are rebuilt only for an account that can sync them; `finish()` and
        // `disconnect()` remember what was observed before the next one starts.
        guard isConnected, choice?.initial != true else { return }
        let settings = localSetup.current
        let progress = library.playbackSyncSnapshot
        let settingsChanged = settings != lastObservedSettings
        guard settingsChanged || progress != lastObservedProgress else { return }
        rememberObserved()
        if !isSyncing { status = .waiting }
        // Settings changes are deliberate and few; playback progress changes every few seconds.
        schedule(after: settingsChanged ? 1 : 15)
    }

    private func schedule(after seconds: Double) {
        guard pending == nil else { return }
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self else { return }
            self.pending = nil
            await self.sync()
        }
    }

    /// Edits made while an operation ran are synced right after it.
    private func finish() {
        isSyncing = false
        rememberObserved()
        if isConnected, !needsChoice, errorMessage == nil,
           localSetup.current != baselines.setup?.settings
            || library.playbackSyncSnapshot != baselines.progress { schedule(after: 1) }
    }

    private func fail(_ error: Error) {
        status = .failed
        errorMessage = (error as? SyncError)?.localizedDescription ?? "Couldn't save sync setup. Try again."
    }

    private static var keychainStorage: Storage {
        let service = "li.tjh.MediaApp.account-sync"
        let account = "connection"
        return Storage(load: {
            do throws(KeychainError) { return try Keychain.read(service: service, account: account) }
            catch { throw SyncError.keychain(error.status) }
        }, save: { data in
            do throws(KeychainError) { try Keychain.save(data, service: service, account: account) }
            catch { throw SyncError.keychain(error.status) }
        }, remove: {
            do throws(KeychainError) { try Keychain.remove(service: service, account: account) }
            catch { throw SyncError.keychain(error.status) }
        })
    }
}

private extension PlaybackSyncSnapshot {
    func replacing(_ ids: Set<String>, from source: Self, references: [Self]) -> Self {
        var result = self
        for id in ids {
            let metaID = source.entries[id]?.item.metaID ?? entries[id]?.item.metaID
                ?? references.lazy.compactMap { $0.entries[id]?.item.metaID }.first
            result.entries[id] = source.entries[id]
            result.removals[id] = source.removals[id]
            if let metaID { result.titleRemovals[metaID] = source.titleRemovals[metaID] }
        }
        return result
    }
}

@MainActor private final class AccountSyncMemoryConnection {
    var data: Data?
}

private final class AccountSyncDefaultsObserver {
    let token: NSObjectProtocol
    init(changed: @escaping @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                       queue: nil) { _ in changed() }
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}
