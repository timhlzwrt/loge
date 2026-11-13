import Foundation
import Synchronization
import Testing
@testable import LogeCore

/// The fixture key picks the scenario: a status code, or the name of a ratings body.
private func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MDBListProtocol.self]
    return URLSession(configuration: configuration)
}

struct MDBListClientTests {
    private func client(_ scenario: String = "valid") -> MDBListClient {
        MDBListClient(apiKey: " fixture-\(scenario) \n", session: session())
    }

    @Test func readsLetterboxdAndTheTomatometerOnTheirOwnScales() async throws {
        let scores = try await client().scores(imdbID: "tt0000042", type: "movie")
        #expect(scores.letterboxd == 4.4)
        #expect(scores.tomatometer == 73)
        #expect(scores.rottenTomatoesURL?.absoluteString == "https://www.rottentomatoes.com/m/fixture_2014")
        // A series is a "show" to MDBList.
        let series = try await client().scores(imdbID: "tt0000084", type: "series")
        #expect(series == TitleScores(tomatometer: 96))
    }

    @Test func leavesOutScoresThatAreMissingOrOffTheirScale() async throws {
        // Letterboxd as a percentage, a Tomatometer above 100 and sources without a value.
        #expect(try await client("offScale").scores(imdbID: "tt0000042", type: "movie") == TitleScores())
        #expect(try await client("noRatings").scores(imdbID: "tt0000042", type: "movie") == TitleScores())
    }

    @Test(arguments: [
        ("/m/fixture_2014", "https://www.rottentomatoes.com/m/fixture_2014"),
        ("/tv/fixture/s01", "https://www.rottentomatoes.com/tv/fixture/s01"),
        ("https://www.rottentomatoes.com/m/fixture", "https://www.rottentomatoes.com/m/fixture"),
        ("https://example.com/m/fixture", nil), ("http://www.rottentomatoes.com/m/fixture", nil),
        ("/m/fixture?next=https://example.com", nil), ("//example.com/m/x", nil), ("fixture_2014", nil),
    ] as [(String, String?)])
    func onlyLinksToRottenTomatoes(_ value: String, _ expected: String?) {
        #expect(MediaResponse.rottenTomatoesURL(value)?.absoluteString == expected)
    }

    @Test func rejectsIDsItCantAskFor() async {
        await #expect(throws: MDBListError.notFound) { try await client().scores(imdbID: "kitsu:1", type: "movie") }
        await #expect(throws: MDBListError.notFound) { try await client().scores(imdbID: "tt0000042", type: "channel") }
    }

    @Test(arguments: [("401", MDBListError.unauthorized), ("403", .unauthorized), ("404", .notFound),
                      ("429", .rateLimited), ("500", .unavailable), ("malformed", .invalidResponse),
                      ("network", .unavailable)])
    func mapsFailures(_ scenario: String, _ expected: MDBListError) async {
        await #expect(throws: expected) { try await client(scenario).scores(imdbID: "tt0000042", type: "movie") }
    }

    @Test func aBlankKeyIsRejectedBeforeMakingARequest() async {
        await #expect(throws: MDBListError.unauthorized) {
            try await MDBListClient(apiKey: " \n", session: session()).validate()
        }
    }
}

@MainActor
struct MDBListAccountTests {
    @MainActor
    private final class Storage {
        var key: String?
        var writes = 0
        init(key: String? = nil) { self.key = key }

        var storage: MDBListAccount.KeyStorage {
            .init(read: { () throws(MDBListAccountError) -> String? in self.key },
                  save: { (key: String) throws(MDBListAccountError) in
                      self.writes += 1
                      self.key = key
                  },
                  remove: { () throws(MDBListAccountError) in self.key = nil })
        }
    }

    @Test func aKeyMDBListRejectsIsntSavedOverTheOldOne() async {
        let storage = Storage(key: "fixture-valid")
        let account = MDBListAccount(session: session(), storage: storage.storage)
        let revision = account.revision
        await #expect(throws: MDBListError.unauthorized) { try await account.connect(apiKey: "fixture-401") }
        await #expect(throws: MDBListAccountError.emptyKey) { try await account.connect(apiKey: "  ") }
        #expect(storage.writes == 0 && storage.key == "fixture-valid")
        #expect(account.isConfigured && account.revision == revision)
    }

    @Test func connectingSavesTheKeyAndATitleIsAskedForOnce() async throws {
        let storage = Storage()
        let account = MDBListAccount(session: session(), storage: storage.storage)
        #expect(!account.isConfigured)
        await #expect(throws: MDBListError.unauthorized) { try await account.scores(imdbID: "tt0000042", type: "movie") }

        try await account.connect(apiKey: " fixture-counted ")
        #expect(storage.key == "fixture-counted" && account.isConfigured)
        let before = MDBListProtocol.count("fixture-counted")
        #expect(try await account.scores(imdbID: "tt0000042", type: "movie").tomatometer == 73)
        #expect(try await account.scores(imdbID: "tt0000042", type: "movie").tomatometer == 73)
        #expect(MDBListProtocol.count("fixture-counted") == before + 1)

        try account.disconnect()
        #expect(storage.key == nil && !account.isConfigured)
        await #expect(throws: MDBListError.unauthorized) { try await account.scores(imdbID: "tt0000042", type: "movie") }
    }
}

private final class MDBListProtocol: StubURLProtocol, @unchecked Sendable {
    private static let requests = Mutex<[String: Int]>([:])

    static func count(_ key: String) -> Int { requests.withLock { $0[key] ?? 0 } }

    override func startLoading() {
        guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "api.mdblist.com", request.timeoutInterval == 15,
              let key = components.queryItems?.first(where: { $0.name == "apikey" })?.value, key.hasPrefix("fixture-") else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        Self.requests.withLock { $0[key, default: 0] += 1 }
        let scenario = String(key.dropFirst("fixture-".count))
        if scenario == "network" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let status = Int(scenario) ?? 200
        let body: String
        switch components.path {
        case "/user":
            body = status == 200 ? #"{"user_id":1,"username":"fixture","api_requests":1000}"# : #"{"error":"Invalid API key!"}"#
        case "/imdb/movie/tt0000042/":
            switch scenario {
            case "malformed": body = "invalid JSON"
            case "noRatings": body = #"{"id":1,"imdb_id":"tt0000042","title":"Fixture"}"#
            case "offScale": body = #"""
                {"ratings":[{"source":"letterboxd","value":88},{"source":"tomatoes","value":140},
                            {"source":"metacritic","value":null},{"source":"popcorn","value":87}]}
                """#
            default: body = status == 200 ? #"""
                {"id":1,"imdb_id":"tt0000042","title":"Fixture","year":2014,"type":"movie","score":86,
                 "ratings":[{"source":"imdb","value":8.7,"score":87,"votes":2100000,"url":"tt0000042"},
                            {"source":"metacritic","value":74,"score":74,"votes":null,"url":17},
                            {"source":"tomatoes","value":73,"score":73,"votes":377,"url":"/m/fixture_2014"},
                            {"source":"popcorn","value":87,"score":87},
                            {"source":"letterboxd","value":4.4,"score":88,"votes":4000000,"url":"/film/fixture/"}]}
                """# : #"{"error":"What went wrong."}"#
            }
        case "/imdb/show/tt0000084/":
            body = #"{"ratings":[{"source":"tomatoes","value":96},{"source":"letterboxd","value":null}]}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        respond(status, body: Data(body.utf8))
    }
}
