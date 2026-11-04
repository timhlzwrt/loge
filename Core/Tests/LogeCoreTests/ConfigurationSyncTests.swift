import Foundation
import Synchronization
import Testing
@testable import LogeCore

struct ConfigurationSyncTests {
    @Test func independentEditsMergeAndRemovalDoesNotReturn() {
        let base = SyncedConfiguration(addonURLs: ["https://a.example/manifest.json"])
        var local = base; local.addonURLs = []; local.audioLanguage = "de"
        var remote = base; remote.accent = "mint"
        let result = SyncedConfiguration.merged(base: base, local: local, remote: remote)
        #expect(result.conflicts.isEmpty)
        #expect(result.configuration.addonURLs.isEmpty)
        #expect(result.configuration.audioLanguage == "de")
        #expect(result.configuration.accent == "mint")
    }

    @Test func concurrentReorderingAndRemovalNeedChoice() {
        let a = "https://a.example/manifest.json", b = "https://b.example/manifest.json"
        let base = SyncedConfiguration(addonURLs: [a, b])
        var local = base; local.addonURLs = [b, a]; local.subtitleLanguage = "de"
        var remote = base; remote.addonURLs = [a]; remote.subtitleLanguage = "fr"
        let result = SyncedConfiguration.merged(base: base, local: local, remote: remote)
        #expect(result.conflicts == [.addonURLs, .subtitleLanguage])
        #expect(result.configuration == local)
    }

    @Test func encryptionRoundTripUsesFreshNonceAndRejectsWrongKeyOrTampering() throws {
        let key = ConfigurationCipher.generateKey()
        let cipher = try ConfigurationCipher(key: key)
        let configuration = SyncedConfiguration(addonURLs: ["https://addon.example/synthetic-credential/manifest.json"])
        let sealed = try cipher.seal(configuration)
        #expect(try cipher.open(sealed) == configuration)
        #expect(try cipher.seal(configuration) != sealed)
        #expect(!sealed.ciphertext.contains("synthetic-credential"))
        let other = try ConfigurationCipher(key: ConfigurationCipher.generateKey())
        #expect(throws: ConfigurationSyncError.decryptionFailed) { try other.open(sealed) }
        var damaged = try #require(Data(base64Encoded: sealed.ciphertext)); damaged[15] ^= 1
        #expect(throws: ConfigurationSyncError.decryptionFailed) {
            try cipher.open(EncryptedConfiguration(ciphertext: damaged.base64EncodedString()))
        }
        #expect(throws: ConfigurationSyncError.unsupportedVersion) {
            try cipher.open(EncryptedConfiguration(version: 2, ciphertext: sealed.ciphertext))
        }
    }

    @Test func validatesCompleteConfiguration() throws {
        var invalid = SyncedConfiguration(); invalid.subtitleScale = .infinity
        #expect(throws: ConfigurationSyncError.invalidConfiguration) { try invalid.validated() }
        invalid = SyncedConfiguration(addonURLs: ["https://a.example/manifest.json", "https://a.example/manifest.json"])
        #expect(throws: ConfigurationSyncError.invalidConfiguration) { try invalid.validated() }
        invalid = SyncedConfiguration(addonURLs: ["https://a.example/not-a-manifest"])
        #expect(throws: ConfigurationSyncError.invalidConfiguration) { try invalid.validated() }
        #expect(throws: ConfigurationSyncError.invalidKey) { try ConfigurationCipher(key: "short") }
    }

    @Test(arguments: ["http://sync.example/configuration", "https://name:secret@sync.example/configuration",
                      "https://sync.example/configuration?new_edits=false", "https://sync.example/configuration#part", "https://sync.example"])
    func rejectsUnsafeEndpoint(_ endpoint: String) {
        #expect(throws: ConfigurationSyncError.invalidEndpoint) {
            try ConfigurationSyncClient(endpoint: endpoint, username: "user", password: "password")
        }
    }

    @MainActor @Test func addonReplacementIsAtomicAndRetainsCachedManifest() async throws {
        let defaults = UserDefaults(suiteName: "ConfigurationSyncTests-\(UUID().uuidString)")!
        let manifest = try decodeFixture("stream-addon-manifest", as: AddonManifest.self)
        let store = AddonStore(defaults: defaults) { _ in manifest }
        try await store.install(manifestURL: "https://a.example/manifest.json")
        try store.replaceManifestURLs(["https://new.example/manifest.json", "https://a.example/manifest.json"])
        #expect(store.addons[0].manifest == nil)
        #expect(store.addons[1].manifest == manifest)
        #expect(throws: ConfigurationSyncError.invalidConfiguration) { try store.replaceManifestURLs(["broken"]) }
        #expect(store.addons.count == 2)
        #expect(AddonStore(defaults: defaults).addons == store.addons)
        try store.replaceManifestURLs(["https://a.example/manifest.json"])
        #expect(AddonStore(defaults: defaults).addons.map(\.manifestURL) == ["https://a.example/manifest.json"])
        try store.replaceManifestURLs([])
        #expect(AddonStore(defaults: defaults).addons.isEmpty)
    }

    @Test func transportPreservesRevisionAndMapsFailuresWithoutServerDetails() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ConfigurationProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let envelope = try ConfigurationCipher(key: ConfigurationCipher.generateKey()).seal(SyncedConfiguration())
        let fixture = UUID().uuidString
        // Separate paths keep parallel tests from sharing fixture state.
        let active = try ConfigurationSyncClient(endpoint: "https://sync.example/\(fixture)", username: "user", password: "password", session: session)
        ConfigurationProtocol.responses.withLock { $0[fixture] = (200, try! JSONSerialization.data(withJSONObject: ["_rev":"1-initial", "version":1,"ciphertext":envelope.ciphertext])) }
        let remote = try #require(try await active.fetch())
        #expect(remote.revision == "1-initial" && remote.envelope == envelope)
        ConfigurationProtocol.responses.withLock { $0[fixture] = (201, Data(#"{"ok":true,"rev":"2-next"}"#.utf8)) }
        #expect(try await active.put(envelope, revision: remote.revision) == "2-next")
        let body = try #require(ConfigurationProtocol.bodies.withLock { $0[fixture] })
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["_rev"] as? String == "1-initial")
        for (status, error) in [(409, ConfigurationSyncError.conflict), (401, .unauthorized), (302, .httpStatus(302))] {
            ConfigurationProtocol.responses.withLock { $0[fixture] = (status, Data("private server details".utf8)) }
            await #expect(throws: error) { try await active.put(envelope, revision: "old") }
        }
        ConfigurationProtocol.responses.withLock { $0[fixture] = (404, Data()) }
        #expect(try await active.fetch() == nil)
    }

    @Test func oversizedResponseIsRejected() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ConfigurationProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let fixture = UUID().uuidString
        ConfigurationProtocol.responses.withLock { $0[fixture] = (200, Data(repeating: 65, count: ConfigurationSyncClient.maximumBytes + 1)) }
        let client = try ConfigurationSyncClient(endpoint: "https://sync.example/\(fixture)", username: "u", password: "p", session: session)
        await #expect(throws: ConfigurationSyncError.responseTooLarge) { try await client.fetch() }
    }
}

