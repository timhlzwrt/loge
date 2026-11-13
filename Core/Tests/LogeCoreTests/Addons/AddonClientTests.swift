import Foundation
import Testing
@testable import LogeCore

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

    @Test func preservesEncodedConfigurationPaths() throws {
        let manifestURL = "https://addon.example/config%2Fpart%3Fvalue%25/manifest.json"
        let client = try AddonClient(manifestURL: manifestURL)

        #expect(client.manifestURL == manifestURL)
        #expect(client.resourceURL("meta", type: "movie", id: "tt0111161").absoluteString
            == "https://addon.example/config%2Fpart%3Fvalue%25/meta/movie/tt0111161.json")
    }

    @Test func keepsQueryAndFragmentAfterResourcePaths() throws {
        let manifestURL = "https://addon.example/config/manifest.json?token=example%2Fvalue#install"
        let client = try AddonClient(manifestURL: manifestURL)

        #expect(client.manifestURL == manifestURL)
        #expect(client.resourceURL("stream", type: "series", id: "tt0903747:1:1").absoluteString
            == "https://addon.example/config/stream/series/tt0903747%3A1%3A1.json?token=example%2Fvalue#install")
    }

    @Test func passesTheFilenameToSubtitleAddons() {
        let url = client.resourceURL("subtitles", type: "movie", id: "tt0111161", extra: [
            (name: "filename", value: "Example.Movie.2024.1080p.mkv"),
        ])
        #expect(url.absoluteString
            == "https://addon.example/config123/subtitles/movie/tt0111161/filename=Example.Movie.2024.1080p.mkv.json")
    }

    @Test func decodesSubtitles() throws {
        let subtitles = try decodeFixture("subtitles", as: SubtitlesResponse.self).subtitles

        #expect(subtitles.map(\.lang) == ["eng", "ger", "pob"])
        #expect(subtitles[0].url == "https://subs.example/1001.srt")
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

    @Test func readsTheTrailerAndToleratesOtherShapes() throws {
        let meta = try decodeFixture("cinemeta-meta-series", as: MetaResponse.self).meta
        #expect(meta.trailers?.youTubeID == "VFkjBy2b50Q")

        func trailer(_ trailers: String) throws -> String? {
            let json = #"{"meta":{"id":"tt1","type":"movie","name":"Movie","trailers":\#(trailers)}}"#
            return try JSONDecoder().decode(MetaResponse.self, from: Data(json.utf8)).meta.trailers?.youTubeID
        }
        #expect(try trailer(#"[{"source":"clip0000001","type":"Clip"},{"source":"trailer0001","type":"Trailer"}]"#) == "trailer0001")
        // Not a video ID, so it can't be put into a link.
        #expect(try trailer(#"[{"source":"x&list=evil","type":"Trailer"}]"#) == nil)
        #expect(try trailer(#"["trailer0001"]"#) == nil)
        #expect(try trailer(#"{"source":"trailer0001"}"#) == nil)
    }

    @Test(arguments: [("45 min", 45.0), ("2h 16min", 136.0), ("1h", 60.0), ("unknown", nil), (nil, nil)] as [(String?, Double?)])
    func readsRuntimes(_ runtime: String?, _ minutes: Double?) {
        #expect(Meta.minutes(inRuntime: runtime) == minutes)
    }

    @Test func decodesStreams() throws {
        let streams = try decodeFixture("streams", as: StreamsResponse.self).streams

        #expect(streams.count == 2)
        #expect(streams[0].url != nil)
        #expect(streams[0].behaviorHints?.proxyHeaders?.request?["User-Agent"] == "Example/1.0")
        #expect(streams[1].url == nil && streams[1].playbackURL == nil)
        #expect(streams[0].subtitles == [Subtitle(id: "s1", url: "https://debrid.example/subs/en.srt", lang: "eng")])
        #expect(streams[1].subtitles == nil)
    }

    @Test func cleansPaddedStreamNames() throws {
        // As sent by AIOStreams: leading spaces, zero-width joiners and trailing padding.
        let json = #"{"name": "   4K \u200d\u200d    \u200d\u200d\u200d⚡\u200d\u200d\n  〈Remux〉\u200d     \u200d\n  ★★★★★            "}"#
        let stream = try JSONDecoder().decode(StreamSource.self, from: Data(json.utf8))
        #expect(stream.cleanName == "4K ⚡\n〈Remux〉\n★★★★★")

        let blank = try JSONDecoder().decode(StreamSource.self, from: Data(#"{"name": " \u200d \n "}"#.utf8))
        #expect(blank.cleanName == nil)
    }

    @Test func onlyHTTPStreamsArePlayable() throws {
        let streams = try decodeFixture("streams", as: StreamsResponse.self).streams
        #expect(streams[0].playbackURL?.host() == "debrid.example")
        #expect(streams[0].requestHeaders == ["User-Agent": "Example/1.0"])
        #expect(streams[1].playbackURL == nil)

        var external = streams[0]
        external.url = "magnet:?xt=urn:btih:0123"
        #expect(external.playbackURL == nil)
    }

    @Test func rejectsTorrentDescriptorsEvenWithDirectLinks() throws {
        for descriptor in [#""infoHash":"0123""#, #""fileIdx":0"#] {
            let json = "{\"url\":\"https://example.com/video.mkv\",\(descriptor)}"
            let source = try JSONDecoder().decode(StreamSource.self, from: Data(json.utf8))
            #expect(source.playbackURL == nil)
        }
    }

    @Test func rejectsNonMediaPlaybackURLs() throws {
        for string in ["magnet:?xt=urn:btih:0123", "file:///tmp/video.mp4", "https:///video.mp4",
                       "https://example.com/movie.TORRENT?download=1", "ftp://example.com/video.mkv"] {
            let url = try #require(URL(string: string))
            #expect(!StreamSource.isDirectPlaybackURL(url))
        }
        #expect(StreamSource.isDirectPlaybackURL(URL(string: "https://example.com/video.mkv")!))
    }

    @Test func mapsTransportAndDecodingFailuresToAddonErrors() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AddonFailureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let offline = try AddonClient(manifestURL: "https://offline.example/manifest.json", session: session)
        await #expect(throws: AddonError.unavailable(.notConnectedToInternet)) { try await offline.manifest() }
        let garbage = try AddonClient(manifestURL: "https://garbage.example/manifest.json", session: session)
        await #expect(throws: AddonError.invalidResponse) { try await garbage.streams(type: "movie", id: "tt1") }
    }
}

private final class AddonFailureProtocol: StubURLProtocol, @unchecked Sendable {
    override func startLoading() {
        guard let url = request.url else { return }
        if url.host() == "offline.example" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        respond(200, body: Data("<html>".utf8))
    }
}
