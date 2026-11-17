import CryptoKit
import Foundation
import Observation

/// One person's sync account on this device: their setup, playback progress and Watch Later.
///
/// What the Sync screen does on a button press and waits for, such as making a device code,
/// revoking a device or disconnecting, throws. Syncing, connecting and choosing run in the
/// background and report through `status` and `errorMessage`.
@MainActor @Observable
public final class AccountSync {
    public private(set) var isConnected = false
    public private(set) var isSyncing = false
    public private(set) var status = Status.off
    public private(set) var errorMessage: String?
    public private(set) var lastSync: Date?
    public var needsChoice: Bool { choice != nil }
    public private(set) var devices: [SyncDevice] = []
    /// The server refused the Watch Later document, as gateways from before it synced do.
    /// Watch Later then stays on this device while everything else syncs.
    public private(set) var watchLaterNeedsNewerServer = false
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
        var watchLater: WatchLaterSyncSnapshot?
        enum CodingKeys: String, CodingKey {
            case setup = "profile", progress, lastSync, initialImport, pendingProgressBase, pendingProgressIDs, formerlyShared
            case watchLater
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
    private static let watchLaterPath = "documents/watchLater"
    private static let setupResource = "configuration"
    private static let progressResource = "progress"
    private static let watchLaterResource = "watchLater"
    private static let resources: Set<String> = [setupResource, progressResource, watchLaterResource]
    private static func baselineKey(_ profileID: String) -> String { "accountSyncBaseline.\(profileID)" }

    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let localSetup: AccountSyncLocalSetup
    @ObservationIgnored private let storage: Storage
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var connection: Connection?
    @ObservationIgnored private var baselines = Baselines()
    private var choice: Choice?
    /// Replaced on disconnect, so results that arrive late are dropped.
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var observer: AccountSyncDefaultsObserver?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var isCheckQueued = false
    @ObservationIgnored private var lastObservedSettings: SyncedSettings?
    @ObservationIgnored private var lastObservedProgress: PlaybackSyncSnapshot?
    @ObservationIgnored private var lastObservedWatchLater: WatchLaterSyncSnapshot?
    /// The server's documents as this device last read or wrote them, by path, so a fetch of
    /// one that hasn't changed costs no download.
    @ObservationIgnored private var documents: [String: AccountSyncDocument] = [:]
    /// Whether the server confirmed this device's account since launch or connecting. Checked
    /// again after it rejects the device.
    @ObservationIgnored private var hasCheckedIdentity = false
    /// Documents another device changed while a sync ran, synced right after it.
    @ObservationIgnored private var queuedResources: Set<String> = []
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var wantsLiveUpdates = false
    /// The server is holding a changes request for this device, so others hear of its progress soon.
    @ObservationIgnored private var isLive = false

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
    public func showForTesting(status: Status, needsChoice: Bool, watchLaterNeedsNewerServer: Bool = false) {
        isConnected = true
        self.watchLaterNeedsNewerServer = watchLaterNeedsNewerServer
        self.status = status
        choice = needsChoice ? Choice(initial: false) : nil
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
            async let setupFetch = fetch(Self.setupPath, client: client, id: id)
            async let progressFetch = fetch(Self.progressPath, client: client, id: id)
            let (setupDocument, progressDocument) = try await (setupFetch, progressFetch)
            let remoteSetup = try openSetup(setupDocument, key: key)
            let remoteProgress = try openProgress(progressDocument, key: key)
            beforeProfileChange?()
            let localSettings = try localSetup.current.validated()
            let localProgress = try library.playbackSyncSnapshot.validated()
            let localWatchLater = try library.watchLaterSyncSnapshot.validated()
            try localSetup.rememberBeforeConnecting(localSettings)
            let pendingBaselines = Baselines(initialImport: InitialImport(settings: localSettings, progress: localProgress))
            try saveBaselines(pendingBaselines, connection: proposed)
            try storage.save(JSONEncoder().encode(proposed))
            connection = proposed
            isConnected = true
            try activateProfiles(for: proposed)
            // Watch Later is never chosen between: this device's titles join the account's.
            try library.applyWatchLaterSyncSnapshot(.merged(local: library.watchLaterSyncSnapshot, remote: localWatchLater))
            baselines = pendingBaselines
            choice = Choice(settings: SettingsChoice(local: localSettings, remote: remoteSetup?.settings ?? SyncedSettings(),
                                                     revision: setupDocument?.revision),
                            progress: ProgressChoice(local: localProgress, remote: remoteProgress, revision: progressDocument?.revision),
                            initial: true)
            status = .choosingInitialSetup
        }
        if isConnected, wantsLiveUpdates { startLiveUpdates() }
    }

