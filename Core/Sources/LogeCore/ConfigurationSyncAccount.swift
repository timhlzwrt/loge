import Foundation
import Observation
import Security

/// Optional configuration sync. Watch history continues to belong to Trakt.
@MainActor @Observable
public final class ConfigurationSyncAccount {
    public private(set) var isConnected = false
    public private(set) var isSyncing = false
    public private(set) var status = "Off"
    public private(set) var errorMessage: String?
    public private(set) var needsChoice = false
    public private(set) var lastSync: Date?
    public var choiceLocal: SyncedConfiguration? { choice?.local }
    public var choiceRemote: SyncedConfiguration? { choice?.remote }
    public var conflictingFields: [ConfigurationField] { ConfigurationField.allCases.filter { choice?.conflicts.contains($0) == true } }
    public var endpoint: String? { connection?.endpoint }
    public var username: String? { connection?.username }
    public var recoveryKey: String? { connection?.key }
    public var setupCode: String? {
        connection.flatMap { try? JSONEncoder().encode($0).base64EncodedString() }
    }

    struct Connection: Codable, Sendable {
        let endpoint: String
        let username: String
        let password: String
        let key: String
    }

    struct ConnectionStorage {
        var load: () throws -> Data?
        var save: (Data) throws -> Void
        var remove: () throws -> Void
    }

    private struct Choice {
        let local: SyncedConfiguration
        let remote: SyncedConfiguration
        let revision: String
        let merged: SyncedConfiguration
        let conflicts: Set<ConfigurationField>
    }

    @ObservationIgnored private let addons: AddonStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storage: ConnectionStorage
    @ObservationIgnored private let clientFactory: (Connection) throws -> ConfigurationSyncClient
    @ObservationIgnored private var connection: Connection?
    @ObservationIgnored private var baseline: SyncedConfiguration?
    @ObservationIgnored private var choice: Choice?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var observer: DefaultsObserver?
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var lastObserved: SyncedConfiguration?
    private static let baselineKey = "configurationSyncBaseline"
    private static let dateKey = "configurationSyncDate"

    public convenience init(addons: AddonStore, defaults: UserDefaults = .standard) {
        self.init(addons: addons, defaults: defaults, storage: Self.keychainStorage,
                  clientFactory: { try ConfigurationSyncClient(endpoint: $0.endpoint, username: $0.username, password: $0.password) })
    }

    init(addons: AddonStore, defaults: UserDefaults, storage: ConnectionStorage,
         clientFactory: @escaping (Connection) throws -> ConfigurationSyncClient) {
        self.addons = addons
        self.defaults = defaults
        self.storage = storage
        self.clientFactory = clientFactory
        do {
            if let data = try storage.load() {
                let saved = try JSONDecoder().decode(Connection.self, from: data)
                _ = try clientFactory(saved)
                let cipher = try ConfigurationCipher(key: saved.key)
                connection = saved
                isConnected = true
                status = "Ready to sync"
                if let data = defaults.data(forKey: Self.baselineKey) {
                    baseline = try cipher.open(JSONDecoder().decode(EncryptedConfiguration.self, from: data))
                }
                lastSync = defaults.object(forKey: Self.dateKey) as? Date
            }
        } catch {
            errorMessage = "Couldn't restore sync setup. Reconnect to continue."
            status = "Setup needs attention"
        }
        lastObserved = snapshot()
        observer = DefaultsObserver { [weak self] in
            Task { @MainActor [weak self] in self?.settingsChanged() }
        }
    }

    public func connect(endpoint: String, username: String, password: String, key: String) async {
        guard !isSyncing else { return }
        let proposed = Connection(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                                  username: username, password: password,
                                  key: key.trimmingCharacters(in: .whitespacesAndNewlines))
        let id = generation
        isSyncing = true
        errorMessage = nil
        defer { if generation == id { finishSync() } }
        do {
            let client = try clientFactory(proposed)
            let cipher = try ConfigurationCipher(key: proposed.key)
            let remote = try await client.fetch()
            guard generation == id else { return }
            let decoded = try remote.map { try cipher.open($0.envelope) }
            try storage.save(JSONEncoder().encode(proposed))
            connection = proposed
            isConnected = true
            baseline = nil
            lastSync = nil
            defaults.removeObject(forKey: Self.baselineKey)
            defaults.removeObject(forKey: Self.dateKey)
            choice = nil
            needsChoice = false
            if let remote, let decoded {
                setChoice(local: snapshot(), remote: decoded, revision: remote.revision)
            } else {
                let local = try snapshot().validated()
                _ = try await client.put(cipher.seal(local), revision: nil)
                guard generation == id else { return }
                try record(local, cipher: cipher)
            }
        } catch {
            guard generation == id else { return }
            fail(error)
        }
    }

