import Foundation
import Synchronization
import Testing
@testable import LogeCore

@MainActor @Suite(.serialized)
struct ConfigurationSyncAccountTests {
    private func fixture(defaults providedDefaults: UserDefaults? = nil,
                         storage providedStorage: SyncConnectionStorage? = nil,
                         addons providedAddons: AddonStore? = nil,
                         reset: Bool = true) -> (ConfigurationSyncAccount, UserDefaults, SyncConnectionStorage) {
        if reset { SyncAccountProtocol.state.withLock { $0 = .init() } }
        let defaults = providedDefaults ?? UserDefaults(suiteName: "sync-account-\(UUID())")!
        let store = providedAddons ?? AddonStore(defaults: defaults)
        let storage = providedStorage ?? SyncConnectionStorage()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [SyncAccountProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let account = ConfigurationSyncAccount(addons: store, defaults: defaults, storage: storage.storage,
            clientFactory: { try ConfigurationSyncClient(endpoint: $0.endpoint, username: $0.username, password: $0.password, session: session) })
        return (account, defaults, storage)
    }

    @Test func staysOffUntilConfiguredAndPersistsOnlyEncryptedBaseline() async throws {
        let (account, defaults, storage) = fixture()
        await account.sync()
        #expect(!account.isConnected)
        #expect(SyncAccountProtocol.state.withLock { $0.requests } == 0)
        await account.connect(endpoint: "https://sync.example/configuration", username: "test", password: "password", key: ConfigurationCipher.generateKey())
        #expect(account.isConnected)
        #expect(account.errorMessage == nil)
        #expect(account.lastSync != nil)
        #expect(storage.data != nil)
        let baseline = try #require(defaults.data(forKey: "configurationSyncBaseline"))
        #expect(!String(decoding: baseline, as: UTF8.self).contains("audioLanguage"))
        try account.disconnect()
        #expect(storage.data == nil)
        #expect(defaults.data(forKey: "configurationSyncBaseline") == nil)
    }

    @Test func firstConnectionNeedsChoiceAndWrongKeyDoesNotChangeLocalSettings() async throws {
        let (account, defaults, _) = fixture()
        let key = ConfigurationCipher.generateKey()
        let cipher = try ConfigurationCipher(key: key)
        try SyncAccountProtocol.setRemote(cipher.seal(SyncedConfiguration(accent: "coral")))
        await account.connect(endpoint: "https://sync.example/configuration", username: "test", password: "password", key: ConfigurationCipher.generateKey())
        #expect(!account.isConnected)
        #expect(defaults.string(forKey: "accentColor") == nil)
        await account.connect(endpoint: "https://sync.example/configuration", username: "test", password: "password", key: key)
        #expect(account.needsChoice)
        #expect(defaults.string(forKey: "accentColor") == nil)
        await account.resolve(useLocal: false)
        #expect(!account.needsChoice)
        #expect(defaults.string(forKey: "accentColor") == "coral")
        try account.disconnect()
    }

    @Test func mergesIndependentOfflineEditsAndKeepsThemWhenResolvingConflict() async throws {
        let (account, defaults, _) = fixture()
        let key = ConfigurationCipher.generateKey()
        let cipher = try ConfigurationCipher(key: key)
        await account.connect(endpoint: "https://sync.example/configuration", username: "test", password: "password", key: key)
        defaults.set("de", forKey: "audioLanguage")
        try SyncAccountProtocol.setRemote(cipher.seal(SyncedConfiguration(accent: "mint")))
        await account.sync()
        #expect(!account.needsChoice)
        #expect(defaults.string(forKey: "audioLanguage") == "de")
        #expect(defaults.string(forKey: "accentColor") == "mint")

        defaults.set("fr", forKey: "audioLanguage")
        defaults.set(1.25, forKey: "subtitleScale")
        try SyncAccountProtocol.setRemote(cipher.seal(SyncedConfiguration(audioLanguage: "es", subtitleLanguage: "en", accent: "mint")))
        await account.sync()
        #expect(account.needsChoice)
        #expect(account.conflictingFields == [.audioLanguage])
        await account.resolve(useLocal: false)
        #expect(!account.needsChoice)
        #expect(defaults.string(forKey: "audioLanguage") == "es")
        #expect(defaults.string(forKey: "subtitleLanguage") == "en")
        #expect(defaults.double(forKey: "subtitleScale") == 1.25)
        let remote = try #require(try SyncAccountProtocol.envelope())
        let saved = try cipher.open(remote)
        #expect(saved.subtitleScale == 1.25)
        #expect(saved.subtitleLanguage == "en")
        try account.disconnect()
    }

    @Test func editsDuringUploadsPreserveIncomingChangesAndConflictChoice() async throws {
        let (account, defaults, _) = fixture()
        let key = ConfigurationCipher.generateKey()
        let cipher = try ConfigurationCipher(key: key)
        await account.connect(endpoint: "https://sync.example/configuration", username: "test", password: "password", key: key)
        defaults.set("de", forKey: "audioLanguage")
        try SyncAccountProtocol.setRemote(cipher.seal(SyncedConfiguration(accent: "mint")))
        SyncAccountProtocol.state.withLock { state in
            state.afterPut = { defaults.set("de", forKey: "subtitleLanguage") }
        }
        await account.sync()
        #expect(defaults.string(forKey: "accentColor") == "mint")
        #expect(defaults.string(forKey: "subtitleLanguage") == "de")
        #expect(defaults.string(forKey: "audioLanguage") == "de")
        await account.sync()

        defaults.set("fr", forKey: "audioLanguage")
        defaults.set(1.25, forKey: "subtitleScale")
        try SyncAccountProtocol.setRemote(cipher.seal(SyncedConfiguration(audioLanguage: "es", subtitleLanguage: "de", accent: "mint")))
        await account.sync()
        #expect(account.needsChoice)
        SyncAccountProtocol.state.withLock { state in
            state.afterPut = { defaults.set("coral", forKey: "accentColor") }
        }
        await account.resolve(useLocal: false)
        #expect(!account.needsChoice)
        #expect(defaults.string(forKey: "audioLanguage") == "es")
        #expect(defaults.string(forKey: "accentColor") == "coral")
        #expect(defaults.double(forKey: "subtitleScale") == 1.25)
        await account.sync()
        let saved = try cipher.open(#require(try SyncAccountProtocol.envelope()))
        #expect(saved.accent == "coral")
        #expect(saved.audioLanguage == "es")
        try account.disconnect()
    }

    @Test func failedUploadSurvivesRelaunchAndMergesAgainstEncryptedBaseline() async throws {
        let (account, defaults, storage) = fixture()
        let key = ConfigurationCipher.generateKey()
        let cipher = try ConfigurationCipher(key: key)
        await account.connect(endpoint: "https://sync.example/configuration", username: "test", password: "password", key: key)
        let baseline = defaults.data(forKey: "configurationSyncBaseline")
        defaults.set("de", forKey: "audioLanguage")
        SyncAccountProtocol.state.withLock { $0.failPut = true }
        await account.sync()
        #expect(account.errorMessage != nil)
        #expect(defaults.data(forKey: "configurationSyncBaseline") == baseline)
        SyncAccountProtocol.state.withLock { $0.failPut = false }
        try SyncAccountProtocol.setRemote(cipher.seal(SyncedConfiguration(accent: "mint")))
        let (restored, _, _) = fixture(defaults: defaults, storage: storage, reset: false)
        #expect(restored.isConnected)
        await restored.sync()
        #expect(!restored.needsChoice)
        #expect(restored.errorMessage == nil)
        #expect(defaults.string(forKey: "audioLanguage") == "de")
        #expect(defaults.string(forKey: "accentColor") == "mint")
        try restored.disconnect()
        try account.disconnect()
    }

    @Test func deliberatePreferenceEditAndAddonRemovalAutomaticallyPush() async throws {
        let defaults = UserDefaults(suiteName: "sync-auto-\(UUID())")!
        let store = AddonStore(defaults: defaults)
        try store.replaceManifestURLs(["https://fixture.example/manifest.json"])
        let (account, _, _) = fixture(defaults: defaults, addons: store)
        let key = ConfigurationCipher.generateKey()
        let cipher = try ConfigurationCipher(key: key)
        await account.connect(endpoint: "https://sync.example/configuration", username: "test", password: "password", key: key)
        defaults.set("de", forKey: "audioLanguage")
        store.remove("https://fixture.example/manifest.json")
        try await Task.sleep(for: .milliseconds(1_500))
        let saved = try cipher.open(#require(try SyncAccountProtocol.envelope()))
        #expect(saved.audioLanguage == "de")
        #expect(saved.addonURLs.isEmpty)
        #expect(account.errorMessage == nil)
        try account.disconnect()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LOGE_SYNC_TEST_CONNECTION_FILE"] != nil))
    func liveTwoIndependentAccountsCarryAddonOrderRemovalAndPreferencesBothWays() async throws {
        await ConfigurationSyncLiveTestLock.shared.acquire()
        defer { Task { await ConfigurationSyncLiveTestLock.shared.release() } }
        let path = try #require(ProcessInfo.processInfo.environment["LOGE_SYNC_TEST_CONNECTION_FILE"])
        struct LiveConnection: Decodable {
            let endpoint: String
            let username: String
            let password: String
            let recoveryKey: String?
            let key: String?
        }
        let connection = try JSONDecoder().decode(LiveConnection.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let key = try #require(connection.recoveryKey ?? connection.key)
        let cipher = try ConfigurationCipher(key: key)
        let client = try ConfigurationSyncClient(endpoint: connection.endpoint, username: connection.username, password: connection.password)
        let original = try await client.fetch()
        let defaultsA = UserDefaults(suiteName: "sync-live-a-\(UUID())")!
        let defaultsB = UserDefaults(suiteName: "sync-live-b-\(UUID())")!
        let addonsA = AddonStore(defaults: defaultsA)
        let addonsB = AddonStore(defaults: defaultsB)
        let first = "https://sync-fixture.invalid/a/manifest.json"
        let second = "https://sync-fixture.invalid/b/manifest.json"
        try addonsA.replaceManifestURLs([first, second])
        let storageA = SyncConnectionStorage()
        let storageB = SyncConnectionStorage()
        let accountA = ConfigurationSyncAccount(addons: addonsA, defaults: defaultsA, storage: storageA.storage,
            clientFactory: { try ConfigurationSyncClient(endpoint: $0.endpoint, username: $0.username, password: $0.password) })
        let accountB = ConfigurationSyncAccount(addons: addonsB, defaults: defaultsB, storage: storageB.storage,
            clientFactory: { try ConfigurationSyncClient(endpoint: $0.endpoint, username: $0.username, password: $0.password) })
        do {
            await accountA.connect(endpoint: connection.endpoint, username: connection.username, password: connection.password, key: key)
            if accountA.needsChoice { await accountA.resolve(useLocal: true) }
            #expect(accountA.errorMessage == nil)
            await accountB.connect(endpoint: connection.endpoint, username: connection.username, password: connection.password, key: key)
            if accountB.needsChoice { await accountB.resolve(useLocal: false) }
            #expect(accountB.errorMessage == nil)
            #expect(addonsB.addons.map(\.manifestURL) == [first, second])
            addonsA.move(fromOffsets: [1], toOffset: 0)
            await accountA.sync()
            await accountB.sync()
            #expect(addonsB.addons.map(\.manifestURL) == [second, first])
            addonsB.remove(first)
            defaultsB.set("de", forKey: "subtitleLanguage")
            await accountB.sync()
            await accountA.sync()
            #expect(addonsA.addons.map(\.manifestURL) == [second])
            #expect(defaultsA.string(forKey: "subtitleLanguage") == "de")
            defaultsA.set("fr", forKey: "audioLanguage")
            await accountA.sync()
            await accountB.sync()
            #expect(defaultsB.string(forKey: "audioLanguage") == "fr")
            #expect(accountA.errorMessage == nil)
            #expect(accountB.errorMessage == nil)
            let final = try #require(try await client.fetch())
            let configuration = try cipher.open(final.envelope)
            #expect(configuration.addonURLs == [second])
            #expect(configuration.audioLanguage == "fr")
            #expect(configuration.subtitleLanguage == "de")
        } catch {
            try accountA.disconnect()
            try accountB.disconnect()
            let latest = try await client.fetch()
            _ = try await client.put(original?.envelope ?? cipher.seal(SyncedConfiguration()), revision: latest?.revision)
            throw error
        }
        try accountA.disconnect()
        try accountB.disconnect()
        let latest = try await client.fetch()
        _ = try await client.put(original?.envelope ?? cipher.seal(SyncedConfiguration()), revision: latest?.revision)
    }

    @Test func disconnectWhileFetchingRejectsTheLateRemoteResult() async throws {
        let (account, defaults, _) = fixture()
        let key = ConfigurationCipher.generateKey()
        let cipher = try ConfigurationCipher(key: key)
        await account.connect(endpoint: "https://sync.example/configuration", username: "test", password: "password", key: key)
        try SyncAccountProtocol.setRemote(cipher.seal(SyncedConfiguration(accent: "mint")))
        SyncAccountProtocol.state.withLock { state in
            state.afterGet = {
                do { try account.disconnect() } catch { Issue.record(error) }
            }
        }
        await account.sync()
        #expect(!account.isConnected)
        #expect(!account.isSyncing)
        #expect(account.status == "Off")
        #expect(defaults.string(forKey: "accentColor") == nil)
        #expect(defaults.data(forKey: "configurationSyncBaseline") == nil)
    }

    @Test func failedCredentialSaveKeepsOldConnectionAndDisconnectFailureKeepsSetup() async throws {
        let (account, _, storage) = fixture()
        let key = ConfigurationCipher.generateKey()
        await account.connect(endpoint: "https://sync.example/configuration", username: "old", password: "password", key: key)
        storage.failSave = true
        await account.connect(endpoint: "https://new.example/configuration", username: "new", password: "password", key: key)
        #expect(account.username == "old")
        #expect(account.endpoint == "https://sync.example/configuration")
        #expect(account.errorMessage != nil)
        storage.failRemove = true
        #expect(throws: SyncStorageError.self) { try account.disconnect() }
        #expect(account.isConnected)
        storage.failRemove = false
        try account.disconnect()
    }
}

private enum SyncStorageError: Error { case failed }

@MainActor private final class SyncConnectionStorage {
    var data: Data?
    var failSave = false
    var failRemove = false
    var storage: ConfigurationSyncAccount.ConnectionStorage {
        .init(load: { self.data }, save: {
            if self.failSave { throw SyncStorageError.failed }
            self.data = $0
        }, remove: {
            if self.failRemove { throw SyncStorageError.failed }
            self.data = nil
        })
    }
}

private final class SyncAccountProtocol: URLProtocol, @unchecked Sendable {
    struct State {
        var body: Data?
        var revision = 0
        var requests = 0
        var failPut = false
        var afterPut: (@MainActor @Sendable () -> Void)?
        var afterGet: (@MainActor @Sendable () -> Void)?
    }
    static let state = Mutex(State())
    static func setRemote(_ envelope: EncryptedConfiguration) throws {
        var body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any] ?? [:]
        state.withLock { state in
            state.revision += 1
            body["_rev"] = "\(state.revision)-fixture"
            state.body = try? JSONSerialization.data(withJSONObject: body)
        }
    }
    static func envelope() throws -> EncryptedConfiguration? {
        try state.withLock { state in
            try state.body.map { try JSONDecoder().decode(EncryptedConfiguration.self, from: $0) }
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body): (Int, Data) = Self.state.withLock { state in
            state.requests += 1
            if request.httpMethod == "GET" { return (state.body == nil ? 404 : 200, state.body ?? Data()) }
            if state.failPut { return (503, Data()) }
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (400, Data()) }
            let expected = state.body == nil ? nil : "\(state.revision)-fixture"
            guard json["_rev"] as? String == expected else { return (409, Data()) }
            state.revision += 1
            let revision = "\(state.revision)-fixture"
            json["_rev"] = revision
            state.body = try? JSONSerialization.data(withJSONObject: json)
            return (201, Data("{\"ok\":true,\"rev\":\"\(revision)\"}".utf8))
        }
        let afterPut = Self.state.withLock { state in
            if request.httpMethod == "PUT" {
                let action = state.afterPut
                state.afterPut = nil
                return action
            }
            let action = state.afterGet
            state.afterGet = nil
            return action
        }
        if let afterPut {
            Task { @Sendable [self] in
                await afterPut()
                self.finish(status: status, body: body)
            }
        } else {
            finish(status: status, body: body)
        }
    }
    private func finish(status: Int, body: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

actor ConfigurationSyncLiveTestLock {
    static let shared = ConfigurationSyncLiveTestLock()
    private var held = false
    func acquire() async {
        while held { try? await Task.sleep(for: .milliseconds(20)) }
        held = true
    }
    func release() { held = false }
}