    public func disconnect() throws {
        let localSettings = try connection?.localSettings?.validated()
        try storage.remove()
        generation = UUID()
        pending?.cancel()
        pending = nil
        listener?.cancel()
        listener = nil
        isLive = false
        documents = [:]
        hasCheckedIdentity = false
        queuedResources = []
        connection = nil
        baselines = Baselines()
        choice = nil
        devices = []
        watchLaterNeedsNewerServer = false
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

    public func sync() async { await sync(only: Self.resources) }

    /// - Parameter resources: The documents to bring up to date: all of them, or those another
    ///   device changed.
    private func sync(only resources: Set<String>) async {
        if choice?.initial == true {
            if choice?.requiresRefresh == true { await refreshInitialChoice() }
            return
        }
        guard let connection else { return }
        let resources = resources.union(queuedResources)
        await run { id in
            queuedResources = []
            status = .syncing
            let client = try client(connection)
            if !hasCheckedIdentity {
                let identity = try await client.me()
                try ensureCurrent(id)
                guard identity.accountID == connection.accountID, identity.deviceID == connection.deviceID else {
                    throw SyncError.unauthorized
                }
                hasCheckedIdentity = true
            }
            try await syncDocuments(resources, client: client, id: id)
            lastSync = .now
            baselines.lastSync = lastSync
            try saveBaselines()
            if !needsChoice { status = .upToDate }
        }
    }

    /// Side by side: each document merges on its own. All finish before a failure is reported,
    /// so none stops between its write and applying what it wrote.
    private func syncDocuments(_ resources: Set<String>, client: AccountSyncClient, id: UUID) async throws {
        let syncsSetup = resources.contains(Self.setupResource) && choice?.settings == nil
        async let setup = failure(syncing: syncsSetup ? Self.setupResource : nil, client: client, id: id)
        async let progress = failure(syncing: resources.contains(Self.progressResource) ? Self.progressResource : nil,
                                     client: client, id: id)
        async let watchLater = failure(syncing: resources.contains(Self.watchLaterResource) ? Self.watchLaterResource : nil,
                                       client: client, id: id)
        let failures = await [setup, progress, watchLater]
        if let error = failures.compactMap({ $0 }).first { throw error }
    }

    private func failure(syncing resource: String?, client: AccountSyncClient, id: UUID) async -> (any Error)? {
        do {
            switch resource {
            case Self.setupResource: try await syncSetup(client: client, id: id)
            case Self.progressResource: try await syncProgress(client: client, id: id)
            case Self.watchLaterResource: try await syncWatchLater(client: client, id: id)
            default: break
            }
        } catch { return error }
        return nil
    }

    private func syncSetup(client: AccountSyncClient, id: UUID) async throws {
        guard let connection else { return }
        let cipher = try AccountSyncCipher(key: connection.key, resource: Self.setupResource)
        try await retryingConflicts {
            let document = try await fetch(Self.setupPath, client: client, id: id)
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
                revision = try await put(cipher.seal(setup), Self.setupPath, revision: document?.revision, client: client, id: id)
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
            let document = try await fetch(Self.progressPath, client: client, id: id)
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
                revision = try await put(cipher.seal(result), Self.progressPath, revision: document?.revision, client: client, id: id)
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
                }
            } else {
                baselines.pendingProgressBase = base
                baselines.pendingProgressIDs = localResult.conflictingIDs
                var pendingChoice = choice ?? Choice(initial: false)
                pendingChoice.progress = ProgressChoice(local: current, remote: result, merge: localResult,
                                                        revision: revision, base: base)
                choice = pendingChoice
                status = .choosingPlayback
            }
        }
    }

    private func syncWatchLater(client: AccountSyncClient, id: UUID) async throws {
        guard let connection else { return }
        let cipher = try AccountSyncCipher(key: connection.key, resource: Self.watchLaterResource)
        do {
            try await retryingConflicts {
                let document = try await fetch(Self.watchLaterPath, client: client, id: id)
                let remote = try openWatchLater(document, key: connection.key)
                let result = WatchLaterSyncSnapshot.merged(local: try library.watchLaterSyncSnapshot.validated(), remote: remote)
                // Written even when empty: an older gateway answers only a write with its refusal.
                if result != remote || document == nil {
                    _ = try await put(cipher.seal(result), Self.watchLaterPath, revision: document?.revision, client: client, id: id)
                }
                // Merged again, so a title saved or removed meanwhile isn't undone.
                try library.applyWatchLaterSyncSnapshot(.merged(local: library.watchLaterSyncSnapshot, remote: result))
                baselines.watchLater = result
                watchLaterNeedsNewerServer = false
            }
        } catch SyncError.httpStatus(404) {
            watchLaterNeedsNewerServer = true
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
            let latest = try await fetch(Self.setupPath, client: client, id: id)
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
            let latest = try await fetch(Self.progressPath, client: client, id: id)
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
        let revision = try await put(cipher.seal(setup), Self.setupPath, revision: pending.revision, client: client, id: id)
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
        let revision = try await put(cipher.seal(progress), Self.progressPath, revision: pending.revision, client: client, id: id)
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
            async let setupFetch = fetch(Self.setupPath, client: client, id: id)
            async let progressFetch = fetch(Self.progressPath, client: client, id: id)
            let (setupDocument, progressDocument) = try await (setupFetch, progressFetch)
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
        status = .choosingSettings
    }

    // MARK: Live updates

    /// While the app is in front: keeps one request open that the server answers when another
    /// device changes this account's documents, and syncs those. `stopLiveUpdates()` on leaving.
    public func startLiveUpdates() {
        wantsLiveUpdates = true
        guard listener == nil, let connection else { return }
        let id = generation
        listener = Task { [weak self] in await self?.listen(connection: connection, id: id) }
    }

    public func stopLiveUpdates() {
        wantsLiveUpdates = false
        listener?.cancel()
        listener = nil
        isLive = false
    }

    /// Failures retry with a growing pause and leave the shown status alone: launch, returning
    /// and local changes still sync and report as before.
    private func listen(connection: Connection, id: UUID) async {
        // Not after `stopLiveUpdates()` or a disconnect, which may have started another one.
        defer {
            if !Task.isCancelled, generation == id {
                listener = nil
                isLive = false
            }
        }
        guard let client = try? client(connection) else { return }
        var since: String?
        var failures = 0
        while !Task.isCancelled, generation == id {
            do {
                let answer = try await client.changes(since: since)
                guard !Task.isCancelled, generation == id else { return }
                failures = 0
                isLive = true
                since = answer.since
                let changed = Self.resources.intersection(answer.changes)
                guard !changed.isEmpty else { continue }
                if isSyncing { queuedResources.formUnion(changed) } else { await sync(only: changed) }
            } catch SyncError.httpStatus(404) {
                // A gateway from before live updates; the next return to the app asks again.
                break
            } catch SyncError.unauthorized {
                hasCheckedIdentity = false
                await sync()
                break
            } catch {
                guard !Task.isCancelled, generation == id else { return }
                isLive = false
                failures += 1
                do { try await Task.sleep(for: .seconds(Self.retryDelay(afterFailures: failures))) } catch { return }
            }
        }
    }

    static func retryDelay(afterFailures failures: Int) -> Double {
        min(60, pow(2, Double(max(failures, 1) - 1)))
    }

    /// Brings playback progress up to date before choosing where to resume, waiting at most
    /// `limit`. A slower server leaves this device's progress to decide; the pull still finishes.
    public func refreshProgress(within limit: Duration) async {
        guard isConnected, choice?.initial != true else { return }
        let (finished, signal) = AsyncStream<Void>.makeStream()
        Task {
            // A sync already running may have fetched before the other device's last save.
            while isSyncing {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
            }
            await sync(only: [Self.progressResource])
            signal.yield()
        }
        let timeout = Task {
            do { try await Task.sleep(for: limit) } catch { return }
            signal.yield()
        }
        for await _ in finished { break }
        timeout.cancel()
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
        do { try await operation(id) } catch {
            guard generation == id else { return }
            if error as? SyncError == .unauthorized { hasCheckedIdentity = false }
            fail(error)
        }
    }

    /// Asks with the revision this device has, so an unchanged document isn't downloaded again.
    private func fetch(_ path: String, client: AccountSyncClient, id: UUID) async throws -> AccountSyncDocument? {
        let document = try await client.fetch(path, cached: documents[path])
        try ensureCurrent(id)
        documents[path] = document
        return document
    }

    private func put(_ document: AccountSyncDocument, _ path: String, revision: String?,
                     client: AccountSyncClient, id: UUID) async throws -> String {
        let written = try await client.put(document, resource: path, revision: revision)
        try ensureCurrent(id)
        var saved = document
        saved.revision = written
        documents[path] = saved
        return written
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

    private func openWatchLater(_ document: AccountSyncDocument?, key: String) throws -> WatchLaterSyncSnapshot {
        guard let document else { return WatchLaterSyncSnapshot() }
        return try AccountSyncCipher(key: key, resource: Self.watchLaterResource)
            .open(document, as: WatchLaterSyncSnapshot.self).validated()
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
        lastObservedWatchLater = library.watchLaterSyncSnapshot
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
        // Settings and Watch Later changes are deliberate and few; playback progress changes every few seconds.
        let deliberate = settings != lastObservedSettings || library.watchLaterSyncSnapshot != lastObservedWatchLater
        guard deliberate || progress != lastObservedProgress else { return }
        rememberObserved()
        if !isSyncing { status = .waiting }
        // While the server holds a changes request, the other devices hear of it at once.
        schedule(after: deliberate ? 1 : isLive ? 2 : 15)
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

    /// Edits made while an operation ran, and documents another device changed meanwhile,
    /// are synced right after it.
    private func finish() {
        isSyncing = false
        rememberObserved()
        guard isConnected, !needsChoice, errorMessage == nil else { return }
        if !queuedResources.isEmpty {
            schedule(after: 0)
        } else if localSetup.current != baselines.setup?.settings
            || library.playbackSyncSnapshot != baselines.progress
            || !watchLaterNeedsNewerServer && library.watchLaterSyncSnapshot != baselines.watchLater {
            schedule(after: 1)
        }
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