    public func sync() async {
        guard let connection, !isSyncing, !needsChoice else { return }
        let id = generation
        isSyncing = true
        errorMessage = nil
        status = "Syncing…"
        defer {
            if generation == id {
                finishSync()
            }
        }
        do {
            let client = try clientFactory(connection)
            let cipher = try ConfigurationCipher(key: connection.key)
            // A concurrent remote writer may win once; refetch and merge instead of forcing a write.
            for attempt in 0..<3 {
                let remote = try await client.fetch()
                guard generation == id else { return }
                let local = try snapshot().validated()
                guard let remote else {
                    guard baseline == nil else {
                        throw AccountError.remoteRemoved
                    }
                    do {
                        _ = try await client.put(cipher.seal(local), revision: nil)
                        guard generation == id else { return }
                        try record(local, cipher: cipher)
                        return
                    } catch ConfigurationSyncError.conflict where attempt < 2 { continue }
                }
                let incoming = try cipher.open(remote.envelope)
                guard let baseline else {
                    setChoice(local: local, remote: incoming, revision: remote.revision)
                    return
                }
                let merged = SyncedConfiguration.merged(base: baseline, local: local, remote: incoming)
                guard merged.conflicts.isEmpty else {
                    setChoice(local: local, remote: incoming, revision: remote.revision)
                    return
                }
                var committedRevision = remote.revision
                if merged.configuration != incoming {
                    do {
                        committedRevision = try await client.put(cipher.seal(merged.configuration), revision: remote.revision)
                    } catch ConfigurationSyncError.conflict where attempt < 2 { continue }
                    guard generation == id else { return }
                }
                let current = snapshot()
                let rebased = SyncedConfiguration.merged(base: local, local: current, remote: merged.configuration)
                if rebased.conflicts.isEmpty {
                    try apply(rebased.configuration)
                    try record(merged.configuration, cipher: cipher)
                } else {
                    try record(merged.configuration, cipher: cipher)
                    setChoice(local: current, remote: merged.configuration, revision: committedRevision, merge: rebased)
                }
                return
            }
        } catch {
            guard generation == id else { return }
            fail(error)
        }
    }

    public func resolve(useLocal: Bool) async {
        guard let connection, let choice, !isSyncing else { return }
        guard snapshot() == choice.local else {
            setChoice(local: snapshot(), remote: choice.remote, revision: choice.revision)
            status = "Settings changed. Choose which setup to keep again."
            return
        }
        let id = generation
        isSyncing = true
        errorMessage = nil
        defer { if generation == id { finishSync() } }
        do {
            let cipher = try ConfigurationCipher(key: connection.key)
            var selected = choice.merged
            let source = useLocal ? choice.local : choice.remote
            for field in choice.conflicts {
                switch field {
                case .addonURLs: selected.addonURLs = source.addonURLs
                case .audioLanguage: selected.audioLanguage = source.audioLanguage
                case .subtitleLanguage: selected.subtitleLanguage = source.subtitleLanguage
                case .subtitleScale: selected.subtitleScale = source.subtitleScale
                case .maximumSourceGigabytes: selected.maximumSourceGigabytes = source.maximumSourceGigabytes
                case .accent: selected.accent = source.accent
                }
            }
            var committedRevision = choice.revision
            if selected != choice.remote {
                let client = try clientFactory(connection)
                committedRevision = try await client.put(cipher.seal(selected), revision: choice.revision)
                guard generation == id else { return }
            }
            let current = snapshot()
            let rebased = SyncedConfiguration.merged(base: choice.local, local: current, remote: selected)
            if rebased.conflicts.isEmpty {
                try apply(rebased.configuration)
                try record(selected, cipher: cipher)
                self.choice = nil
                needsChoice = false
            } else {
                try record(selected, cipher: cipher)
                setChoice(local: current, remote: selected, revision: committedRevision, merge: rebased)
            }
        } catch ConfigurationSyncError.conflict {
            guard generation == id else { return }
            self.choice = nil
            needsChoice = false
            status = "Server setup changed. Sync again to review it."
        } catch {
            guard generation == id else { return }
            fail(error)
        }
    }

    public func disconnect() throws {
        try storage.remove()
        generation = UUID()
        pendingSync?.cancel()
        pendingSync = nil
        connection = nil
        baseline = nil
        choice = nil
        needsChoice = false
        isConnected = false
        isSyncing = false
        lastSync = nil
        errorMessage = nil
        status = "Off"
        defaults.removeObject(forKey: Self.baselineKey)
        defaults.removeObject(forKey: Self.dateKey)
    }

