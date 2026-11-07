import Foundation
import Synchronization
import Testing
@testable import LogeCore

struct FestivalFilmMatchingTests {
    private func client() -> FilmCollectionClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FestivalFilmProtocol.self]
        return FilmCollectionClient(session: URLSession(configuration: configuration))
    }

    @Test func uniqueRecentFilmIgnoresOldHomonymsSeriesAndDuplicateIDs() async throws {
        let match = try await client().film(named: "Josephine", festivalYear: 2026)
        #expect(match?.id == "tt100")
        #expect(match?.name == "Josephine")
        #expect(match?.releaseInfo == "2026")
    }

    @Test func titleNormalizationAndSearchEncodingPreserveNonASCIIAndSlashes() async throws {
        let match = try await client().film(named: "  Été / Nuit  ", festivalYear: 2026)
        #expect(match?.id == "tt200")
        #expect(match?.name == "ete / nuit")
    }

    @Test(arguments: ["Ambiguous", "Unknown", "Invalid", "Missing"])
    func uncertainMatchesDoNotBecomeAnAutomaticIdentity(_ name: String) async throws {
        #expect(try await client().film(named: name, festivalYear: 2026) == nil)
    }

    @Test func invalidInputDoesNotQueryTheCatalog() async throws {
        let client = client()
        #expect(try await client.film(named: " ", festivalYear: 2026) == nil)
        #expect(try await client.film(named: "Josephine", festivalYear: Int.max) == nil)
    }

    @Test func simultaneousGridAndDetailLookupsShareARequestDespiteCancellation() async throws {
        let client = client()
        let grid = Task { try await client.film(named: "Shared", festivalYear: 2026) }
        defer { FestivalFilmProtocol.releaseSharedResponses() }
        let deadline = ContinuousClock.now + .seconds(2)
        while FestivalFilmProtocol.sharedRequestCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(FestivalFilmProtocol.sharedRequestCount == 1)
        let detail = Task { try await client.film(named: "Shared", festivalYear: 2026) }
        try await Task.sleep(for: .milliseconds(50))
        grid.cancel()
        #expect(FestivalFilmProtocol.sharedRequestCount == 1)
        FestivalFilmProtocol.releaseSharedResponses()
        await #expect(throws: CancellationError.self) { try await grid.value }
        #expect(try await detail.value?.id == "tt600")
        #expect(try await client.film(named: "Shared", festivalYear: 2026)?.id == "tt600")
        #expect(FestivalFilmProtocol.sharedRequestCount == 1)
    }

    @Test func networkAndMalformedResponsesRemainRetryableFailures() async {
        let client = client()
        for name in ["Failure", "Malformed", "Failure"] {
            await #expect(throws: (any Error).self) {
                try await client.film(named: name, festivalYear: 2026)
            }
        }
    }
}

private final class FestivalFilmProtocol: StubURLProtocol, @unchecked Sendable {
    private static let sharedRequests = Mutex(0)
    private static let heldResponses = Mutex<[@Sendable () -> Void]>([])
    static var sharedRequestCount: Int { sharedRequests.withLock { $0 } }
    static func releaseSharedResponses() {
        let responses = heldResponses.withLock { responses in
            let held = responses
            responses = []
            return held
        }
        for response in responses { response() }
    }

    override func startLoading() {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "v3-cinemeta.strem.io",
              components.percentEncodedPath.hasPrefix("/catalog/movie/top/search="),
              components.percentEncodedPath.hasSuffix(".json"),
              let search = String(components.percentEncodedPath.dropFirst("/catalog/movie/top/search=".count)
                .dropLast(".json".count)).removingPercentEncoding else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let body: String
        switch search {
        case "Josephine":
            body = #"""
                {
                  "metas": [
                    {
                      "id": "tt100",
                      "type": "movie",
                      "name": "Josephine",
                      "releaseInfo": "2026"
                    },
                    {
                      "id": "tt100",
                      "type": "movie",
                      "name": "Josephine",
                      "releaseInfo": "2026"
                    },
                    {
                      "id": "tt101",
                      "type": "movie",
                      "name": "Josephine",
                      "releaseInfo": "1990"
                    },
                    {
                      "id": "tt102",
                      "type": "series",
                      "name": "Josephine",
                      "releaseInfo": "2026"
                    },
                    {
                      "id": "tt103",
                      "type": "movie",
                      "name": "Josephine Dreams",
                      "releaseInfo": "2026"
                    }
                  ]
                }
                """#
        case "Été / Nuit":
            guard components.percentEncodedPath.hasSuffix("search=%C3%89t%C3%A9%20%2F%20Nuit.json") else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            body = #"{"metas":[{"id":"tt200","type":"movie","name":"ete / nuit","releaseInfo":"2025-06-01"}]}"#
        case "Ambiguous":
            body = #"{"metas":[{"id":"tt300","type":"movie","name":"Ambiguous","releaseInfo":"2026"},{"id":"tt301","type":"movie","name":"AMBIGUOUS","releaseInfo":"2027"}]}"#
        case "Unknown":
            body = #"{"metas":[{"id":"tt400","type":"movie","name":"Unknown"}]}"#
        case "Invalid":
            body = #"""
                {
                  "metas": [
                    {
                      "id": "nm500",
                      "type": "movie",
                      "name": "Invalid",
                      "releaseInfo": "2026"
                    },
                    {
                      "id": "tt501/path",
                      "type": "movie",
                      "name": "Invalid",
                      "releaseInfo": "2026"
                    },
                    {
                      "id": "tt502",
                      "type": "movie",
                      "name": "Invalid",
                      "releaseInfo": "20260"
                    },
                    {
                      "id": "tt503",
                      "type": "movie",
                      "name": "Invalid",
                      "releaseInfo": "2024"
                    }
                  ]
                }
                """#
        case "Shared": body = #"{"metas":[{"id":"tt600","type":"movie","name":"Shared","releaseInfo":"2026"}]}"#
        case "Missing": body = #"{"metas":[]}"#
        case "Failure": body = #"{"error":"unavailable"}"#
        case "Malformed": body = #"{"error":"unexpected response"}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let respond: @Sendable () -> Void = { [weak self] in
            guard let self,
                  let response = HTTPURLResponse(url: url, statusCode: search == "Failure" ? 503 : 200,
                                                 httpVersion: nil, headerFields: nil) else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(body.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if search == "Shared" {
            Self.heldResponses.withLock { $0.append(respond) }
            Self.sharedRequests.withLock { $0 += 1 }
        } else {
            respond()
        }
    }
}
