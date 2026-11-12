import CryptoKit
import Foundation
import Observation

/// One person's sync account on this device: their private setup and playback progress,
/// plus any setup categories they share with other people. Private account state and
/// deliberately shared setup use separate encryption keys.
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
    public private(set) var sharedGroups: [SyncGroup] = []
    public private(set) var devices: [SyncDevice] = []
    /// Runs before the library and setup switch to another person's, so playback can stop.
    @ObservationIgnored public var beforeProfileChange: (() -> Void)?
    public var displayName: String? { connection?.displayName }
    public var endpoint: String? { connection?.endpoint }
    public var recoveryKey: String? { connection?.key }
    /// Marks this device in the device list, where every iPhone is called "iPhone".
    public var currentDeviceID: String? { connection?.deviceID }
    public var choiceSummary: String {
        if let groupChoice { return "Shared setup: " + groupChoice.grant.categories.map(\.name).sorted().joined(separator: ", ") }
        if let choice, choice.initial {
            return "Choose whether to bring this device's setup and playback into this account, or use the account's saved data."
        }
        return "Choose only the conflicting settings, or whether a title removed on one device and played on another stays. Independent changes are kept."
    }
    public var conflictingProgressIDs: [String] { choice?.progress?.merge?.conflictingIDs.sorted() ?? [] }

    /// Membership of a shared setup, with the key its members share.
    struct Grant: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let categories: Set<SyncCategory>
        let key: String
        /// Set until the group's first document is written.
        var initializing: Bool?
        var metadata: SyncGroup { SyncGroup(id: id, name: name, categories: categories) }
        var cipherResource: String { "group.\(id)" }
    }
    /// What Keychain keeps for a connected account.
    struct Connection: Codable, Sendable {
        let endpoint: String
        let token: String
        let accountID: String
        let displayName: String
        let deviceID: String
        let key: String
        var groups: [Grant]
        /// The setup from before connecting, restored on disconnect.
        var localSettings: SyncedSettings?
        var requiresInitialChoice: Bool?
        var libraryProfileID: String {
            SHA256.hash(data: Data("\(endpoint)|\(accountID)".utf8)).map { String(format: "%02x", $0) }.joined()
        }
        var sharedCategories: Set<SyncCategory> { Set(groups.flatMap(\.categories)) }
        var privateCategories: Set<SyncCategory> { Set(SyncCategory.allCases).subtracting(sharedCategories) }
        var isValid: Bool {
            AccountSyncClient.endpointURL(endpoint) != nil && AccountSyncCipher.isValidKey(key)
                && groups.allSatisfy { AccountSyncCipher.isValidKey($0.key) }
        }
    }
    struct Storage {
        var load: () throws -> Data?
        var save: (Data) throws -> Void
        var remove: () throws -> Void
    }
    /// The account's own encrypted document: its private settings, and the shared-setup
    /// keys its devices need. Group keys travel only between one person's devices.
    private struct AccountSetup: Codable, Equatable {
        var settings: SyncedSettings
        var groups: [Grant]
    }
    /// What was last agreed with the server, to tell local edits from remote ones.
    private struct Baselines: Codable {
        var setup: AccountSetup?
        var progress: PlaybackSyncSnapshot?
        var groups: [String: SyncedSettings] = [:]
        var lastSync: Date?
        var initialImport: InitialImport?
        var pendingProgressBase: PlaybackSyncSnapshot?
        var pendingProgressIDs: Set<String> = []
        enum CodingKeys: String, CodingKey {
            case setup = "profile", progress, groups, lastSync, initialImport, pendingProgressBase, pendingProgressIDs
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
    private struct GroupChoice {
        let grant: Grant
        let local: SyncedSettings
        let remote: SyncedSettings
        let merge: SyncedSettings.Merge
        let revision: String?
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
    @ObservationIgnored private var groupChoice: GroupChoice?
    /// Replaced on disconnect, so results that arrive late are dropped.
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var observer: AccountSyncDefaultsObserver?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var isCheckQueued = false
    @ObservationIgnored private var lastObservedSettings: SyncedSettings?
    @ObservationIgnored private var lastObservedProgress: PlaybackSyncSnapshot?

    public convenience init(addons: AddonStore, library: LibraryStore, defaults: UserDefaults = .standard) {
        Self.removeRetiredEndpointSync(defaults: defaults)
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
            sharedGroups = saved.groups.map(\.metadata)
            try restoreBaselines(saved)
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
            var proposed = Connection(endpoint: code.endpoint, token: identity.token, accountID: identity.accountID,
                                      displayName: identity.displayName, deviceID: identity.deviceID, key: key,
                                      groups: code.groups ?? [], localSettings: try localSetup.current.validated(),
                                      requiresInitialChoice: true)
            let client = try client(proposed)
            let memberships = try await client.me().groups
            let setupDocument = try await client.fetch(Self.setupPath)
            let progressDocument = try await client.fetch(Self.progressPath)
            try ensureCurrent(id)
            let remoteSetup = try openSetup(setupDocument, key: key)
            let remoteProgress = try openProgress(progressDocument, key: key)
            proposed.groups = try validatedGrants(remoteSetup?.groups ?? proposed.groups, memberships: memberships)
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
            sharedGroups = proposed.groups.map(\.metadata)
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
        groupChoice = nil
        needsChoice = false
        sharedGroups = []
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
            if choice?.settings == nil { try await syncSetup(client: client, memberships: identity.groups, id: id) }
            try await syncGroups(client: client, id: id)
            try await syncProgress(client: client, id: id)
            lastSync = .now
            baselines.lastSync = lastSync
            try saveBaselines()
            if !needsChoice { status = .upToDate }
        }
    }

    private func syncSetup(client: AccountSyncClient, memberships: [SyncGroup], id: UUID) async throws {
        guard var connection else { return }
        let cipher = try AccountSyncCipher(key: connection.key, resource: Self.setupResource)
        try await retryingConflicts {
            let document = try await client.fetch(Self.setupPath)
            try ensureCurrent(id)
            let remote = try openSetup(document, key: connection.key) ?? AccountSetup(settings: SyncedSettings(), groups: [])
            let known = connection.groups + remote.groups.filter { incoming in !connection.groups.contains { $0.id == incoming.id } }
            connection.groups = try validatedGrants(known, memberships: memberships)
            try adoptGroups(of: connection)
            let scopes = connection.sharedCategories
            let local = localSetup.current.excluding(scopes)
            let incoming = remote.settings.excluding(scopes)
            let merged = SyncedSettings.merged(base: baselines.setup?.settings.excluding(scopes) ?? incoming,
                                               local: local, remote: incoming)
            guard merged.conflicts.isEmpty else {
                chooseSettings(SettingsChoice(local: local, remote: incoming, merge: merged, revision: document?.revision))
                return
            }
            let setup = AccountSetup(settings: merged.settings, groups: connection.groups)
            var revision = document?.revision
            if setup != remote || document == nil {
                revision = try await client.put(cipher.seal(setup), resource: Self.setupPath, revision: document?.revision)
                try ensureCurrent(id)
            }
            baselines.setup = setup
            let latest = localSetup.current.excluding(scopes)
            let rebased = SyncedSettings.merged(base: local, local: latest, remote: merged.settings)
            if rebased.conflicts.isEmpty {
                try localSetup.apply(rebased.settings, categories: connection.privateCategories)
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
                    needsChoice = choice != nil || groupChoice != nil
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
            try saveBaselines()
        }
    }

    // MARK: Choosing

    public func resolve(useLocal: Bool) async {
        if choice?.requiresRefresh == true { await refreshInitialChoice(); return }
        if groupChoice != nil { await resolveShared(useLocal: useLocal); return }
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
        var scopes: Set<SyncCategory> { connection.sharedCategories }
    }

    private func resolve(_ selected: Choice, useLocal: Bool, connection: Connection, id: UUID) async throws {
        var selected = selected
        let context = Resolution(client: try client(connection), connection: connection, id: id,
                                 settings: localSetup.current.excluding(connection.sharedCategories),
                                 progress: library.playbackSyncSnapshot)
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
        needsChoice = groupChoice != nil
        lastSync = .now
        baselines.lastSync = lastSync
        try saveBaselines()
        try await syncGroups(client: context.client, id: id)
        if !needsChoice { status = .upToDate }
    }

    /// - Returns: Whether this device changed since the choice was shown, so it was previewed again.
    private func previewLocalChanges(_ selected: inout Choice, in context: Resolution) -> Bool {
        let settings = context.settings, progress = context.progress
        if var pending = selected.settings, settings != pending.local {
            pending.local = settings
            pending.merge = SyncedSettings.merged(base: baselines.setup?.settings.excluding(context.scopes) ?? pending.remote,
                                                  local: settings, remote: pending.remote)
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
                pending.remote = (try openSetup(latest, key: connection.key)?.settings ?? SyncedSettings())
                    .excluding(connection.sharedCategories)
                pending.revision = latest?.revision
                if !selected.initial {
                    pending.local = settings
                    pending.merge = SyncedSettings.merged(base: baselines.setup?.settings ?? pending.remote,
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
        let setup = AccountSetup(settings: settings.excluding(connection.sharedCategories), groups: connection.groups)
        let cipher = try AccountSyncCipher(key: connection.key, resource: Self.setupResource)
        let revision = try await client.put(cipher.seal(setup), resource: Self.setupPath, revision: pending.revision)
        try ensureCurrent(id)
        baselines.setup = setup
        let current = localSetup.current.excluding(connection.sharedCategories)
        let rebased = SyncedSettings.merged(base: starting, local: current, remote: setup.settings)
        guard rebased.conflicts.isEmpty else {
            selected.settings = SettingsChoice(local: current, remote: setup.settings, merge: rebased, revision: revision)
            selected.initial = false
            choice = selected
            status = .choosingAgain(.syncing)
            try saveBaselines()
            return false
        }
        try localSetup.apply(rebased.settings, categories: connection.privateCategories)
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

    // MARK: Devices and shared setups

    public func makeDeviceCode() async throws -> String {
        guard let connection, !isSyncing, !needsChoice else { throw SyncError.notReady }
        let id = generation
        let invitation = try await client(connection).invite(kind: .device)
        try ensureCurrent(id)
        return try AccountSyncCode(kind: .device, endpoint: connection.endpoint, code: invitation.code,
                                   key: connection.key, groups: connection.groups).encoded()
    }

    public func makeShareCode(categories: Set<SyncCategory>) async throws -> String {
        guard var connection, !isSyncing, !needsChoice, !categories.isEmpty else { throw SyncError.notReady }
        let id = generation
        isSyncing = true
        defer { if generation == id { finish() } }
        let client = try client(connection)
        let existing = connection.groups.first { $0.categories == categories }
        guard existing != nil || connection.groups.allSatisfy({ $0.categories.isDisjoint(with: categories) }) else {
            throw SyncError.overlappingGroup
        }
        let invitation = try await client.invite(kind: .share, categories: categories, groupID: existing?.id)
        guard let groupID = invitation.groupID else { throw SyncError.invalidResponse }
        guard generation == id else {
            if existing == nil { try await client.leaveGroup(groupID) }
            throw CancellationError()
        }
        var grant = existing ?? Grant(id: groupID, name: "Shared setup", categories: categories,
                                      key: AccountSyncCipher.generateKey(), initializing: true)
        if existing == nil {
            connection.groups.append(grant)
            do { try storage.save(JSONEncoder().encode(connection)) }
            catch {
                // The server group has no published key or members yet; release its
                // category reservation if local credential storage cannot retain it.
                try await client.leaveGroup(grant.id)
                throw error
            }
            self.connection = connection
            sharedGroups = connection.groups.map(\.metadata)
        }
        if grant.initializing == true {
            let shared = localSetup.current.only(categories)
            let cipher = try AccountSyncCipher(key: grant.key, resource: grant.cipherResource)
            let path = try client.groupResource(grant.id)
            let existingDocument = try await client.fetch(path)
            let published = try existingDocument.map { try cipher.open($0, as: SyncedSettings.self).validated().only(categories) }
            if existingDocument == nil { _ = try await client.put(cipher.seal(shared), resource: path, revision: nil) }
            try ensureCurrent(id)
            grant.initializing = nil
            connection.groups = connection.groups.map { $0.id == grant.id ? grant : $0 }
            self.connection = connection
            sharedGroups = connection.groups.map(\.metadata)
            baselines.groups[grant.id] = published ?? shared
            try persistConnection()
            try saveBaselines()
            // The account document carries group keys to this person's own devices only.
            try await syncSetup(client: client, memberships: try await client.me().groups, id: id)
        }
        return try AccountSyncCode(kind: .share, endpoint: connection.endpoint, code: invitation.code,
                                   key: grant.key, groupID: grant.id, categories: categories).encoded()
    }

    public func joinShare(code string: String) async {
        guard var connection, !needsChoice else { return }
        await run { id in
            let code = try AccountSyncCode(decoding: string)
            guard code.kind == .share, code.endpoint == connection.endpoint,
                  let key = code.key, let groupID = code.groupID, let categories = code.categories, !categories.isEmpty
            else { throw SyncError.wrongCode }
            guard AccountSyncCipher.isValidKey(key) else { throw SyncError.invalidKey }
            guard connection.groups.allSatisfy({ $0.categories.isDisjoint(with: categories) }) else {
                throw SyncError.overlappingGroup
            }
            let client = try client(connection)
            let group = try await client.join(code: code.code)
            let grant = Grant(id: group.id, name: group.name, categories: categories, key: key)
            let incoming: SyncedSettings
            do {
                try ensureCurrent(id)
                guard group.id == groupID, group.categories == categories else { throw SyncError.invalidResponse }
                guard let document = try await client.fetch(try client.groupResource(group.id)) else {
                    throw SyncError.invalidResponse
                }
                incoming = try AccountSyncCipher(key: key, resource: grant.cipherResource)
                    .open(document, as: SyncedSettings.self).validated()
                try ensureCurrent(id)
                connection.groups.append(grant)
                try storage.save(JSONEncoder().encode(connection))
            } catch {
                // Leave a membership this device can't use, so the person can join again.
                try await client.leaveGroup(group.id)
                throw error
            }
            self.connection = connection
            sharedGroups = connection.groups.map(\.metadata)
            baselines.groups[group.id] = incoming.only(categories)
            try localSetup.apply(incoming, categories: categories)
            try saveBaselines()
            try await syncSetup(client: client, memberships: try await client.me().groups, id: id)
            status = .sharedSetupJoined
        }
    }

    public func leaveGroup(id groupID: String) async {
        guard var connection else { return }
        await run { id in
            try await client(connection).leaveGroup(groupID)
            try ensureCurrent(id)
            connection.groups.removeAll { $0.id == groupID }
            self.connection = connection
            sharedGroups = connection.groups.map(\.metadata)
            baselines.groups[groupID] = nil
            try persistConnection()
            try saveBaselines()
            status = .sharedSetupLeft
        }
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

    private func syncGroups(client: AccountSyncClient, id: UUID) async throws {
        guard let connection else { return }
        for grant in connection.groups where groupChoice?.grant.id != grant.id {
            if try await syncGroup(grant, client: client, id: id) { return }
        }
    }

    /// - Returns: Whether the group waits for a choice, which holds back the groups after it.
    private func syncGroup(_ grant: Grant, client: AccountSyncClient, id: UUID) async throws -> Bool {
        let cipher = try AccountSyncCipher(key: grant.key, resource: grant.cipherResource)
        let path = try client.groupResource(grant.id)
        var waiting = false
        try await retryingConflicts {
            guard let document = try await client.fetch(path) else { throw SyncError.invalidResponse }
            try ensureCurrent(id)
            let remote = try cipher.open(document, as: SyncedSettings.self).validated().only(grant.categories)
            let local = localSetup.current.only(grant.categories)
            guard let baseline = baselines.groups[grant.id] else {
                try localSetup.apply(remote, categories: grant.categories)
                baselines.groups[grant.id] = remote
                try saveBaselines()
                return
            }
            let merged = SyncedSettings.merged(base: baseline, local: local, remote: remote)
            guard merged.conflicts.isEmpty else {
                waiting = true
                chooseShared(GroupChoice(grant: grant, local: local, remote: remote, merge: merged, revision: document.revision))
                return
            }
            var revision = document.revision
            if merged.settings != remote {
                revision = try await client.put(cipher.seal(merged.settings), resource: path, revision: document.revision)
                try ensureCurrent(id)
            }
            let current = localSetup.current.only(grant.categories)
            let rebased = SyncedSettings.merged(base: local, local: current, remote: merged.settings)
            guard rebased.conflicts.isEmpty else {
                waiting = true
                chooseShared(GroupChoice(grant: grant, local: current, remote: merged.settings, merge: rebased, revision: revision))
                return
            }
            try localSetup.apply(rebased.settings, categories: grant.categories)
            baselines.groups[grant.id] = merged.settings
            try saveBaselines()
        }
        return waiting
    }

    /// One shared setup is reviewed at a time; a second conflict waits for the next sync.
    private func chooseShared(_ pending: GroupChoice) {
        guard groupChoice == nil else { return }
        groupChoice = pending
        needsChoice = true
        status = .choosingSharedSettings
    }

    private func resolveShared(useLocal: Bool) async {
        guard let connection, let selected = groupChoice else { return }
        await run { id in
            do {
                let client = try client(connection)
                let path = try client.groupResource(selected.grant.id)
                let resolved = selected.merge.settings.replacing(selected.merge.conflicts,
                                                                 from: useLocal ? selected.local : selected.remote)
                let cipher = try AccountSyncCipher(key: selected.grant.key, resource: selected.grant.cipherResource)
                let revision = try await client.put(cipher.seal(resolved), resource: path, revision: selected.revision)
                try ensureCurrent(id)
                let current = localSetup.current.only(selected.grant.categories)
                let rebased = SyncedSettings.merged(base: selected.local, local: current, remote: resolved)
                baselines.groups[selected.grant.id] = resolved
                if rebased.conflicts.isEmpty {
                    try localSetup.apply(rebased.settings, categories: selected.grant.categories)
                    groupChoice = nil
                    needsChoice = choice != nil
                    status = needsChoice ? .choosingRemaining : .upToDate
                } else {
                    groupChoice = GroupChoice(grant: selected.grant, local: current, remote: resolved, merge: rebased, revision: revision)
                }
                try saveBaselines()
                if groupChoice == nil { try await syncGroups(client: client, id: id) }
            } catch SyncError.conflict {
                guard generation == id else { return }
                groupChoice = nil
                needsChoice = choice != nil
                errorMessage = SyncError.conflict.localizedDescription
                status = .sharedSetupChanged
            }
        }
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

    private func adoptGroups(of updated: Connection) throws {
        guard updated.groups != connection?.groups else { return }
        connection = updated
        sharedGroups = updated.groups.map(\.metadata)
        try persistConnection()
        if let pendingGroup = groupChoice, !updated.groups.contains(where: { $0.id == pendingGroup.grant.id }) {
            groupChoice = nil
            needsChoice = choice != nil
        }
    }

    private func openSetup(_ document: AccountSyncDocument?, key: String) throws -> AccountSetup? {
        guard let document else { return nil }
        let setup: AccountSetup = try AccountSyncCipher(key: key, resource: Self.setupResource).open(document)
        return AccountSetup(settings: try setup.settings.validated(), groups: setup.groups)
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

    /// Group grants must match the server's memberships, and each category belongs to one group.
    private func validatedGrants(_ grants: [Grant], memberships: [SyncGroup]) throws -> [Grant] {
        var scopes = Set<SyncCategory>()
        var seen = Set<String>()
        return try grants.filter { grant in memberships.contains { $0.id == grant.id } }.map { grant in
            guard seen.insert(grant.id).inserted, !grant.categories.isEmpty,
                  memberships.contains(where: { $0.id == grant.id && $0.categories == grant.categories }),
                  scopes.isDisjoint(with: grant.categories) else { throw SyncError.overlappingGroup }
            guard AccountSyncCipher.isValidKey(grant.key) else { throw SyncError.invalidKey }
            scopes.formUnion(grant.categories)
            return grant
        }
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
           localSetup.current.excluding(connection?.sharedCategories ?? []) != baselines.setup?.settings
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

    /// The single-user endpoint sync this replaced kept a server password and recovery key
    /// in Keychain; remove them rather than leave secrets nothing reads.
    private static func removeRetiredEndpointSync(defaults: UserDefaults) {
        try? Keychain.remove(service: "li.tjh.MediaApp.configuration-sync", account: "connection")
        defaults.removeObject(forKey: "configurationSyncBaseline")
        defaults.removeObject(forKey: "configurationSyncDate")
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
