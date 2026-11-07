import Foundation
import Testing
@testable import LogeCore

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

    @Test func recommendationsKeepTMDBOrderAndTheirOwnKind() async throws {
        let movie = try await client().details(imdbID: "tt0000042", type: "movie")
        #expect(movie.tmdbID == 42)
        // The title itself, repeats and entries without an ID or name are dropped.
        #expect(movie.recommendations.map(\.id) == ["movie:51", "movie:53"])
        let first = try #require(movie.recommendations.first)
        #expect(first.name == "First pick")
        #expect(first.posterURL == "https://image.tmdb.org/t/p/w500/first.jpg")
        #expect(first.backgroundURL == "https://image.tmdb.org/t/p/w1280/first-backdrop.jpg")
        #expect(first.overview == "Its overview")
        #expect(first.releaseDate == "2019-06-01")
        #expect(first.roles.isEmpty)
        #expect(movie.recommendations[1].releaseDate == nil)

        let series = try await client().details(imdbID: "tt0000084", type: "series")
        #expect(series.recommendations.map(\.id) == ["series:71"])
        #expect(series.recommendations.first?.name == "Next show")
        #expect(series.recommendations.first?.releaseDate == "2020-02-02")
    }

    @Test func similarTitlesStandInOnlyWhenThereAreNoRecommendations() async throws {
        let details = try await client("onlySimilar").details(imdbID: "tt0000042", type: "movie")
        #expect(details.recommendations.map(\.name) == ["Similar"])
        let sparse = try await client("unrated").details(imdbID: "tt0000042", type: "movie")
        #expect(sparse.recommendations.isEmpty)
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

    @Test func richerMovieAndSeriesFieldsKeepTheirProviderMeaning() async throws {
        let movie = try await client().details(imdbID: "tt0000042", type: "movie")
        #expect(movie.tagline == "A real tagline")
        #expect(movie.originalTitle == "Original title")
        #expect(movie.status == "Released")
        #expect(movie.originalLanguage == "fr")
        #expect(movie.countries == ["France", "Germany"])
        #expect(movie.studios == ["Studio A"])
        #expect(movie.releaseDate == "2024-03-01")
        #expect(movie.lastAirDate == nil)
        #expect(movie.seasonCount == nil)
        #expect(movie.episodeCount == nil)
        #expect(movie.rating == 7.4)
        #expect(movie.voteCount == 180)
        #expect(movie.budget == 12_000_000)
        #expect(movie.revenue == 25_000_000)

        let series = try await client().details(imdbID: "tt0000084", type: "series")
        #expect(series.originalTitle == "Original series name")
        #expect(series.status == "Ended")
        #expect(series.originalLanguage == "es")
        #expect(series.countries == ["Spain"])
        #expect(series.releaseDate == "2021-01-08")
        #expect(series.lastAirDate == "2023-12-31")
        #expect(series.seasonCount == 3)
        #expect(series.episodeCount == 24)
        #expect(series.budget == nil)
        #expect(series.revenue == nil)
    }

    @Test func missingOrUnratedDetailsDoNotInventMoneyOrScores() async throws {
        let details = try await client("unrated").details(imdbID: "tt0000042", type: "movie")
        #expect(details.rating == nil)
        #expect(details.voteCount == 0)
        #expect(details.budget == nil)
        #expect(details.revenue == nil)
        let oldInitializer = TMDBDetails(overview: "Existing call site")
        #expect(oldInitializer.tagline == nil)
        #expect(oldInitializer.countries == nil)
        #expect(oldInitializer.voteCount == nil)
    }

    @Test func completePersonCreditsMergeEveryJobWithoutCollidingMediaIDs() async throws {
        let person = try await client().person(id: 5)
        #expect(person.id == 5)
        #expect(person.name == "A Person")
        #expect(person.biography == "Full biography")
        #expect(person.knownFor == "Directing")
        #expect(person.portraitURL == "https://image.tmdb.org/t/p/w500/person.jpg")
        #expect(person.birthday == "1960-05-01")
        #expect(person.placeOfBirth == "Paris")
        #expect(person.titles.count == 53)
        #expect(person.titles.prefix(2).map(\.id) == ["movie:7", "series:7"])
        #expect(person.titles.suffix(2).allSatisfy { $0.releaseDate == nil })
        let movie = try #require(person.titles.first { $0.id == "movie:7" })
        #expect(movie.creditRoles == [.acting, .directing, .otherCrew])
        #expect(movie.roles == ["Actor · Alex", "Actor · Other role", "Director", "Producer", "Editor", "Composer"])
        #expect(movie.posterURL == "https://image.tmdb.org/t/p/w500/newest.jpg")
        #expect(movie.backgroundURL == "https://image.tmdb.org/t/p/w1280/newest-background.jpg")
        #expect(movie.overview == "Crew record fills a missing overview")
        let series = try #require(person.titles.first { $0.id == "series:7" })
        #expect(series.creditRoles == [.acting, .otherCrew])
        #expect(person.titles.first { $0.id == "movie:8" }?.creditRoles == [.acting])
        #expect(person.titles.first { $0.id == "series:13" }?.creditRoles == [.otherCrew])
        #expect(person.titles.first { $0.id == "movie:15" }?.creditRoles == [.otherCrew])
        #expect(series.name == "Series twin")
        #expect(series.roles == ["Actor · Self", "Executive Producer"])
        #expect(person.titles.contains { $0.id == "series:13" && $0.roles == ["Director of Photography"] })
        #expect(person.titles.contains { $0.id == "series:14" && $0.roles == ["Camera"] })
        #expect(person.titles.contains { $0.id == "movie:15" && $0.roles == ["Crew"] })
        #expect(person.titles.first { $0.id == "movie:10" }?.name == "Original name")
    }

    @Test func personMissingOptionalFieldsStillReturnsAnHonestEmptyFilmography() async throws {
        let person = try await client("personSparse").person(id: 5)
        #expect(person.name == "Solo")
        #expect(person.biography == nil)
        #expect(person.portraitURL == nil)
        #expect(person.knownFor == nil)
        #expect(person.birthday == nil)
        #expect(person.placeOfBirth == nil)
        #expect(person.titles.isEmpty)
        for scenario in ["personWrongID", "personMissingName", "personMalformed"] {
            await #expect(throws: TMDBError.invalidResponse) { try await client(scenario).person(id: 5) }
        }
    }

    @Test(arguments: ["personNoCredits", "personNullCredits", "personAppendError", "personAppendFalse",
                      "personMissingCast", "personMissingCrew", "personNullCast", "personNullCrew"])
    func missingOrFailedCombinedCreditsAreRetryableErrors(_ scenario: String) async {
        await #expect(throws: TMDBError.invalidResponse) { try await client(scenario).person(id: 5) }
    }

    @Test func externalIMDbResolutionUsesTheMatchingMovieOrSeriesNamespace() async throws {
        #expect(try await client().imdbID(tmdbID: 7, type: "movie") == "tt0000777")
        #expect(try await client().imdbID(tmdbID: 7, type: "series") == "tt0000888")
        for scenario in ["externalMissing", "externalAbsent", "externalEmpty"] {
            #expect(try await client(scenario).imdbID(tmdbID: 7, type: "movie") == nil)
        }
        for scenario in ["externalWrongID", "externalInvalid", "externalEpisode", "externalPath",
                         "externalNoIdentity", "externalNullIdentity", "externalError", "externalFalse"] {
            await #expect(throws: TMDBError.invalidResponse) {
                try await client(scenario).imdbID(tmdbID: 7, type: "movie")
            }
        }
        for id in [0, -1] {
            await #expect(throws: TMDBError.notFound) { try await client().person(id: id) }
            await #expect(throws: TMDBError.notFound) { try await client().imdbID(tmdbID: id, type: "movie") }
        }
        await #expect(throws: TMDBError.notFound) { try await client().imdbID(tmdbID: 7, type: "episode") }
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

private final class TMDBProtocol: StubURLProtocol, @unchecked Sendable {

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
            guard components.queryItems?.contains(.init(name: "append_to_response", value: "credits,recommendations,similar")) == true else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            if scenario == "wrongID" {
                body = #"{"id":99}"#
            } else if scenario == "missingDetails" {
                body = "{}"
            } else if scenario == "onlySimilar" {
                body = #"{"id":42,"recommendations":{"results":[]},"similar":{"results":[{"id":61,"title":"Similar"}]}}"#
            } else if scenario == "unrated" {
                body = #"{"id":42,"vote_average":0,"vote_count":0,"budget":0,"revenue":-1}"#
            } else {
                body = components.path == "/3/movie/42" ? Self.movie : Self.series
            }
        case "/3/person/5":
            guard components.queryItems?.contains(.init(name: "append_to_response", value: "combined_credits")) == true else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            switch scenario {
            case "personSparse": body = #"{"id":5,"name":"Solo","biography":null,"combined_credits":{"cast":[],"crew":[]}}"#
            case "personWrongID": body = #"{"id":99,"name":"Other person","combined_credits":{"cast":[],"crew":[]}}"#
            case "personMissingName": body = #"{"id":5,"name":" ","combined_credits":{"cast":[],"crew":[]}}"#
            case "personNoCredits": body = #"{"id":5,"name":"Solo"}"#
            case "personNullCredits": body = #"{"id":5,"name":"Solo","combined_credits":null}"#
            case "personAppendError": body = #"{"id":5,"name":"Solo","combined_credits":{"success":false,"status_code":11}}"#
            case "personAppendFalse": body = #"{"id":5,"name":"Solo","combined_credits":{"cast":[],"crew":[],"success":false}}"#
            case "personMissingCast": body = #"{"id":5,"name":"Solo","combined_credits":{"crew":[]}}"#
            case "personMissingCrew": body = #"{"id":5,"name":"Solo","combined_credits":{"cast":[]}}"#
            case "personNullCast": body = #"{"id":5,"name":"Solo","combined_credits":{"cast":null,"crew":[]}}"#
            case "personNullCrew": body = #"{"id":5,"name":"Solo","combined_credits":{"cast":[],"crew":null}}"#
            case "personMalformed": body = "invalid JSON"
            default: body = Self.person
            }
        case "/3/movie/7/external_ids", "/3/tv/7/external_ids":
            switch scenario {
            case "externalMissing": body = #"{"id":7,"imdb_id":null}"#
            case "externalAbsent": body = #"{"id":7}"#
            case "externalEmpty": body = #"{"id":7,"imdb_id":""}"#
            case "externalNoIdentity": body = #"{"imdb_id":"tt0000777"}"#
            case "externalNullIdentity": body = #"{"id":null,"imdb_id":"tt0000777"}"#
            case "externalError": body = #"{"success":false,"status_code":11}"#
            case "externalFalse": body = #"{"id":7,"imdb_id":null,"success":false}"#
            case "externalInvalid": body = #"{"id":7,"imdb_id":"nm0000777"}"#
            case "externalEpisode": body = #"{"id":7,"imdb_id":"tt0000777:1:2"}"#
            case "externalPath": body = #"{"id":7,"imdb_id":"tt0000777/path"}"#
            case "externalWrongID": body = #"{"id":99,"imdb_id":"tt0000777"}"#
            default: body = components.path.contains("/movie/")
                ? #"{"id":7,"imdb_id":"tt0000777"}"# : #"{"id":7,"imdb_id":"tt0000888"}"#
            }
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        respond(status, body: Data(body.utf8))
    }

    private static let movie = #"""
    {"id":42,"overview":"  English overview \n","poster_path":"/poster.jpg","backdrop_path":"/backdrop.jpg",
     "tagline":"  A real tagline  ","original_title":"Original title","status":"Released","original_language":"fr",
     "production_countries":[{"name":"France"},{"name":"France"},{"name":null,"iso_3166_1":"DE"}],
     "production_companies":[{"name":"Studio A"},{"name":"Studio A"},{"name":" "}],
     "vote_average":7.4,"vote_count":180,"budget":12000000,"revenue":25000000,
     "last_air_date":"2025-01-01","number_of_seasons":9,"number_of_episodes":99,
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
        {"id":5,"name":"Editor","job":"Editor","department":"Editing"}]},
     "recommendations":{"results":[
        {"id":51,"title":"  First pick ","poster_path":"/first.jpg","backdrop_path":"/first-backdrop.jpg",
         "overview":"Its overview","release_date":"2019-06-01","name":"TV-style name"},
        {"id":42,"title":"The title itself"},{"id":51,"title":"Duplicate"},
        {"id":null,"title":"Missing ID"},{"id":52,"title":" "},{"id":53,"title":"Sparse","release_date":""}]},
     "similar":{"results":[{"id":61,"title":"Only used without recommendations"}]}}
    """#

    private static let series = #"""
    {"id":84,"overview":" ","poster_path":null,"backdrop_path":"//untrusted.example/image.jpg",
     "original_name":"Original series name","status":"Ended","original_language":"es","origin_country":["ES"],
     "last_air_date":"2023-12-31","number_of_seasons":3,"number_of_episodes":24,"budget":10,"revenue":20,
     "first_air_date":"2021-01-08","runtime":999,"episode_run_time":[0,45],"genres":[],"credits":null,
     "recommendations":{"results":[{"id":71,"name":"Next show","title":"Movie-style title","first_air_date":"2020-02-02"}]}}
    """#

    private static var person: String {
        let archive = (100..<145).map {
            #"{"id":\#($0),"media_type":"movie","title":"Archive \#($0)","release_date":"1990-01-01","character":"Self"}"#
        }.joined(separator: ",")
        return #"""
        {"id":5,"name":" A Person ","biography":" Full biography ","profile_path":"/person.jpg",
         "known_for_department":"Directing","birthday":"1960-05-01","place_of_birth":" Paris ",
         "combined_credits":{"cast":[
           {"id":7,"media_type":"movie","title":"Newest","release_date":"2026-05-01","character":"Alex"},
           {"id":7,"media_type":"tv","name":"Series twin","first_air_date":"2025-01-02","character":"Self"},
           {"id":7,"media_type":"movie","title":"Newest","character":"Other role"},
           {"id":7,"media_type":"movie","title":"Newest","character":"Alex"},
           {"id":8,"media_type":"movie","title":"Undated","release_date":""},
           {"id":9,"media_type":"movie","title":"Invalid date","release_date":"unknown"},
           {"id":10,"media_type":"movie","title":" ","original_title":"Original name","release_date":"2024-01-01"},
           {"id":0,"media_type":"movie","title":"Invalid ID"},
           {"id":-1,"media_type":"tv","name":"Negative ID"},
           {"media_type":"movie","title":"Missing ID"},
           {"id":11,"media_type":"movie","title":null},
           {"id":12,"media_type":"person","name":"Not a title"},
           \#(archive)],
           "crew":[
           {"id":7,"media_type":"movie","title":"Newest","job":"Director","poster_path":"/newest.jpg",
            "backdrop_path":"/newest-background.jpg","overview":"Crew record fills a missing overview"},
           {"id":7,"media_type":"movie","title":"Newest","job":"Producer"},
           {"id":7,"media_type":"movie","title":"Newest","job":"Editor"},
           {"id":7,"media_type":"movie","title":"Newest","job":"Composer"},
           {"id":7,"media_type":"movie","title":"Newest","job":"Director"},
           {"id":7,"media_type":"tv","name":"Series twin","job":"Executive Producer"},
           {"id":13,"media_type":"tv","name":"Crew only","first_air_date":"2023-01-01","job":"Director of Photography"},
           {"id":14,"media_type":"tv","name":"No job","first_air_date":"2022-01-01","department":"Camera"},
           {"id":15,"media_type":"movie","title":"Unspecified crew","release_date":"2020-01-01","job":null}]}}
        """#
    }

}