private final class ConfigurationProtocol: URLProtocol, @unchecked Sendable {
    static let responses = Mutex<[String: (Int, Data)]>([:])
    static let bodies = Mutex<[String: Data]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let key = url.lastPathComponent
        var bodyData = request.httpBody
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            bodyData = data
        }
        Self.bodies.withLock { $0[key] = bodyData }
        let (status, body) = Self.responses.withLock { $0[key] ?? (404, Data()) }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Length":String(body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// Keep both optional tests against the same document in one serialized suite.
extension ConfigurationSyncAccountTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LOGE_SYNC_TEST_CONNECTION_FILE"] != nil))
    func liveEncryptedDocumentRoundTripAndStaleWrite() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LOGE_SYNC_TEST_CONNECTION_FILE"])
        struct Connection: Decodable {
            let endpoint: String
            let username: String
            let password: String
            let recoveryKey: String?
            let key: String?
        }
        let connection = try JSONDecoder().decode(Connection.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let key = try #require(connection.recoveryKey ?? connection.key)
        let client = try ConfigurationSyncClient(endpoint: connection.endpoint, username: connection.username, password: connection.password)
        let cipher = try ConfigurationCipher(key: key)
        let original = try await client.fetch()
        let synthetic = SyncedConfiguration(subtitleLanguage: "de", accent: "mint")
        let envelope = try cipher.seal(synthetic)
        let revision = try await client.put(envelope, revision: original?.revision)
        do {
            let received = try #require(try await client.fetch())
            #expect(received.revision == revision)
            #expect(try cipher.open(received.envelope) == synthetic)
            await #expect(throws: ConfigurationSyncError.conflict) {
                try await client.put(envelope, revision: original?.revision)
            }
        } catch {
            if let original { _ = try await client.put(original.envelope, revision: revision) }
            throw error
        }
        if let original { _ = try await client.put(original.envelope, revision: revision) }
    }

}
