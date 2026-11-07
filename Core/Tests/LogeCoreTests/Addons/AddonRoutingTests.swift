import Foundation
import Testing
@testable import LogeCore

struct AddonRoutingTests {
    let cinemeta = InstalledAddon(
        manifestURL: AddonStore.cinemetaURL,
        manifest: try! decodeFixture("cinemeta-manifest", as: AddonManifest.self)
    )
    let streams = InstalledAddon(
        manifestURL: "https://streams.example/manifest.json",
        manifest: try! decodeFixture("stream-addon-manifest", as: AddonManifest.self)
    )
    let subtitles = InstalledAddon(
        manifestURL: "https://subtitles.example/manifest.json",
        manifest: try! decodeFixture("subtitle-addon-manifest", as: AddonManifest.self)
    )
    let notLoaded = InstalledAddon(manifestURL: "https://pending.example/manifest.json", manifest: nil)

    @Test func homeSkipsCatalogsThatNeedInput() {
        let titles = [cinemeta, notLoaded].homeCatalogs.map(\.title)
        // "New" needs a genre and the video catalogs need IDs.
        #expect(titles == ["Popular Movies", "Popular Series", "Featured Movies", "Featured Series"])
    }

    @Test func searchUsesCatalogsThatDeclareSearch() {
        #expect([cinemeta].searchCatalogs.map(\.title) == ["Popular Movies", "Popular Series"])
    }

    @Test func legacyExtraFieldsAreHonoured() throws {
        let json = #"{"type":"movie","id":"x","extraRequired":["genre"],"extraSupported":["search","genre"]}"#
        let catalog = try JSONDecoder().decode(AddonManifest.Catalog.self, from: Data(json.utf8))
        #expect(!catalog.isBrowsable)
        #expect(catalog.supportsSearch)
    }

    @Test func providesRespectsTypesAndPrefixes() throws {
        let manifest = try #require(streams.manifest)
        #expect(manifest.provides("stream", type: "series", id: "kitsu:123"))
        #expect(!manifest.provides("stream", type: "series", id: "tmdb:123"))
        #expect(!manifest.provides("stream", type: "channel", id: "tt123"))
        #expect(!manifest.provides("meta", type: "movie", id: "tt123"))
    }

    @Test func metaComesFromFirstCapableAddonInUserOrder() {
        #expect([streams, cinemeta].metaClient(type: "movie", id: "tt0111161")?.manifestURL == AddonStore.cinemetaURL)
        #expect([streams, cinemeta].metaClient(type: "movie", id: "kitsu:1") == nil)
    }

    @Test func streamProvidersFollowUserOrderAndCapabilities() {
        let providers = [cinemeta, streams, notLoaded].streamProviders(type: "series", id: "tt0903747:1:1")
        #expect(providers.map(\.name) == ["Example Streams"])
        #expect([cinemeta, streams].streamProviders(type: "channel", id: "tt1").isEmpty)
    }

    @Test func subtitleProvidersFollowUserOrderAndCapabilities() {
        let addons = [streams, subtitles, cinemeta, notLoaded]
        #expect(addons.subtitleProviders(type: "movie", id: "tt0111161").map(\.manifestURL)
            == ["https://subtitles.example/manifest.json"])
        #expect(addons.subtitleProviders(type: "movie", id: "kitsu:1").isEmpty)
    }
}
