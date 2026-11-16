import Foundation
import Testing
@testable import LogeCore

@MainActor
struct SetupCodeTests {
    let defaults = UserDefaults(suiteName: "SetupCodeTests-\(UUID().uuidString)")!
    let manifest = try! decodeFixture("stream-addon-manifest", as: AddonManifest.self)
    /// Synthetic, shaped like a configured addon: its settings, keys included, in the path.
    let configured = "https://streams.example/stremio/\(UUID())/eyJhcGlLZXkiOiJzeW50aGV0aWMifQ/manifest.json"

    /// Serves `manifest` for every host except `offline.example`.
    func makeStore() -> AddonStore {
        let manifest = manifest
        return AddonStore(defaults: defaults) { client in
            if client.baseURL.host() == "offline.example" { throw AddonError.unavailable(.notConnectedToInternet) }
            return manifest
        }
    }

    @Test func roundTripsAddonsInOrderWithOrWithoutPreferences() throws {
        let addons = [configured, "https://subtitles.example/manifest.json"]
        let plain = SetupCode(addonURLs: addons)
        let encoded = try plain.encoded()
        #expect(encoded.hasPrefix("loge-setup-1:"))
        #expect(try SetupCode(decoding: encoded) == plain)
        #expect(try SetupCode(decoding: "  \(encoded)\n") == plain)

        let preferences = SetupCode.Preferences(audioLanguage: "de", subtitleLanguage: "en", maximumBitrate: 25)
        let full = SetupCode(addonURLs: addons, preferences: preferences)
        let link = SetupCode.linkPrefix + (try full.encoded())
        #expect(link.hasPrefix("loge://setup#loge-setup-1:"))
        #expect(try SetupCode(decoding: link) == full)
    }

    @Test func preferencesReadAndWriteThePlaybackSettings() {
        defaults.set("fr", forKey: SyncedSettings.Key.audioLanguage)
        defaults.set(10, forKey: SyncedSettings.Key.maximumBitrate)
        let preferences = SetupCode.Preferences(defaults: defaults)
        #expect(preferences == .init(audioLanguage: "fr", subtitleLanguage: "", maximumBitrate: 10))
        let other = UserDefaults(suiteName: "SetupCodeTests-\(UUID().uuidString)")!
        preferences.write(to: other)
        #expect(SetupCode.Preferences(defaults: other) == preferences)
    }

    @Test func aLaterVersionAsksForAnUpdate() throws {
        let encoded = try SetupCode(addonURLs: [configured]).encoded()
        let later = encoded.replacingOccurrences(of: "loge-setup-1:", with: "loge-setup-2:")
        #expect(throws: SetupCode.DecodingError.newerVersion) { try SetupCode(decoding: later) }
    }

    @Test(arguments: ["", "loge-setup-1:", "loge-setup-x:abc", "setup-1:abc", "loge-setup-1:!!!!", "https://streams.example/manifest.json"])
    func rejectsMalformedText(_ text: String) {
        #expect(throws: SetupCode.DecodingError.malformed) { try SetupCode(decoding: text) }
    }

    @Test func rejectsCutOffCodesAndUnsafeContents() throws {
        let encoded = try SetupCode(addonURLs: [configured, "https://subtitles.example/manifest.json"]).encoded()
        #expect(throws: SetupCode.DecodingError.malformed) { try SetupCode(decoding: String(encoded.dropLast(12))) }
        for contents in [SetupCode(addonURLs: []),
                         SetupCode(addonURLs: [configured, configured]),
                         SetupCode(addonURLs: [AddonStore.cinemetaURL]),
                         SetupCode(addonURLs: [configured, "not a url"]),
                         SetupCode(addonURLs: [configured], preferences: .init(audioLanguage: "xx", subtitleLanguage: "", maximumBitrate: 25)),
                         SetupCode(addonURLs: [configured], preferences: .init(audioLanguage: "en", subtitleLanguage: "", maximumBitrate: 7))] {
            #expect(throws: SetupCode.DecodingError.malformed) { try SetupCode(decoding: try contents.encoded()) }
        }
    }

    @Test func aCodeThatFailsToDecodeChangesNothing() async throws {
        let store = makeStore()
        try await store.install(manifestURL: "https://mine.example/manifest.json")
        let mixed = try SetupCode(addonURLs: ["https://new.example/manifest.json", "not a url"]).encoded()
        #expect(throws: SetupCode.DecodingError.malformed) { try SetupCode(decoding: mixed) }
        #expect(store.addons.map(\.manifestURL) == ["https://mine.example/manifest.json"])
    }

    @Test func addingAppendsOnlyAddonsNotInstalledAndReportsFailuresByHost() async throws {
        let store = makeStore()
        try await store.install(manifestURL: "https://mine.example/manifest.json")
        let code = SetupCode(addonURLs: ["https://new.example/manifest.json", "https://mine.example/manifest.json",
                                         "https://offline.example/manifest.json"])
        let result = await store.importSetup(code, replacing: false)
        #expect(result.added == ["new.example"])
        #expect(result.failed.map(\.host) == ["offline.example"])
        #expect(store.addons.map(\.host) == ["mine.example", "new.example"])
        #expect(store.addons.allSatisfy { $0.manifest != nil })
    }

    @Test func replacingTakesTheCodesAddonsAndOrderOnlyWhenAllInstall() async throws {
        let store = makeStore()
        try await store.install(manifestURL: "https://mine.example/manifest.json")
        try await store.install(manifestURL: "https://shared.example/manifest.json")

        let failing = SetupCode(addonURLs: ["https://new.example/manifest.json", "https://offline.example/manifest.json"])
        let kept = await store.importSetup(failing, replacing: true)
        #expect(kept.keptExisting && !kept.replaced && kept.failed.map(\.host) == ["offline.example"])
        #expect(store.addons.map(\.host) == ["mine.example", "shared.example", "new.example"])

        let code = SetupCode(addonURLs: ["https://other.example/manifest.json", "https://shared.example/manifest.json"])
        let replaced = await store.importSetup(code, replacing: true)
        #expect(replaced.replaced && !replaced.keptExisting && replaced.failed.isEmpty && replaced.added == ["other.example"])
        #expect(store.addons.map(\.host) == ["other.example", "shared.example"])
        #expect(store.addons.allSatisfy { $0.manifest != nil })
    }
}
