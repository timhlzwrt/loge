import Foundation
import Testing
@testable import MediaCore

struct TMDBClientTests {
    private func client(_ scenario: String = "valid") -> TMDBClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TMDBProtocol.self]
        return TMDBClient(readAccessToken: " fixture-\(scenario) \n", session: URLSession(configuration: configuration))
    }

    @Test func validatesUsingBearerHeaderWithoutPuttingTokenInURL() async throws {
        // The protocol rejects missing headers, a leaked token, the wrong language, or a long timeout.
        try await client().validate()
    }

    @Test func movieLookupUsesIMDbIdentityAndMergesPeopleByNumericID() async throws {
        let details = try await client().details(imdbID: "tt0000042", type: "movie")
        #expect(details.overview == "English overview")
        #expect(details.posterURL == "https://image.tmdb.org/t/p/w500/poster.jpg")
        #expect(details.backgroundURL == "https://image.tmdb.org/t/p/w1280/backdrop.jpg")
        #expect(details.releaseInfo == "2024")
        #expect(details.runtime == "169 min")
        #expect(details.genres == ["Drama"])
        #expect(details.people.map(\.id) == [1, 2, 3])
        #expect(details.people[0].name == "Alex")
        #expect(details.people[0].roles == [.actor, .director, .writer])
        #expect(details.people[0].character == "The lead")
        #expect(details.people[0].profileURL == "https://image.tmdb.org/t/p/w185/alex.jpg")
        // Distinct people with the same name must stay distinct.
        #expect(details.people[1].name == "Alex")
        #expect(details.people[1].roles == [.actor])
        #expect(details.people[1].character == nil)
        #expect(details.people[2].roles == [.writer])
    }

    @Test func seriesUsesTVMatchAndHandlesNullSparseMetadata() async throws {
        let details = try await client().details(imdbID: "tt0000084", type: "series")
        #expect(details.overview == nil)
        #expect(details.posterURL == nil)
        #expect(details.backgroundURL == nil)
        #expect(details.releaseInfo == "2021")
        #expect(details.runtime == "45 min")
        #expect(details.genres == nil)
        #expect(details.people.isEmpty)
    }

    @Test func unknownTitleOrEpisodeCannotBecomeAnUnrelatedMovie() async {
        await #expect(throws: TMDBError.notFound) {
            try await client("episode").details(imdbID: "tt0000042", type: "movie")
        }
        await #expect(throws: TMDBError.notFound) {
            try await client("empty").details(imdbID: "tt0000042", type: "series")
        }
        await #expect(throws: TMDBError.notFound) {
            try await client().details(imdbID: "tt42/path", type: "movie")
        }
        await #expect(throws: TMDBError.notFound) {
            try await client().details(imdbID: "tt0000042", type: "channel")
        }
    }

    @Test(arguments: [
        ("401", TMDBError.unauthorized), ("403", .unauthorized), ("429", .rateLimited),
        ("404", .notFound), ("503", .unavailable), ("network", .unavailable),
        ("malformed", .invalidResponse), ("missing", .invalidResponse), ("false", .unauthorized),
    ])
    func failuresHaveSafeTypedErrors(_ scenario: String, _ expected: TMDBError) async {
        await #expect(throws: expected) { try await client(scenario).validate() }
    }

    @Test func invalidDetailsCannotBePresentedAsSuccessfulEnrichment() async {
        await #expect(throws: TMDBError.invalidResponse) {
            try await client("wrongID").details(imdbID: "tt0000042", type: "movie")
        }
        await #expect(throws: TMDBError.invalidResponse) {
            try await client("missingDetails").details(imdbID: "tt0000042", type: "movie")
        }
    }

    @Test(arguments: [" \n", "fixture-valid\r\nInjected: value", "fixture valid"])
    func blankOrMalformedTokenIsRejectedBeforeMakingARequest(_ token: String) async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TMDBProtocol.self]
        let session = URLSession(configuration: configuration)
        await #expect(throws: TMDBError.unauthorized) {
            try await TMDBClient(readAccessToken: token, session: session).validate()
        }
    }

    @Test func transportCancellationRemainsCancellation() async throws {
        do {
            try await client("cancelled").validate()
            Issue.record("Cancelled request returned success")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        let task = Task { try await client().details(imdbID: "tt0000042", type: "movie") }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled lookup returned details")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }
}

private final class TMDBProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let authorization = request.value(forHTTPHeaderField: "Authorization"),
              authorization.hasPrefix("Bearer fixture-"),
              !url.absoluteString.contains("fixture-"), components.host == "api.themoviedb.org",
              components.queryItems?.contains(.init(name: "language", value: "en-US")) == true,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.timeoutInterval == 15 else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let scenario = String(authorization.dropFirst("Bearer fixture-".count))
        if scenario == "network" || scenario == "cancelled" {
            client?.urlProtocol(self, didFailWithError: URLError(scenario == "network" ? .notConnectedToInternet : .cancelled))
            return
        }
        let status = Int(scenario) ?? 200
        let body: String
        switch components.path {
        case "/3/authentication":
            switch scenario {
            case "malformed": body = "invalid JSON"
            case "missing": body = "{}"
            case "false": body = #"{"success":false}"#
            default: body = #"{"success":true}"#
            }
        case "/3/find/tt0000042", "/3/find/tt0000084":
            guard components.queryItems?.contains(.init(name: "external_source", value: "imdb_id")) == true else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            switch scenario {
            case "episode": body = #"{"movie_results":[],"tv_results":[],"tv_episode_results":[{"id":999}]}"#
            case "empty": body = #"{"movie_results":null}"#
            default: body = #"{"movie_results":[{"id":42}],"tv_results":[{"id":84}]}"#
            }
        case "/3/movie/42", "/3/tv/84":
            guard components.queryItems?.contains(.init(name: "append_to_response", value: "credits")) == true else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            if scenario == "wrongID" {
                body = #"{"id":99}"#
            } else if scenario == "missingDetails" {
                body = "{}"
            } else {
                body = components.path == "/3/movie/42" ? Self.movie : Self.series
            }
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static let movie = #"""
    {"id":42,"overview":"  English overview \n","poster_path":"/poster.jpg","backdrop_path":"/backdrop.jpg",
     "release_date":"2024-03-01","runtime":169,"genres":[{"name":"Drama"},{"name":" "},{"name":null}],
     "credits":{"cast":[
        {"id":1,"name":"Alex","character":"The lead","profile_path":null},
        {"id":2,"name":"Alex","character":" ","profile_path":"https://other.example/image.jpg"},
        {"id":1,"name":"Alex","character":"The lead"},
        {"id":null,"name":"Missing ID"},{"id":9,"name":" "}],
       "crew":[
        {"id":1,"name":"Alex","job":"Director","department":"Directing","profile_path":"/alex.jpg"},
        {"id":1,"name":"Alex","job":"Screenplay","department":"Writing"},
        {"id":3,"name":"Sam","job":"Story","department":null},
        {"id":4,"name":"Assistant","job":"First Assistant Director","department":"Directing"},
        {"id":5,"name":"Editor","job":"Editor","department":"Editing"}]}}
    """#

    private static let series = #"""
    {"id":84,"overview":" ","poster_path":null,"backdrop_path":"//untrusted.example/image.jpg",
     "first_air_date":"2021-01-08","runtime":999,"episode_run_time":[0,45],"genres":[],"credits":null}
    """#
}