    private func finishSync() {
        isSyncing = false
        if errorMessage == nil, isConnected, !needsChoice, snapshot() != baseline {
            scheduleSync()
        }
    }

    private func scheduleSync() {
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self else { return }
            self.pendingSync = nil
            await self.sync()
        }
    }

    private func settingsChanged() {
        let current = snapshot()
        guard current != lastObserved else { return }
        lastObserved = current
        guard isConnected, !needsChoice, current != baseline else { return }
        scheduleSync()
        if !isSyncing { status = "Changes waiting to sync" }
    }

    private func snapshot() -> SyncedConfiguration {
        SyncedConfiguration(addonURLs: addons.addons.map(\.manifestURL),
                            audioLanguage: defaults.string(forKey: "audioLanguage") ?? "en",
                            subtitleLanguage: defaults.string(forKey: "subtitleLanguage") ?? "",
                            subtitleScale: (defaults.object(forKey: "subtitleScale") as? Double) ?? 1,
                            maximumSourceGigabytes: (defaults.object(forKey: "maximumAutomaticSourceGigabytes") as? Int) ?? 50,
                            accent: defaults.string(forKey: "accentColor") ?? "white")
    }

    private func apply(_ configuration: SyncedConfiguration) throws {
        let configuration = try configuration.validated()
        let addonsChanged = addons.addons.map(\.manifestURL) != configuration.addonURLs
        if addonsChanged { try addons.replaceManifestURLs(configuration.addonURLs) }
        defaults.set(configuration.audioLanguage, forKey: "audioLanguage")
        defaults.set(configuration.subtitleLanguage, forKey: "subtitleLanguage")
        defaults.set(configuration.subtitleScale, forKey: "subtitleScale")
        defaults.set(configuration.maximumSourceGigabytes, forKey: "maximumAutomaticSourceGigabytes")
        defaults.set(configuration.accent, forKey: "accentColor")
        if addonsChanged { Task { await addons.refreshManifests() } }
    }

    private func record(_ configuration: SyncedConfiguration, cipher: ConfigurationCipher) throws {
        defaults.set(try JSONEncoder().encode(cipher.seal(configuration)), forKey: Self.baselineKey)
        baseline = configuration
        lastSync = Date()
        defaults.set(lastSync, forKey: Self.dateKey)
        status = snapshot() == configuration ? "Up to date" : "Changes waiting to sync"
    }

    private func setChoice(local: SyncedConfiguration, remote: SyncedConfiguration, revision: String,
                           merge: ConfigurationMerge? = nil) {
        let merged = merge ?? baseline.map { SyncedConfiguration.merged(base: $0, local: local, remote: remote) }
        choice = Choice(local: local, remote: remote, revision: revision,
                        merged: merged?.configuration ?? local,
                        conflicts: merged?.conflicts ?? Set(ConfigurationField.allCases))
        needsChoice = true
        status = baseline == nil ? "Choose the initial setup" : "Both devices changed the same setup. Choose which to keep."
    }

    private func fail(_ error: Error) {
        status = "Couldn't sync"
        // URLSession errors can include endpoint URLs. Only show errors with controlled copy.
        errorMessage = (error as? ConfigurationSyncError)?.localizedDescription
            ?? (error as? AccountError)?.localizedDescription
            ?? "Couldn't save or load sync setup. Check the connection and try again."
    }

    private enum AccountError: Error, LocalizedError {
        case remoteRemoved
        case keychain(Int32)
        var errorDescription: String? {
            switch self {
            case .remoteRemoved: "The server configuration was removed. Reconnect to choose an initial setup."
            case .keychain(let code): "Couldn't access sync credentials in Keychain (\(code)). Try again."
            }
        }
    }

    private static var keychainStorage: ConnectionStorage {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "li.tjh.MediaApp.configuration-sync",
                                    kSecAttrAccount as String: "connection"]
        return ConnectionStorage(load: {
            var query = query
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data else { throw AccountError.keychain(status) }
            return data
        }, save: { data in
            let values: [String: Any] = [kSecValueData as String: data,
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
            if status == errSecItemNotFound {
                let added = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
                guard added == errSecSuccess else { throw AccountError.keychain(added) }
            } else if status != errSecSuccess { throw AccountError.keychain(status) }
        }, remove: {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.keychain(status) }
        })
    }
}

private final class DefaultsObserver {
    private let token: NSObjectProtocol
    init(changed: @escaping @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                       object: nil, queue: nil) { _ in changed() }
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}
