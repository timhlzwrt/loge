import Foundation
import Testing
@testable import MediaCore

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

    @Test func startsWithCinemeta() {
        #expect(makeStore().addons.map(\.manifestURL) == [AddonStore.cinemetaURL])
    }

    @Test func installPersistsAcrossStores() async throws {
        try await makeStore().install(manifestURL: "https://a.example/manifest.json")

        let reloaded = makeStore()
        #expect(reloaded.addons.map(\.manifestURL) == [AddonStore.cinemetaURL, "https://a.example/manifest.json"])
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
        #expect(store.addons.count == 1)
    }

    @Test func removingEverythingDoesNotRestoreCinemeta() {
        makeStore().remove(AddonStore.cinemetaURL)
        #expect(makeStore().addons.isEmpty)
    }

    @Test func movesLikeSwiftUIOnMove() async throws {
        let store = makeStore()
        try await store.install(manifestURL: "https://a.example/manifest.json")
        try await store.install(manifestURL: "https://b.example/manifest.json")

        // Move Cinemeta (index 0) to the end, as dragging it below the last row would.
        store.move(fromOffsets: [0], toOffset: 3)

        #expect(makeStore().addons.map { URL(string: $0.manifestURL)!.host()! }
            == ["a.example", "b.example", "v3-cinemeta.strem.io"])
    }

    @Test func refreshFillsManifestsAndFlagsUnreachableAddons() async throws {
        let store = makeStore()
        try await store.install(manifestURL: "https://a.example/manifest.json")
        // Install an addon whose host then goes offline, by writing it straight to storage.
        let offline = InstalledAddon(manifestURL: "https://offline.example/manifest.json", manifest: manifest)
        defaults.set(try JSONEncoder().encode(store.addons + [offline]), forKey: "installedAddons")
        let reloaded = makeStore()

        await reloaded.refreshManifests()

        #expect(reloaded.addons[0].manifest != nil)
        #expect(reloaded.unreachable == [offline.id])
        #expect(reloaded.addons[2].manifest == manifest)
    }
}
