import CryptoKit
import Foundation
import Observation
import Security

/// Private account state and deliberately shared setup use separate encryption keys.
@MainActor @Observable
public final class AccountSync {
    public private(set) var isConnected = false
    public private(set) var isSyncing = false
    public private(set) var status = "Off"
    public private(set) var errorMessage: String?
    public private(set) var lastSync: Date?
    public private(set) var needsChoice = false
    public private(set) var sharedGroups: [SyncGroup] = []
    public private(set) var devices: [SyncDevice] = []
    @ObservationIgnored public var beforeProfileChange: (() -> Void)?
    public var displayName: String? { connection?.displayName }
    public var endpoint: String? { connection?.endpoint }
    public var recoveryKey: String? { connection?.key }
    public var choiceSummary: String {
        if let groupChoice { return "Shared setup: " + groupChoice.grant.categories.map(\.name).sorted().joined(separator: ", ") }
        if let choice, choice.initial { return "Choose whether to bring this device’s setup and playback into this account, or use the account’s saved data." }
        return "Choose only the conflicting settings or playback positions. Independent changes are kept."
    }
    public var conflictingProgressIDs: [String] { choice?.progress?.conflictingIDs.sorted() ?? [] }

    struct Grant: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let categories: Set<SyncCategory>
        let key: String
        var initializing: Bool? = nil
        var metadata: SyncGroup { SyncGroup(id: id, name: name, categories: categories) }
    }
    struct Connection: Codable, Sendable {
        let endpoint: String
        let token: String
        let accountID: String
        let displayName: String
        let deviceID: String
        let key: String
        var groups: [Grant]
        var localSettings: SyncedConfiguration?
        var requiresInitialChoice: Bool?
        var profileID: String {
            SHA256.hash(data: Data("\(endpoint)|\(accountID)".utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }
    struct Storage {
        var load: () throws -> Data?
        var save: (Data) throws -> Void
        var remove: () throws -> Void
    }
    private struct Code: Codable {
        var version = 2
        let kind: String
        let endpoint: String
        let code: String
        var key: String?
        var groupID: String?
        var categories: Set<SyncCategory>?
        var groups: [Grant]?
    }
    private struct Profile: Codable, Equatable {
        var settings: SyncedConfiguration
        var groups: [Grant]
    }
    private struct Baselines: Codable {
        var profile: Profile?
        var progress: PlaybackSyncSnapshot?
        var groups: [String: SyncedConfiguration] = [:]
        var lastSync: Date?
        var initialImport: InitialImport?
        var pendingProgressBase: PlaybackSyncSnapshot?
        var pendingProgressIDs: Set<String> = []
    }
    private struct InitialImport: Codable {
        var settings: SyncedConfiguration
        var progress: PlaybackSyncSnapshot
    }
    private struct Choice {
        var localSettings: SyncedConfiguration
        var remoteSettings: SyncedConfiguration
        var configuration: ConfigurationMerge?
        var settingsRevision: String?
        var localProgress: PlaybackSyncSnapshot
        var remoteProgress: PlaybackSyncSnapshot
        var progress: PlaybackSyncMerge?
        var progressRevision: String?
        var initial: Bool
        var progressBase: PlaybackSyncSnapshot? = nil
        var requiresRefresh = false
    }
    @ObservationIgnored private let addons: AddonStore
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storage: Storage
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var connection: Connection?
    @ObservationIgnored private var baselines = Baselines()
    private struct GroupChoice {
        let grant: Grant
        let local: SyncedConfiguration
        let remote: SyncedConfiguration
        let merge: ConfigurationMerge
        let revision: String
    }
    @ObservationIgnored private var groupChoice: GroupChoice?
    @ObservationIgnored private var choice: Choice?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var observer: AccountSyncDefaultsObserver?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var lastObservedSettings: SyncedConfiguration?
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
    init(addons: AddonStore, library: LibraryStore, defaults: UserDefaults, storage: Storage, session: URLSession) {
        self.addons = addons
        self.library = library
        self.defaults = defaults
        self.storage = storage
        self.session = session
        do {
            if let data = try storage.load() {
                let saved = try JSONDecoder().decode(Connection.self, from: data)
                _ = try client(saved)
                _ = try AccountSyncCipher(key: saved.key, resource: "configuration")
                connection = saved
                try activateSettingsProfile(saved)
                library.activateProfile(id: saved.profileID)
                isConnected = true
                status = "Ready to sync"
                sharedGroups = saved.groups.map(\.metadata)
                try restoreBaselines(saved)
                if saved.requiresInitialChoice == true || baselines.profile == nil {
                    let initial = baselines.initialImport
                    choice = Choice(localSettings: initial?.settings ?? saved.localSettings ?? SyncedConfiguration(),
                                    remoteSettings: SyncedConfiguration(), localProgress: initial?.progress ?? PlaybackSyncSnapshot(),
                                    remoteProgress: PlaybackSyncSnapshot(), initial: true, requiresRefresh: true)
                    needsChoice = true
                    status = "Choose the initial setup"
                }
            } else {
                try activateSettingsProfile(nil)
                library.activateProfile(id: nil)
            }
        } catch {
            if connection == nil {
                do { try activateSettingsProfile(nil) }
                catch { fail(error) }
                library.activateProfile(id: nil)
            } else if let connection {
                choice = Choice(localSettings: settingsSnapshot(), remoteSettings: SyncedConfiguration(),
                                localProgress: library.playbackSyncSnapshot, remoteProgress: PlaybackSyncSnapshot(),
                                initial: true, requiresRefresh: true)
                needsChoice = true
                self.connection = connection
            }
            fail(error)
        }
        rememberObserved()
        observer = AccountSyncDefaultsObserver { [weak self] in
            Task { @MainActor [weak self] in self?.localChanged() }
        }
    }

    public func connect(code string: String, deviceName: String = "loge", recoveryKey: String? = nil) async {
        guard !isSyncing, !isConnected else { return }
        let id = generation
        isSyncing = true
        errorMessage = nil
        defer { if generation == id { finish() } }
        do {
            let code = try decodeCode(string)
            guard ["account", "device"].contains(code.kind) else { throw SyncError.wrongCode }
            guard code.kind != "device" || code.key != nil else { throw SyncError.recoveryRequired }
            let suppliedKey = code.key ?? recoveryKey
            let key = suppliedKey ?? ConfigurationCipher.generateKey()
            let cipher = try AccountSyncCipher(key: key, resource: "configuration")
            let unauthenticated = try AccountSyncClient(endpoint: code.endpoint, session: session)
            let identity = try await unauthenticated.redeem(code: code.code, deviceName: String(deviceName.prefix(80)), hasRecoveryKey: suppliedKey != nil)
            guard generation == id else { return }
            if identity.requiresRecoveryKey == true, suppliedKey == nil { throw SyncError.recoveryRequired }
            var proposed = Connection(endpoint: code.endpoint, token: identity.token, accountID: identity.accountID,
                                      displayName: identity.displayName, deviceID: identity.deviceID, key: key, groups: code.groups ?? [],
                                      localSettings: try settingsSnapshot().validated())
            proposed.requiresInitialChoice = true
            let client = try self.client(proposed)
            let metadata = try await client.me()
            let document = try await client.fetch("documents/configuration")
            let progressDocument = try await client.fetch("documents/progress")
            guard generation == id else { return }
            let profile: Profile? = try document.map { try cipher.open($0) }
            let remoteProgress: PlaybackSyncSnapshot = try progressDocument.map {
                try AccountSyncCipher(key: key, resource: "progress").open($0, as: PlaybackSyncSnapshot.self).validated()
            } ?? PlaybackSyncSnapshot()
            if let profile {
                _ = try profile.settings.validated()
                proposed.groups = try validatedGrants(profile.groups, memberships: metadata.groups)
            } else { proposed.groups = try validatedGrants(proposed.groups, memberships: metadata.groups) }
            beforeProfileChange?()
            let localSettings = try settingsSnapshot().validated()
            let localProgress = try library.playbackSyncSnapshot.validated()
            defaults.set(try JSONEncoder().encode(localSettings), forKey: "accountSyncLocalSetup")
            let pendingBaselines = Baselines(initialImport: InitialImport(settings: localSettings, progress: localProgress))
            try saveBaselines(pendingBaselines, connection: proposed)
            try storage.save(JSONEncoder().encode(proposed))
            connection = proposed
            isConnected = true
            try activateSettingsProfile(proposed)
            library.activateProfile(id: proposed.profileID)
            baselines = pendingBaselines
            sharedGroups = proposed.groups.map(\.metadata)
            choice = Choice(localSettings: localSettings, remoteSettings: profile?.settings ?? SyncedConfiguration(),
                            settingsRevision: document?.revision, localProgress: localProgress,
                            remoteProgress: remoteProgress, progressRevision: progressDocument?.revision, initial: true)
            needsChoice = true
            status = "Choose the initial setup"
        } catch {
            guard generation == id else { return }
            fail(error)
        }
    }

    public func sync() async {
        if choice?.initial == true {
            if choice?.requiresRefresh == true { await refreshInitialChoice() }
            return
        }
        guard let connection, !isSyncing else { return }
        let id = generation
        isSyncing = true
        errorMessage = nil
        status = "Syncing…"
        defer { if generation == id { finish() } }
        do {
            let client = try client(connection)
            let identity = try await client.me()
            guard generation == id else { return }
            guard identity.accountID == connection.accountID, identity.deviceID == connection.deviceID else {
                throw ConfigurationSyncError.unauthorized
            }
            if choice?.configuration == nil { try await syncProfile(client: client, memberships: identity.groups, id: id) }
            guard generation == id else { return }
            try await syncGroups(client: client, id: id)
            guard generation == id else { return }
            try await syncProgress(client: client, id: id)
            guard generation == id else { return }
            lastSync = .now
            baselines.lastSync = lastSync
            try saveBaselines()
            if !needsChoice { status = "Up to date" }
        } catch {
            guard generation == id else { return }
            fail(error)
        }
    }

    private func syncProfile(client: AccountSyncClient, memberships: [SyncGroup], id: UUID) async throws {
        guard var connection else { return }
        let cipher = try AccountSyncCipher(key: connection.key, resource: "configuration")
        for attempt in 0..<3 {
            let document = try await client.fetch("documents/configuration")
            guard generation == id else { return }
            let remote: Profile = try document.map { try cipher.open($0) } ?? Profile(settings: SyncedConfiguration(), groups: [])
            _ = try remote.settings.validated()
            let known = connection.groups + remote.groups.filter { incoming in !connection.groups.contains { $0.id == incoming.id } }
            connection.groups = try validatedGrants(known, memberships: memberships)
            if let pendingGroup = groupChoice, !connection.groups.contains(where: { $0.id == pendingGroup.grant.id }) {
                groupChoice = nil
                needsChoice = choice != nil
            }
            let scopes = Set(connection.groups.flatMap(\.categories))
            let local = settingsSnapshot().excluding(scopes)
            let incoming = remote.settings.excluding(scopes)
            let base = baselines.profile?.settings.excluding(scopes) ?? incoming
            let merged = SyncedConfiguration.merged(base: base, local: local, remote: incoming)
            if !merged.conflicts.isEmpty {
                let progress = library.playbackSyncSnapshot
                var pendingChoice = choice ?? Choice(localSettings: local, remoteSettings: incoming,
                                                    localProgress: progress, remoteProgress: progress, initial: false)
                pendingChoice.localSettings = local
                pendingChoice.remoteSettings = incoming
                pendingChoice.configuration = merged
                pendingChoice.settingsRevision = document?.revision
                choice = pendingChoice
                needsChoice = true
                status = "Choose conflicting settings"
                return
            }
            let profile = Profile(settings: merged.configuration, groups: connection.groups)
            if profile != remote || document == nil {
                do { _ = try await client.put(cipher.seal(profile), resource: "documents/configuration", revision: document?.revision) }
                catch ConfigurationSyncError.conflict where attempt < 2 { continue }
                guard generation == id else { return }
            }
            let latest = settingsSnapshot().excluding(scopes)
            let rebased = SyncedConfiguration.merged(base: local, local: latest, remote: merged.configuration)
            self.connection = connection
            sharedGroups = connection.groups.map(\.metadata)
            try persistConnection()
            baselines.profile = profile
            if rebased.conflicts.isEmpty { try applySettings(rebased.configuration, excluding: scopes) }
            else {
                let progress = library.playbackSyncSnapshot
                var pendingChoice = choice ?? Choice(localSettings: latest, remoteSettings: merged.configuration,
                                                    localProgress: progress, remoteProgress: progress, initial: false)
                pendingChoice.localSettings = latest
                pendingChoice.remoteSettings = merged.configuration
                pendingChoice.configuration = rebased
                choice = pendingChoice
                needsChoice = true
                status = "Choose conflicting settings"
            }
            try saveBaselines()
            return
        }
    }

    private func syncProgress(client: AccountSyncClient, id: UUID) async throws {
        guard let connection else { return }
        let cipher = try AccountSyncCipher(key: connection.key, resource: "progress")
        for attempt in 0..<3 {
            let document = try await client.fetch("documents/progress")
            guard generation == id else { return }
            let remote: PlaybackSyncSnapshot = try document.map { try cipher.open($0, as: PlaybackSyncSnapshot.self).validated() } ?? PlaybackSyncSnapshot()
            let local = try library.playbackSyncSnapshot.validated()
            var base = baselines.progress ?? remote
            if let original = baselines.pendingProgressBase {
                base = base.replacing(baselines.pendingProgressIDs, from: original, references: [local, remote])
            }
            let merged = PlaybackSyncSnapshot.merged(base: base, local: local, remote: remote)
            // Independent titles keep syncing while ambiguous episodes wait for a choice.
            let result = merged.resolving(useLocal: false)
            var committedRevision = document?.revision
            if result != remote || document == nil {
                do { committedRevision = try await client.put(cipher.seal(result), resource: "documents/progress", revision: document?.revision) }
                catch ConfigurationSyncError.conflict where attempt < 2 { continue }
                guard generation == id else { return }
            }
            let current = library.playbackSyncSnapshot
            let localResult = PlaybackSyncSnapshot.merged(base: base, local: current, remote: result)
            try library.applyPlaybackSyncSnapshot(localResult.snapshot)
            baselines.progress = result
            if !localResult.conflictingIDs.isEmpty {
                let progressMerge = localResult
                baselines.pendingProgressBase = base
                baselines.pendingProgressIDs = localResult.conflictingIDs
                if var existing = choice {
                    existing.localProgress = current
                    existing.remoteProgress = result
                    existing.progress = progressMerge
                    existing.progressRevision = committedRevision
                    existing.progressBase = base
                    choice = existing
                } else {
                    choice = Choice(localSettings: settingsSnapshot(), remoteSettings: settingsSnapshot(),
                                    localProgress: current, remoteProgress: result,
                                    progress: progressMerge, progressRevision: committedRevision, initial: false, progressBase: base)
                }
                needsChoice = true
                status = "Choose playback position"
            } else {
                baselines.pendingProgressBase = nil
                baselines.pendingProgressIDs = []
                if var pendingChoice = choice, pendingChoice.progress != nil {
                    pendingChoice.progress = nil
                    pendingChoice.progressBase = nil
                    choice = pendingChoice.configuration == nil ? nil : pendingChoice
                    needsChoice = choice != nil || groupChoice != nil
                }
            }
            try saveBaselines()
            return
        }
    }

    public func resolve(useLocal: Bool) async {
        if choice?.requiresRefresh == true { await refreshInitialChoice(); return }
        if groupChoice != nil { await resolveShared(useLocal: useLocal); return }
        guard let connection, var selected = choice, !isSyncing else { return }
        let id = generation
        let startingSettings = settingsSnapshot()
        let startingProgress = library.playbackSyncSnapshot
        isSyncing = true
        errorMessage = nil
        defer { if generation == id { finish() } }
        do {
            let client = try client(connection)
            let scopes = Set(connection.groups.flatMap(\.categories))
            if !selected.initial, selected.configuration != nil,
               startingSettings.excluding(scopes) != selected.localSettings {
                selected.localSettings = startingSettings.excluding(scopes)
                selected.configuration = SyncedConfiguration.merged(base: baselines.profile?.settings.excluding(scopes) ?? selected.remoteSettings,
                                                                   local: selected.localSettings, remote: selected.remoteSettings)
                choice = selected
                status = "Settings changed on this device. Choose again."
                return
            }
            if !selected.initial, selected.progress != nil, startingProgress != selected.localProgress {
                selected.localProgress = startingProgress
                selected.progress = PlaybackSyncSnapshot.merged(base: selected.progressBase ?? baselines.progress ?? selected.remoteProgress,
                                                               local: startingProgress, remote: selected.remoteProgress)
                choice = selected
                status = "Playback changed on this device. Choose again."
                return
            }
            let profileCipher = try AccountSyncCipher(key: connection.key, resource: "configuration")
            let progressCipher = try AccountSyncCipher(key: connection.key, resource: "progress")
            let resolveSettings = selected.initial || selected.configuration != nil
            let resolveProgress = selected.initial || selected.progress != nil
            // Check every captured revision before writing either resource. A fresh
            // revision is never permission to overwrite a stale choice.
            if resolveSettings {
                let latest = try await client.fetch("documents/configuration")
                guard generation == id else { return }
                if latest?.revision != selected.settingsRevision {
                    let profile: Profile = try latest.map { try profileCipher.open($0) } ?? Profile(settings: SyncedConfiguration(), groups: [])
                    _ = try profile.settings.validated()
                    selected.remoteSettings = profile.settings.excluding(scopes)
                    selected.settingsRevision = latest?.revision
                    if !selected.initial {
                        selected.localSettings = startingSettings.excluding(scopes)
                        selected.configuration = SyncedConfiguration.merged(base: baselines.profile?.settings ?? selected.remoteSettings,
                                                                           local: selected.localSettings, remote: selected.remoteSettings)
                    }
                    choice = selected
                    status = "Server setup changed. Choose again."
                    return
                }
            }
            if resolveProgress {
                let latest = try await client.fetch("documents/progress")
                guard generation == id else { return }
                if latest?.revision != selected.progressRevision {
                    selected.remoteProgress = try latest.map { try progressCipher.open($0, as: PlaybackSyncSnapshot.self).validated() } ?? PlaybackSyncSnapshot()
                    selected.progressRevision = latest?.revision
                    if !selected.initial {
                        selected.localProgress = startingProgress
                        selected.progress = PlaybackSyncSnapshot.merged(base: baselines.progress ?? selected.remoteProgress,
                                                                       local: startingProgress, remote: selected.remoteProgress)
                    }
                    choice = selected
                    status = "Playback changed on another device. Choose again."
                    return
                }
            }
            if resolveSettings {
                var settings = selected.configuration?.configuration ?? (useLocal ? selected.localSettings : selected.remoteSettings)
                if let merge = selected.configuration {
                    settings = settings.replacing(merge.conflicts, from: useLocal ? selected.localSettings : selected.remoteSettings)
                }
                let profile = Profile(settings: settings.excluding(scopes), groups: connection.groups)
                let revision = try await client.put(profileCipher.seal(profile), resource: "documents/configuration", revision: selected.settingsRevision)
                guard generation == id else { return }
                baselines.profile = profile
                let current = settingsSnapshot().excluding(scopes)
                let rebased = SyncedConfiguration.merged(base: startingSettings.excluding(scopes), local: current, remote: profile.settings)
                if rebased.conflicts.isEmpty {
                    try applySettings(rebased.configuration, excluding: scopes)
                    selected.configuration = nil
                    selected.settingsRevision = revision
                    selected.remoteSettings = profile.settings
                } else {
                    selected.localSettings = current
                    selected.remoteSettings = profile.settings
                    selected.configuration = rebased
                    selected.settingsRevision = revision
                    selected.initial = false
                    choice = selected
                    status = "Settings changed while syncing. Choose again."
                    try saveBaselines()
                    return
                }
            }
            if resolveProgress {
                let progress = selected.progress?.resolving(useLocal: useLocal)
                    ?? (useLocal ? selected.localProgress : selected.remoteProgress)
                let revision = try await client.put(progressCipher.seal(progress), resource: "documents/progress", revision: selected.progressRevision)
                guard generation == id else { return }
                baselines.progress = progress
                let current = library.playbackSyncSnapshot
                let rebased = PlaybackSyncSnapshot.merged(base: startingProgress, local: current, remote: progress)
                try library.applyPlaybackSyncSnapshot(rebased.snapshot)
                if !rebased.conflictingIDs.isEmpty {
                    baselines.pendingProgressBase = startingProgress
                    baselines.pendingProgressIDs = rebased.conflictingIDs
                    selected.localProgress = current
                    selected.remoteProgress = progress
                    selected.progress = rebased
                    selected.progressRevision = revision
                    selected.initial = false
                    choice = selected
                    status = "Playback changed while syncing. Choose again."
                    try saveBaselines()
                    return
                }
                baselines.pendingProgressBase = nil
                baselines.pendingProgressIDs = []
            }
            if selected.initial {
                self.connection?.requiresInitialChoice = false
                baselines.initialImport = nil
                try persistConnection()
            }
            choice = nil
            needsChoice = groupChoice != nil
            try saveBaselines()
            try await syncGroups(client: client, id: id)
            guard generation == id else { return }
            if !needsChoice { status = "Up to date" }
            lastSync = .now
        } catch ConfigurationSyncError.conflict {
            guard generation == id else { return }
            // The next choice revalidates the captured revisions and refreshes its preview.
            status = "Another device saved changes. Choose again."
            errorMessage = ConfigurationSyncError.conflict.localizedDescription
        } catch { if generation == id { fail(error) } }
    }

    private func refreshInitialChoice() async {
        guard let connection, var selected = choice, selected.initial, !isSyncing else { return }
        let id = generation
        isSyncing = true
        defer { if generation == id { finish() } }
        do {
            let client = try client(connection)
            let profileDocument = try await client.fetch("documents/configuration")
            let progressDocument = try await client.fetch("documents/progress")
            guard generation == id else { return }
            let profile: Profile? = try profileDocument.map {
                try AccountSyncCipher(key: connection.key, resource: "configuration").open($0)
            }
            selected.remoteSettings = try profile?.settings.validated() ?? SyncedConfiguration()
            selected.remoteProgress = try progressDocument.map {
                try AccountSyncCipher(key: connection.key, resource: "progress").open($0, as: PlaybackSyncSnapshot.self).validated()
            } ?? PlaybackSyncSnapshot()
            selected.settingsRevision = profileDocument?.revision
            selected.progressRevision = progressDocument?.revision
            selected.requiresRefresh = false
            choice = selected
            status = "Choose the initial setup"
        } catch { if generation == id { fail(error) } }
    }

    public func makeDeviceCode(deviceName: String = "Another device") async throws -> String {
        guard let connection, !isSyncing, !needsChoice else { throw SyncError.notReady }
        let id = generation
        let invitation = try await client(connection).invite(kind: "device")
        guard generation == id else { throw CancellationError() }
        return try encodeCode(Code(kind: "device", endpoint: connection.endpoint, code: invitation.code,
                                   key: connection.key, groups: connection.groups))
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
        let invitation = try await client.invite(kind: "share", categories: categories, groupID: existing?.id)
        guard let groupID = invitation.groupID else { throw ConfigurationSyncError.invalidResponse }
        guard generation == id else {
            if existing == nil { try await client.leaveGroup(groupID) }
            throw CancellationError()
        }
        var grant = existing ?? Grant(id: groupID, name: "Shared setup", categories: categories,
                                      key: ConfigurationCipher.generateKey(), initializing: true)
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
            let shared = settingsSnapshot().only(categories)
            let cipher = try AccountSyncCipher(key: grant.key, resource: "group.\(grant.id)")
            let resource = try client.groupResource(grant.id)
            let existingDocument = try await client.fetch(resource)
            if let existingDocument { _ = try cipher.open(existingDocument, as: SyncedConfiguration.self).validated() }
            else { _ = try await client.put(cipher.seal(shared), resource: resource, revision: nil) }
            guard generation == id else { throw CancellationError() }
            grant.initializing = nil
            connection.groups = connection.groups.map { $0.id == grant.id ? grant : $0 }
            self.connection = connection
            sharedGroups = connection.groups.map(\.metadata)
            baselines.groups[grant.id] = try existingDocument.map { try cipher.open($0, as: SyncedConfiguration.self).validated().only(categories) } ?? shared
            try persistConnection()
            try saveBaselines()
            // Profile transport distributes group keys only to this person's own devices.
            try await syncProfile(client: client, memberships: try await client.me().groups, id: id)
        }
        return try encodeCode(Code(kind: "share", endpoint: connection.endpoint, code: invitation.code,
                                   key: grant.key, groupID: grant.id, categories: categories))
    }

    public func joinShare(code string: String) async {
        guard var connection, !isSyncing, !needsChoice else { return }
        let id = generation
        isSyncing = true
        errorMessage = nil
        defer { if generation == id { finish() } }
        do {
            let code = try decodeCode(string)
            guard code.kind == "share", code.endpoint == connection.endpoint,
                  let key = code.key, let groupID = code.groupID, let categories = code.categories, !categories.isEmpty
            else { throw SyncError.wrongCode }
            _ = try AccountSyncCipher(key: key, resource: "group.\(groupID)")
            guard connection.groups.allSatisfy({ $0.categories.isDisjoint(with: categories) }) else { throw SyncError.overlappingGroup }
            let client = try client(connection)
            let group = try await client.join(code: code.code)
            let incoming: SyncedConfiguration
            do {
                guard generation == id else { throw CancellationError() }
                guard group.id == groupID, group.categories == categories else { throw ConfigurationSyncError.invalidResponse }
                let resource = try client.groupResource(group.id)
                guard let document = try await client.fetch(resource) else { throw ConfigurationSyncError.invalidResponse }
                incoming = try AccountSyncCipher(key: key, resource: "group.\(group.id)").open(document, as: SyncedConfiguration.self).validated()
                guard generation == id else { throw CancellationError() }
                connection.groups.append(Grant(id: group.id, name: group.name, categories: categories, key: key))
                try storage.save(JSONEncoder().encode(connection))
            } catch {
                try await client.leaveGroup(group.id)
                throw error
            }
            self.connection = connection
            sharedGroups = connection.groups.map(\.metadata)
            baselines.groups[group.id] = incoming.only(categories)
            try applySettings(incoming, only: categories)
            try saveBaselines()
            try await syncProfile(client: client, memberships: try await client.me().groups, id: id)
            status = "Shared setup connected"
        } catch {
            guard generation == id else { return }
            fail(error)
        }
    }

    public func leaveGroup(id groupID: String) async {
        guard var connection, !isSyncing else { return }
        let id = generation
        isSyncing = true
        defer { if generation == id { finish() } }
        do {
            let client = try client(connection)
            try await client.leaveGroup(groupID)
            guard generation == id else { return }
            connection.groups.removeAll { $0.id == groupID }
            self.connection = connection
            sharedGroups = connection.groups.map(\.metadata)
            baselines.groups[groupID] = nil
            try persistConnection()
            try saveBaselines()
            status = "Shared setup disconnected"
        } catch { if generation == id { fail(error) } }
    }

    public func refreshDevices() async {
        guard let connection else { return }
        let id = generation
        do {
            let devices = try await client(connection).devices()
            guard generation == id else { return }
            self.devices = devices
        } catch { if generation == id { fail(error) } }
    }
    public func revokeDevice(id deviceID: String) async {
        guard let connection else { return }
        let id = generation
        do {
            try await client(connection).revokeDevice(deviceID)
            guard generation == id else { return }
            if deviceID == connection.deviceID { try disconnect() }
            else { devices.removeAll { $0.id == deviceID } }
        } catch { if generation == id { fail(error) } }
    }

    private func syncGroups(client: AccountSyncClient, id: UUID) async throws {
        guard let connection else { return }
        for grant in connection.groups {
            if groupChoice?.grant.id == grant.id { continue }
            let cipher = try AccountSyncCipher(key: grant.key, resource: "group.\(grant.id)")
            let resource = try client.groupResource(grant.id)
            for attempt in 0..<3 {
                guard let document = try await client.fetch(resource) else { throw ConfigurationSyncError.invalidResponse }
                guard generation == id else { return }
                let remote = try cipher.open(document, as: SyncedConfiguration.self).validated().only(grant.categories)
                let local = settingsSnapshot().only(grant.categories)
                guard let baseline = baselines.groups[grant.id] else {
                    try applySettings(remote, only: grant.categories)
                    baselines.groups[grant.id] = remote
                    try saveBaselines()
                    break
                }
                let merged = SyncedConfiguration.merged(base: baseline, local: local, remote: remote)
                guard merged.conflicts.isEmpty else {
                    guard groupChoice == nil else { return }
                    guard let revision = document.revision else { throw ConfigurationSyncError.invalidResponse }
                    groupChoice = GroupChoice(grant: grant, local: local, remote: remote, merge: merged, revision: revision)
                    needsChoice = true
                    status = "Choose shared settings"
                    return
                }
                if merged.configuration != remote {
                    do { _ = try await client.put(cipher.seal(merged.configuration), resource: resource, revision: document.revision) }
                    catch ConfigurationSyncError.conflict where attempt < 2 { continue }
                    guard generation == id else { return }
                }
                let current = settingsSnapshot().only(grant.categories)
                let rebased = SyncedConfiguration.merged(base: local, local: current, remote: merged.configuration)
                guard rebased.conflicts.isEmpty else {
                    guard groupChoice == nil else { return }
                    guard let latest = try await client.fetch(resource), let revision = latest.revision else { throw ConfigurationSyncError.invalidResponse }
                    guard generation == id else { return }
                    groupChoice = GroupChoice(grant: grant, local: current, remote: merged.configuration, merge: rebased, revision: revision)
                    needsChoice = true
                    status = "Choose shared settings"
                    return
                }
                try applySettings(rebased.configuration, only: grant.categories)
                baselines.groups[grant.id] = merged.configuration
                try saveBaselines()
                break
            }
        }
    }


    private func resolveShared(useLocal: Bool) async {
        guard let connection, let selected = groupChoice, !isSyncing else { return }
        let id = generation
        isSyncing = true
        errorMessage = nil
        defer { if generation == id { finish() } }
        do {
            let client = try client(connection)
            let resource = try client.groupResource(selected.grant.id)
            let resolved = selected.merge.configuration.replacing(selected.merge.conflicts, from: useLocal ? selected.local : selected.remote)
            let cipher = try AccountSyncCipher(key: selected.grant.key, resource: "group.\(selected.grant.id)")
            let revision = try await client.put(cipher.seal(resolved), resource: resource, revision: selected.revision)
            guard generation == id else { return }
            let current = settingsSnapshot().only(selected.grant.categories)
            let rebased = SyncedConfiguration.merged(base: selected.local, local: current, remote: resolved)
            baselines.groups[selected.grant.id] = resolved
            if rebased.conflicts.isEmpty {
                try applySettings(rebased.configuration, only: selected.grant.categories)
                groupChoice = nil
                needsChoice = choice != nil
                status = needsChoice ? "Choose remaining changes" : "Up to date"
            } else {
                groupChoice = GroupChoice(grant: selected.grant, local: current, remote: resolved, merge: rebased, revision: revision)
            }
            try saveBaselines()
            if groupChoice == nil { try await syncGroups(client: client, id: id) }
        } catch ConfigurationSyncError.conflict {
            guard generation == id else { return }
            groupChoice = nil
            needsChoice = choice != nil
            errorMessage = ConfigurationSyncError.conflict.localizedDescription
            status = "Shared setup changed. Sync again."
        } catch { if generation == id { fail(error) } }
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
        status = "Off"
        beforeProfileChange?()
        try activateSettingsProfile(nil)
        library.activateProfile(id: nil)
        if let localSettings { try applySettings(localSettings) }
        defaults.removeObject(forKey: "accountSyncLocalSetup")
        rememberObserved()
    }

    private func settingsSnapshot() -> SyncedConfiguration {
        SyncedConfiguration(addonURLs: addons.addons.map(\.manifestURL), audioLanguage: defaults.string(forKey: "audioLanguage") ?? "en",
                            subtitleLanguage: defaults.string(forKey: "subtitleLanguage") ?? "",
                            subtitleScale: defaults.object(forKey: "subtitleScale") as? Double ?? 1,
                            maximumSourceGigabytes: defaults.object(forKey: "maximumAutomaticSourceGigabytes") as? Int ?? 50,
                            accent: defaults.string(forKey: "accentColor") ?? "white")
    }
    private func activateSettingsProfile(_ connection: Connection?) throws {
        // AddonStore already persists the local setup in UserDefaults. Keep the
        // same local data model, but never leave one person's setup active for another.
        let activeKey = "accountSyncSettingsProfile"
        let previous = defaults.string(forKey: activeKey)
        if let previous {
            defaults.set(try JSONEncoder().encode(settingsSnapshot()), forKey: "accountSyncSettings.\(previous)")
        }
        if let connection {
            if previous != connection.profileID {
                let saved = defaults.data(forKey: "accountSyncSettings.\(connection.profileID)")
                let setup = try saved.map { try JSONDecoder().decode(SyncedConfiguration.self, from: $0).validated() }
                    ?? SyncedConfiguration()
                try applySettings(setup)
            }
            defaults.set(connection.profileID, forKey: activeKey)
        } else {
            if let saved = defaults.data(forKey: "accountSyncLocalSetup") {
                do { try applySettings(JSONDecoder().decode(SyncedConfiguration.self, from: saved)) }
                catch {
                    try applySettings(SyncedConfiguration())
                    defaults.removeObject(forKey: activeKey)
                    throw ConfigurationSyncError.invalidConfiguration
                }
            } else if previous != nil {
                try applySettings(SyncedConfiguration())
            }
            defaults.removeObject(forKey: activeKey)
        }
    }
    private func applySettings(_ settings: SyncedConfiguration, excluding scopes: Set<SyncCategory> = [], only: Set<SyncCategory>? = nil) throws {
        let settings = try settings.validated()
        let categories = only ?? Set(SyncCategory.allCases).subtracting(scopes)
        if categories.contains(.addons), addons.addons.map(\.manifestURL) != settings.addonURLs {
            try addons.replaceManifestURLs(settings.addonURLs)
            Task { await addons.refreshManifests() }
        }
        if categories.contains(.playback) {
            defaults.set(settings.audioLanguage, forKey: "audioLanguage")
            defaults.set(settings.subtitleLanguage, forKey: "subtitleLanguage")
            defaults.set(settings.subtitleScale, forKey: "subtitleScale")
            defaults.set(settings.maximumSourceGigabytes, forKey: "maximumAutomaticSourceGigabytes")
        }
        if categories.contains(.appearance) { defaults.set(settings.accent, forKey: "accentColor") }
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
        let cipher = try AccountSyncCipher(key: connection.key, resource: "baseline")
        let document = try cipher.seal(value)
        defaults.set(try JSONEncoder().encode(document), forKey: "accountSyncBaseline.\(connection.profileID)")
    }
    private func restoreBaselines(_ connection: Connection) throws {
        if let data = defaults.data(forKey: "accountSyncBaseline.\(connection.profileID)") {
            let document = try JSONDecoder().decode(AccountSyncDocument.self, from: data)
            baselines = try AccountSyncCipher(key: connection.key, resource: "baseline").open(document)
            lastSync = baselines.lastSync
        }
    }
    private func validatedGrants(_ grants: [Grant], memberships: [SyncGroup]) throws -> [Grant] {
        var scopes = Set<SyncCategory>()
        var seen = Set<String>()
        return try grants.filter { grant in memberships.contains { $0.id == grant.id } }.map { grant in
            guard seen.insert(grant.id).inserted, !grant.categories.isEmpty,
                  memberships.contains(where: { $0.id == grant.id && $0.categories == grant.categories }),
                  scopes.isDisjoint(with: grant.categories) else { throw SyncError.overlappingGroup }
            _ = try AccountSyncCipher(key: grant.key, resource: "group.\(grant.id)")
            scopes.formUnion(grant.categories)
            return grant
        }
    }
    private func rememberObserved() {
        lastObservedSettings = settingsSnapshot()
        lastObservedProgress = library.playbackSyncSnapshot
    }
    private func localChanged() {
        let settings = settingsSnapshot()
        let progress = library.playbackSyncSnapshot
        guard settings != lastObservedSettings || progress != lastObservedProgress else { return }
        let settingsChanged = settings != lastObservedSettings
        rememberObserved()
        guard isConnected, choice?.initial != true else { return }
        if !isSyncing { status = "Changes waiting to sync" }
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
    private func finish() {
        isSyncing = false
        rememberObserved()
        if isConnected, !needsChoice, errorMessage == nil,
           (settingsSnapshot().excluding(Set(connection?.groups.flatMap(\.categories) ?? [])) != baselines.profile?.settings
            || library.playbackSyncSnapshot != baselines.progress) { schedule(after: 1) }
    }
    private func decodeCode(_ string: String) throws -> Code {
        guard string.utf8.count <= 32_768,
              let data = Data(base64Encoded: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let code = try? JSONDecoder().decode(Code.self, from: data), code.version == 2,
              !code.code.isEmpty, code.code.utf8.count <= 512 else { throw SyncError.wrongCode }
        _ = try AccountSyncClient(endpoint: code.endpoint, session: session)
        return code
    }
    private func encodeCode(_ code: Code) throws -> String { try JSONEncoder().encode(code).base64EncodedString() }
    private func fail(_ error: Error) {
        status = "Couldn't sync"
        errorMessage = (error as? ConfigurationSyncError)?.localizedDescription
            ?? (error as? AccountSyncClientError)?.localizedDescription
            ?? (error as? SyncError)?.localizedDescription ?? "Couldn't save sync setup. Try again."
    }
    private enum SyncError: Error, LocalizedError {
        case wrongCode, notReady, overlappingGroup, sharedConflict, recoveryRequired, keychain(Int32)
        var errorDescription: String? {
            switch self {
            case .recoveryRequired: "This account already has encrypted data. Enter its recovery key or use Add my device on a connected device."
            case .wrongCode: "Paste the complete account, device or sharing code for this server."
            case .notReady: "Finish connecting and resolve pending changes first."
            case .overlappingGroup: "A category can belong to one shared setup. Leave its current shared setup first."
            case .sharedConflict: "Both people changed the shared setup. Retry after reviewing the shared settings."
            case .keychain(let code): "Couldn't access account credentials in Keychain (\(code)). Try again."
            }
        }
    }
    private static var keychainStorage: Storage {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "li.tjh.MediaApp.account-sync", kSecAttrAccount as String: "connection"]
        return Storage(load: {
            var request = query
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var value: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &value)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = value as? Data else { throw SyncError.keychain(status) }
            return data
        }, save: { data in
            let values: [String: Any] = [kSecValueData as String: data,
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
            if status == errSecItemNotFound {
                let added = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
                guard added == errSecSuccess else { throw SyncError.keychain(added) }
            } else if status != errSecSuccess { throw SyncError.keychain(status) }
        }, remove: {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SyncError.keychain(status) }
        })
    }
}

private extension SyncedConfiguration {
    func only(_ categories: Set<SyncCategory>) -> Self {
        var result = Self()
        if categories.contains(.addons) { result.addonURLs = addonURLs }
        if categories.contains(.playback) {
            result.audioLanguage = audioLanguage; result.subtitleLanguage = subtitleLanguage
            result.subtitleScale = subtitleScale; result.maximumSourceGigabytes = maximumSourceGigabytes
        }
        if categories.contains(.appearance) { result.accent = accent }
        return result
    }
    func excluding(_ categories: Set<SyncCategory>) -> Self { only(Set(SyncCategory.allCases).subtracting(categories)) }
    func replacing(_ fields: Set<ConfigurationField>, from source: Self) -> Self {
        var result = self
        for field in fields {
            switch field {
            case .addonURLs: result.addonURLs = source.addonURLs
            case .audioLanguage: result.audioLanguage = source.audioLanguage
            case .subtitleLanguage: result.subtitleLanguage = source.subtitleLanguage
            case .subtitleScale: result.subtitleScale = source.subtitleScale
            case .maximumSourceGigabytes: result.maximumSourceGigabytes = source.maximumSourceGigabytes
            case .accent: result.accent = source.accent
            }
        }
        return result
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
        token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in changed() }
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}
