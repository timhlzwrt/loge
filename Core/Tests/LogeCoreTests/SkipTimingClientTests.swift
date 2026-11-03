import Foundation
import Testing
@testable import LogeCore

struct SkipTimingClientTests {
    private let movie = WatchItem(id: "tt0000001", type: "movie", metaID: "tt0000001", title: "Fixture")

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SkipTimingProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func buildsOnlyValidatedMovieAndEpisodeRequests() throws {
        let url = try #require(SkipTimingClient.requestURL(for: movie, duration: 1_000))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "api.theintrodb.org")
        #expect(components.path == "/v4/media")
        #expect(components.queryItems?.contains(.init(name: "duration_ms", value: "1000000")) == true)
        #expect(components.queryItems?.contains(.init(name: "details", value: "true")) == true)
        #expect(components.queryItems?.contains(where: { $0.name == "season" }) == false)
        let episode = WatchItem(id: "tt0903747:1:2", type: "series", metaID: "tt0903747", title: "Fixture", season: 1, episode: 2)
        let episodeURL = try #require(SkipTimingClient.requestURL(for: episode, duration: 1_000))
        #expect(episodeURL.query()?.contains("season=1&episode=2") == true)
        var invalid = movie
        invalid.metaID = "addon:1234"
        #expect(SkipTimingClient.requestURL(for: invalid, duration: 1_000) == nil)
        invalid = movie
        invalid.type = "series"
        #expect(SkipTimingClient.requestURL(for: invalid, duration: 1_000) == nil)
        #expect(SkipTimingClient.requestURL(for: movie, duration: .infinity) == nil)
        #expect(SkipTimingClient.requestURL(for: movie, duration: 0) == nil)
    }

    @Test func decodesAllSegmentsWithDocumentedNullBoundaries() async throws {
        let segments = try await SkipTimingClient(session: session()).segments(for: movie, duration: 1_000)
        #expect(segments == [
            PlaybackSegment(kind: .recap, start: 0, end: 20),
            PlaybackSegment(kind: .intro, start: 40, end: 70),
            PlaybackSegment(kind: .credits, start: 950, end: 1_000),
        ])
        #expect(segments[0].skip(at: 0, duration: 1_000)?.end == 20)
        #expect(segments[0].skip(at: 20, duration: 1_000) == nil)
        #expect(segments[1].skip(at: 30, duration: 1_000) == nil)
        #expect(segments[2].skip(at: 960, duration: 900) == nil)
    }

    @Test func ignoresSparseMalformedOrOutOfRuntimeSegments() throws {
        let data = Data(#"""
        {"group_duration_ms":1000000,
         "intro":[
            {"start_ms":-1,"end_ms":30000,"confidence":1,"submission_count":9},
            {"start_ms":40000,"end_ms":30000,"confidence":1,"submission_count":9},
            {"start_ms":0,"end_ms":0,"confidence":1,"submission_count":9},
            {"start_ms":0,"end_ms":null,"confidence":1,"submission_count":9},
            {"start_ms":0,"end_ms":30000,"confidence":0.49,"submission_count":9},
            {"start_ms":0,"end_ms":30000,"confidence":1.01,"submission_count":9},
            {"start_ms":0,"end_ms":30000,"confidence":1,"submission_count":2}],
         "recap":[{"start_ms":0,"end_ms":30000}],
         "credits":[{"start_ms":950000,"end_ms":1000001,"confidence":1,"submission_count":9}]}
        """#.utf8)
        #expect(try SkipTimingClient.decode(data, duration: 1_000).isEmpty)
    }

    @Test func rejectsUnknownOrDifferentReleaseDurations() throws {
        let valid = try #require(SkipTimingProtocol.valid.data(using: .utf8))
        #expect(try SkipTimingClient.decode(valid, duration: 1_002).count == 3)
        #expect(try SkipTimingClient.decode(valid, duration: 1_003).isEmpty)
        let unknown = Data(#"{"intro":[{"start_ms":0,"end_ms":30000,"confidence":1,"submission_count":9}]}"#.utf8)
        #expect(try SkipTimingClient.decode(unknown, duration: 1_000).isEmpty)
        let invalidDuration = Data(#"{"group_duration_ms":0,"intro":[{"start_ms":0,"end_ms":500,"confidence":1,"submission_count":9}]}"#.utf8)
        #expect(try SkipTimingClient.decode(invalidDuration, duration: 1).isEmpty)
    }

    @Test func handlesMissingDataAndPropagatesFailures() async throws {
        let client = SkipTimingClient(session: session())
        var item = movie
        item.metaID = "tt0000004"
        #expect(try await client.segments(for: item, duration: 1_000).isEmpty)
        item.metaID = "tt0000005"
        await #expect(throws: SkipTimingError.httpStatus(503)) {
            try await client.segments(for: item, duration: 1_000)
        }
        item.metaID = "tt0000006"
        await #expect(throws: DecodingError.self) {
            try await client.segments(for: item, duration: 1_000)
        }
    }

    @Test func cancelledLookupCannotReturnTimings() async {
        let client = SkipTimingClient(session: session())
        let task = Task { try await client.segments(for: movie, duration: 1_000) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled lookup returned timings")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }
}

private final class SkipTimingProtocol: URLProtocol, @unchecked Sendable {
    static let valid = #"""
    {"group_duration_ms":1000000,
     "intro":[{"start_ms":40000,"end_ms":70000,"confidence":0.9,"submission_count":8}],
     "recap":[{"start_ms":null,"end_ms":20000,"confidence":0.5,"submission_count":3}],
     "credits":[{"start_ms":950000,"end_ms":null,"confidence":1,"submission_count":5}]}
    """#

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "imdb_id" }?.value
        let status = id == "tt0000004" ? 404 : (id == "tt0000005" ? 503 : 200)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((id == "tt0000006" ? "invalid JSON" : Self.valid).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
