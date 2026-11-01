import Testing
@testable import MediaCore

struct DiscoveryCatalogsTests {
    @Test func homeProvidesDistinctBrowsableShelves() {
        let shelves = DiscoveryCatalogs.home
        #expect(shelves.count == 7)
        #expect(Set(shelves.map(\.id)).count == shelves.count)
        #expect(shelves.allSatisfy { $0.manifestURL == AddonStore.cinemetaURL })
        #expect(shelves.allSatisfy { $0.catalog.supportsPaging })
        #expect(shelves.allSatisfy { $0.catalog.isBrowsable })
        #expect(shelves.compactMap(\.defaultGenre) == ["Crime", "Sci-Fi", "Animation"])
        #expect(shelves.first?.title == "Popular Movies")
    }

    @Test func searchProvidesOneUnfilteredFeedPerContentType() {
        let search = DiscoveryCatalogs.search
        #expect(search.map(\.catalog.type) == ["movie", "series"])
        #expect(search.allSatisfy { $0.catalog.supportsSearch && $0.defaultGenre == nil })
        #expect(Set(search.map(\.id)).count == 2)
    }

    @Test func builtinMetadataWorksWithoutInstalledAddons() {
        let addons: [InstalledAddon] = []
        #expect(addons.metaClient(type: "movie", id: "tt0111161")?.manifestURL == AddonStore.cinemetaURL)
        #expect(addons.metaClient(type: "series", id: "tt0903747")?.manifestURL == AddonStore.cinemetaURL)
        #expect(addons.metaClient(type: "movie", id: "kitsu:1") == nil)
        #expect(addons.metaClient(type: "channel", id: "tt1") == nil)
    }

    @Test func installedMetadataKeepsUserPriority() throws {
        let manifest = try decodeFixture("cinemeta-manifest", as: AddonManifest.self)
        let custom = InstalledAddon(manifestURL: "https://custom.example/manifest.json", manifest: manifest)
        #expect([custom].metaClient(type: "movie", id: "tt0111161")?.manifestURL == custom.manifestURL)
    }
}
