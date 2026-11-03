import Foundation
import Testing
@testable import LogeCore

@MainActor
struct AddonStoreTests {
    let defaults = UserDefaults(suiteName: "AddonStoreTests-\(UUID().uuidString)")!
    let manifest = try! decodeFixture("stream-addon-manifest", as: AddonManifest.self)

    /// Serves `manifest` for every host except `offline.example` and `garbage.example`.
    func makeStore() -> AddonStore {
        let manifest = manifest
        return AddonStore(defaults: defaults) { client in
            switch client.baseURL.host() {
            case "offline.example": throw URLError(.notConnectedToInternet)
            case "garbage.example": throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not JSON"))
            default: return manifest
            }
        }
    }

    @Test func startsWithoutInstalledAddons() {
        #expect(makeStore().addons.isEmpty)
    }

    @Test func installPersistsAcrossStores() async throws {
        try await makeStore().install(manifestURL: "https://a.example/manifest.json")

        let reloaded = makeStore()
        #expect(reloaded.addons.map(\.manifestURL) == ["https://a.example/manifest.json"])
        #expect(reloaded.addons.last?.displayName == "Example Streams")
    }

    @Test func rejectsEquivalentURLAsDuplicate() async throws {
        let store = makeStore()
        try await store.install(manifestURL: "https://a.example/manifest.json")

        await #expect(throws: AddonStore.InstallError.alreadyInstalled) {
            try await store.install(manifestURL: "stremio://a.example/manifest.json")
        }
    }

    @Test func reportsWhyInstallFailed() async {
        let store = makeStore()

        await #expect(throws: AddonStore.InstallError.invalidURL) {
            try await store.install(manifestURL: "not a url")
        }
        await #expect(throws: AddonStore.InstallError.invalidManifest) {
            try await store.install(manifestURL: "https://garbage.example/manifest.json")
        }
        await #expect {
            try await store.install(manifestURL: "https://offline.example/manifest.json")
        } throws: { error in
            if case .unreachable = error as? AddonStore.InstallError { true } else { false }
        }
        #expect(store.addons.isEmpty)
    }

    @Test func removingEverythingDoesNotRestoreCinemeta() async throws {
        let store = makeStore()
        let installed = try await store.install(manifestURL: "https://a.example/manifest.json")
        store.remove(installed.id)
        #expect(makeStore().addons.isEmpty)
    }

    @Test func movesLikeSwiftUIOnMove() async throws {
        let store = makeStore()
        try await store.install(manifestURL: "https://a.example/manifest.json")
        try await store.install(manifestURL: "https://b.example/manifest.json")
        try await store.install(manifestURL: "https://c.example/manifest.json")

        // Move the first addon to the end, as dragging it below the last row would.
        store.move(fromOffsets: [0], toOffset: 3)

        #expect(makeStore().addons.map { URL(string: $0.manifestURL)!.host()! }
            == ["b.example", "c.example", "a.example"])
    }

    @Test func refreshFillsManifestsAndFlagsUnreachableAddons() async throws {
        let store = makeStore()
        try await store.install(manifestURL: "https://a.example/manifest.json")
        // Install an addon whose host then goes offline, by writing it straight to storage.
        let offline = InstalledAddon(manifestURL: "https://offline.example/manifest.json", manifest: manifest)
        let pending = InstalledAddon(manifestURL: store.addons[0].manifestURL, manifest: nil)
        defaults.set(try JSONEncoder().encode([pending, offline]), forKey: "installedAddons")
        let reloaded = makeStore()

        await reloaded.refreshManifests()

        #expect(reloaded.addons[0].manifest != nil)
        #expect(reloaded.unreachable == [offline.id])
        #expect(reloaded.addons[1].manifest == manifest)
    }

    @Test func migratesOnlyTheLegacyBuiltinCatalogAddon() throws {
        let saved = [
            InstalledAddon(manifestURL: "https://a.example/manifest.json", manifest: manifest),
            InstalledAddon(manifestURL: AddonStore.cinemetaURL, manifest: nil),
            InstalledAddon(manifestURL: "https://v3-cinemeta.strem.io/custom/manifest.json", manifest: manifest),
            InstalledAddon(manifestURL: "https://b.example/manifest.json", manifest: manifest),
        ]
        defaults.set(try JSONEncoder().encode(saved), forKey: "installedAddons")

        #expect(makeStore().addons == [saved[0], saved[2], saved[3]])
    }
}
