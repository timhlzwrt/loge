import Foundation
import Testing
@testable import MediaCore

struct AddonClientTests {
    let client = try! AddonClient(manifestURL: "https://addon.example/config123/manifest.json")

    @Test func derivesBaseURLFromManifestURL() {
        #expect(client.baseURL.absoluteString == "https://addon.example/config123")
    }

    @Test func acceptsStremioInstallLinks() throws {
        let client = try AddonClient(manifestURL: " stremio://addon.example/manifest.json\n")
        #expect(client.baseURL.absoluteString == "https://addon.example")
    }

    @Test(arguments: [
        "addon.example/manifest.json",
        "https://addon.example/",
        "ftp://addon.example/manifest.json",
        "",
    ])
    func rejectsInvalidManifestURLs(_ url: String) {
        #expect(throws: AddonError.self) { try AddonClient(manifestURL: url) }
    }

    @Test func buildsResourceURLs() {
        #expect(client.resourceURL("meta", type: "movie", id: "tt0111161").absoluteString
            == "https://addon.example/config123/meta/movie/tt0111161.json")
        #expect(client.resourceURL("stream", type: "series", id: "tt0903747:1:1").absoluteString
            == "https://addon.example/config123/stream/series/tt0903747%3A1%3A1.json")
    }

    @Test func encodesCatalogExtras() {
        let url = client.resourceURL("catalog", type: "movie", id: "top", extra: [
            (name: "search", value: "the office & co"),
            (name: "skip", value: "100"),
        ])
        #expect(url.absoluteString
            == "https://addon.example/config123/catalog/movie/top/search=the%20office%20%26%20co&skip=100.json")
    }

    @Test func decodesCatalog() throws {
        let response = try decodeFixture("cinemeta-catalog", as: CatalogResponse.self)

        #expect(response.metas.count == 3)
        #expect(response.metas[0].id.hasPrefix("tt"))
        #expect(response.metas[0].poster != nil)
    }

    @Test func decodesSeriesMeta() throws {
        let meta = try decodeFixture("cinemeta-meta-series", as: MetaResponse.self).meta

        #expect(meta.name == "Breaking Bad")
        let pilot = try #require(meta.videos?.first)
        #expect(pilot.id == "tt0903747:1:1")
        #expect(pilot.season == 1 && pilot.episode == 1)
        #expect(pilot.displayTitle == "Pilot")
    }

    @Test func decodesStreams() throws {
        let streams = try decodeFixture("streams", as: StreamsResponse.self).streams

        #expect(streams.count == 2)
        #expect(streams[0].url != nil)
        #expect(streams[0].behaviorHints?.proxyHeaders?.request?["User-Agent"] == "Example/1.0")
        #expect(streams[1].url == nil && streams[1].infoHash != nil)
    }
}
