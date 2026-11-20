import Foundation
import Synchronization
import Testing
@testable import LogeCore

struct SyncedSettingsTests {
    @Test func independentEditsMergeAndRemovalDoesNotReturn() {
        let base = SyncedSettings(addonURLs: ["https://a.example/manifest.json"])
        var local = base; local.addonURLs = []; local.audioLanguage = "de"
        var remote = base; remote.maximumBitrate = 25
        let result = SyncedSettings.merged(base: base, local: local, remote: remote)
        #expect(result.conflicts.isEmpty)
        #expect(result.settings.addonURLs.isEmpty)
        #expect(result.settings.audioLanguage == "de")
        #expect(result.settings.maximumBitrate == 25)
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

    /// Names and the combined-sources setting sync with the addons; setups from before them
    /// read as no names and one addon at a time.
    @MainActor @Test func addonNamesAndCombiningTravelWithTheAddons() throws {
        let a = "https://a.example/manifest.json", b = "https://b.example/manifest.json"
        let base = SyncedSettings(addonURLs: [a, b])
        var local = base; local.addonNames = [a: "German"]
        var remote = base; remote.combinesAddonSources = true
        let merged = SyncedSettings.merged(base: base, local: local, remote: remote)
        #expect(merged.conflicts.isEmpty)
        #expect(merged.settings.addonNames == [a: "German"])
        #expect(merged.settings.combinesAddonSources)

        let old = #"{"addonURLs":[],"audioLanguage":"en","subtitleLanguage":"","subtitleScale":1,"maximumBitrate":100}"#
        let decoded = try JSONDecoder().decode(SyncedSettings.self, from: Data(old.utf8))
        #expect(decoded.addonNames.isEmpty && !decoded.combinesAddonSources)
        #expect(try JSONDecoder().decode(SyncedSettings.self, from: JSONEncoder().encode(merged.settings)) == merged.settings)

        // A name for an addon that isn't there, or an empty one, isn't a valid setup.
        #expect(throws: SyncError.invalidData) { try SyncedSettings(addonURLs: [a], addonNames: [b: "English"]).validated() }
        #expect(throws: SyncError.invalidData) { try SyncedSettings(addonURLs: [a], addonNames: [a: ""]).validated() }

        let defaults = UserDefaults(suiteName: "SyncedSettingsTests-\(UUID().uuidString)")!
        let store = AddonStore(defaults: defaults) { _ in throw AddonError.invalidResponse }
        let setup = AccountSyncLocalSetup(addons: store, defaults: defaults)
        try setup.apply(merged.settings)
        #expect(store.addons.map(\.displayName) == ["German", "b.example"])
        #expect(setup.current == merged.settings)
    }

    @MainActor @Test func cachedOnlySyncsWithThePlaybackPreferences() throws {
        let defaults = UserDefaults(suiteName: "SyncedSettingsTests-\(UUID().uuidString)")!
        let settings = SyncedSettings(cachedOnly: true)
        settings.writePreferences(to: defaults)
        #expect(SyncedSettings(addonURLs: [], defaults: defaults).cachedOnly)
        #expect(try JSONDecoder().decode(SyncedSettings.self, from: JSONEncoder().encode(settings)) == settings)
        #expect(SyncedSettings().replacing(categories: [.playback], from: settings).cachedOnly)
        var remote = SyncedSettings(); remote.cachedOnly = true
        #expect(SyncedSettings.merged(base: SyncedSettings(), local: SyncedSettings(), remote: remote).settings.cachedOnly)
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
        invalid = SyncedSettings(maximumBitrate: 40)
        #expect(throws: SyncError.invalidData) { try invalid.validated() }
    }

    @Test func readsSetupsFromBeforeTheBitrateLimitAndStaysReadableForThem() throws {
        func decoded(_ limit: String) throws -> SyncedSettings {
            let json = #"{"addonURLs":[],"audioLanguage":"de","subtitleLanguage":"","subtitleScale":1,"# + limit + #""accent":"white"}"#
            return try JSONDecoder().decode(SyncedSettings.self, from: Data(json.utf8))
        }
        #expect(try decoded(#""maximumSourceGigabytes":0,"#).maximumBitrate == 0)
        #expect(try decoded(#""maximumSourceGigabytes":25,"#).maximumBitrate == 100)
        #expect(try decoded("").maximumBitrate == 100)
        #expect(try decoded(#""maximumBitrate":25,"maximumSourceGigabytes":50,"#).maximumBitrate == 25)
        #expect(try decoded(#""maximumSourceGigabytes":0,"#).audioLanguage == "de")

        // The accent setting is gone: any colour a released build wrote is ignored.
        #expect(try decoded(#""maximumBitrate":25,"accent":"coral","#).maximumBitrate == 25)

        // Older versions require a size limit in a valid range, and the accent they offered.
        let settings = SyncedSettings(maximumBitrate: 25)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        #expect(object["maximumSourceGigabytes"] as? Int == 50)
        #expect(object["accent"] as? String == "white")
        #expect(try JSONDecoder().decode(SyncedSettings.self, from: JSONEncoder().encode(settings)) == settings)
        var unlimited = settings; unlimited.maximumBitrate = 0
        let unlimitedObject = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(unlimited)) as? [String: Any])
        #expect(unlimitedObject["maximumSourceGigabytes"] as? Int == 0)
    }

    @Test func migratesAStoredSizeLimitOnce() {
        let defaults = UserDefaults(suiteName: "SyncedSettingsTests-\(UUID().uuidString)")!
        defaults.set(0, forKey: SyncedSettings.Key.maximumSourceGigabytes)
        SyncedSettings.migrateSourceSizeLimit(in: defaults)
        #expect(defaults.object(forKey: SyncedSettings.Key.maximumBitrate) as? Int == 0)
        #expect(defaults.object(forKey: SyncedSettings.Key.maximumSourceGigabytes) == nil)

        defaults.set(25, forKey: SyncedSettings.Key.maximumBitrate)
        defaults.set(10, forKey: SyncedSettings.Key.maximumSourceGigabytes)
        SyncedSettings.migrateSourceSizeLimit(in: defaults)
        #expect(defaults.object(forKey: SyncedSettings.Key.maximumBitrate) as? Int == 25)

        let other = UserDefaults(suiteName: "SyncedSettingsTests-\(UUID().uuidString)")!
        other.set(50, forKey: SyncedSettings.Key.maximumSourceGigabytes)
        SyncedSettings.migrateSourceSizeLimit(in: other)
        #expect(other.object(forKey: SyncedSettings.Key.maximumBitrate) as? Int == 100)
    }

    @MainActor @Test func unsetPreferencesReadAsDefaultsAndWrittenOnesReadBack() {
        let defaults = UserDefaults(suiteName: "SyncedSettingsTests-\(UUID().uuidString)")!
        #expect(SyncedSettings(addonURLs: [], defaults: defaults) == SyncedSettings())
        let settings = SyncedSettings(audioLanguage: "de", maximumBitrate: 25)
        settings.writePreferences(to: defaults)
        #expect(SyncedSettings(addonURLs: [], defaults: defaults) == settings)
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
