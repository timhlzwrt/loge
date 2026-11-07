import Foundation
import Synchronization
import Testing
@testable import LogeCore

struct SyncedSettingsTests {
    @Test func independentEditsMergeAndRemovalDoesNotReturn() {
        let base = SyncedSettings(addonURLs: ["https://a.example/manifest.json"])
        var local = base; local.addonURLs = []; local.audioLanguage = "de"
        var remote = base; remote.accent = .mint
        let result = SyncedSettings.merged(base: base, local: local, remote: remote)
        #expect(result.conflicts.isEmpty)
        #expect(result.settings.addonURLs.isEmpty)
        #expect(result.settings.audioLanguage == "de")
        #expect(result.settings.accent == .mint)
    }

    @Test func concurrentReorderingAndRemovalNeedChoice() {
        let a = "https://a.example/manifest.json", b = "https://b.example/manifest.json"
        let base = SyncedSettings(addonURLs: [a, b])
        var local = base; local.addonURLs = [b, a]; local.subtitleLanguage = "de"
        var remote = base; remote.addonURLs = [a]; remote.subtitleLanguage = "fr"
        let result = SyncedSettings.merged(base: base, local: local, remote: remote)
        #expect(result.conflicts == [.addonURLs, .subtitleLanguage])
        #expect(result.settings == local)
    }

    @Test func encryptionUsesFreshNonceAndRejectsTamperingAndOtherVersions() throws {
        let cipher = try AccountSyncCipher(key: AccountSyncCipher.generateKey(), resource: "configuration")
        let settings = SyncedSettings(addonURLs: ["https://addon.example/synthetic-credential/manifest.json"])
        let sealed = try cipher.seal(settings)
        #expect(try cipher.open(sealed, as: SyncedSettings.self) == settings)
        #expect(try cipher.seal(settings).ciphertext != sealed.ciphertext)
        #expect(!sealed.ciphertext.contains("synthetic-credential"))
        var damaged = try #require(Data(base64Encoded: sealed.ciphertext)); damaged[15] ^= 1
        #expect(throws: SyncError.decryptionFailed) {
            try cipher.open(AccountSyncDocument(version: 2, ciphertext: damaged.base64EncodedString()), as: SyncedSettings.self)
        }
        #expect(throws: SyncError.unsupportedVersion) {
            try cipher.open(AccountSyncDocument(version: 1, ciphertext: sealed.ciphertext), as: SyncedSettings.self)
        }
    }

    @Test func validatesCompleteSettings() throws {
        var invalid = SyncedSettings(); invalid.subtitleScale = .infinity
        #expect(throws: SyncError.invalidData) { try invalid.validated() }
        invalid = SyncedSettings(addonURLs: ["https://a.example/manifest.json", "https://a.example/manifest.json"])
        #expect(throws: SyncError.invalidData) { try invalid.validated() }
        invalid = SyncedSettings(addonURLs: ["https://a.example/not-a-manifest"])
        #expect(throws: SyncError.invalidData) { try invalid.validated() }
        #expect(throws: SyncError.invalidKey) { try AccountSyncCipher(key: "short", resource: "configuration") }
        let unknownAccent = Data(#"{"addonURLs":[],"audioLanguage":"en","subtitleLanguage":"","subtitleScale":1,"maximumSourceGigabytes":50,"accent":"purple"}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SyncedSettings.self, from: unknownAccent) }
    }

    @MainActor @Test func unsetPreferencesReadAsDefaultsAndCategoriesWriteOnlyTheirOwn() {
        let defaults = UserDefaults(suiteName: "SyncedSettingsTests-\(UUID().uuidString)")!
        #expect(SyncedSettings(addonURLs: [], defaults: defaults) == SyncedSettings())
        SyncedSettings(audioLanguage: "de", accent: .coral).writePreferences(to: defaults, categories: [.appearance])
        #expect(defaults.string(forKey: SyncedSettings.Key.accent) == "coral")
        #expect(defaults.string(forKey: SyncedSettings.Key.audioLanguage) == nil)
    }

    @Test(arguments: ["http://sync.example/v2", "https://name:secret@sync.example/v2",
                      "https://sync.example/v2?new_edits=false", "https://sync.example/v2#part", "https://sync.example"])
    func rejectsUnsafeEndpoint(_ endpoint: String) {
        #expect(throws: SyncError.invalidEndpoint) { try AccountSyncClient(endpoint: endpoint) }
    }

    @MainActor @Test func addonReplacementIsAtomicAndRetainsCachedManifest() async throws {
        let defaults = UserDefaults(suiteName: "SyncedSettingsTests-\(UUID().uuidString)")!
        let manifest = try decodeFixture("stream-addon-manifest", as: AddonManifest.self)
        let store = AddonStore(defaults: defaults) { _ in manifest }
        try await store.install(manifestURL: "https://a.example/manifest.json")
        try store.replaceManifestURLs(["https://new.example/manifest.json", "https://a.example/manifest.json"])
        #expect(store.addons[0].manifest == nil)
        #expect(store.addons[1].manifest == manifest)
        #expect(throws: SyncError.invalidData) { try store.replaceManifestURLs(["broken"]) }
        #expect(store.addons.count == 2)
        #expect(AddonStore(defaults: defaults).addons == store.addons)
        try store.replaceManifestURLs(["https://a.example/manifest.json"])
        #expect(AddonStore(defaults: defaults).addons.map(\.manifestURL) == ["https://a.example/manifest.json"])
        try store.replaceManifestURLs([])
        #expect(AddonStore(defaults: defaults).addons.isEmpty)
    }

    @Test func transportPreservesRevisionAndMapsFailuresWithoutServerDetails() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyncTransportProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let document = try AccountSyncCipher(key: AccountSyncCipher.generateKey(), resource: "progress").seal(PlaybackSyncSnapshot())
        // Separate resources keep parallel tests from sharing fixture state.
        let resource = "documents/\(UUID().uuidString)"
        let fixture = URL(fileURLWithPath: resource).lastPathComponent
        let client = try AccountSyncClient(endpoint: "https://sync.example/v2", token: "token", session: session)
        SyncTransportProtocol.responses.withLock { $0[fixture] = (200, try! JSONSerialization.data(withJSONObject: ["_rev": "1-initial", "version": 2, "ciphertext": document.ciphertext])) }
        let remote = try #require(try await client.fetch(resource))
        #expect(remote.revision == "1-initial" && remote.ciphertext == document.ciphertext)
        SyncTransportProtocol.responses.withLock { $0[fixture] = (201, Data(#"{"ok":true,"rev":"2-next"}"#.utf8)) }
        #expect(try await client.put(document, resource: resource, revision: remote.revision) == "2-next")
        let body = try #require(SyncTransportProtocol.bodies.withLock { $0[fixture] })
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["_rev"] as? String == "1-initial")
        let failures: [(Int, SyncError)] = [(409, .conflict), (401, .unauthorized), (410, .expiredInvitation),
                                            (428, .recoveryRequired), (302, .httpStatus(302))]
        for (status, error) in failures {
            SyncTransportProtocol.responses.withLock { $0[fixture] = (status, Data("private server details".utf8)) }
            await #expect(throws: error) { try await client.put(document, resource: resource, revision: "old") }
        }
        SyncTransportProtocol.responses.withLock { $0[fixture] = (404, Data()) }
        #expect(try await client.fetch(resource) == nil)
    }

    @Test func oversizedResponseIsRejected() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyncTransportProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let fixture = UUID().uuidString
        SyncTransportProtocol.responses.withLock { $0[fixture] = (200, Data(repeating: 65, count: AccountSyncClient.maximumBytes + 1)) }
        let client = try AccountSyncClient(endpoint: "https://sync.example/v2", token: "token", session: session)
        await #expect(throws: SyncError.tooLarge) { try await client.fetch("documents/\(fixture)") }
    }
}

private final class SyncTransportProtocol: StubURLProtocol, @unchecked Sendable {
    static let responses = Mutex<[String: (Int, Data)]>([:])
    static let bodies = Mutex<[String: Data]>([:])
    override func startLoading() {
        guard let url = request.url else { return }
        let key = url.lastPathComponent
        let sent = requestBody
        Self.bodies.withLock { $0[key] = sent }
        let (status, body) = Self.responses.withLock { $0[key] ?? (404, Data()) }
        respond(status, body: body)
    }
}
