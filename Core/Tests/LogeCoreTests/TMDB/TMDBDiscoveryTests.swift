import Foundation
import Testing
@testable import LogeCore

struct TMDBDiscoveryTests {
    private func client(_ scenario: String = "valid") -> TMDBClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryProtocol.self]
        return TMDBClient(readAccessToken: scenario, session: URLSession(configuration: configuration))
    }

    @Test func directorsAreRankedDeduplicatedAndFilteredByDepartment() async throws {
        let result = try await client().popularDirectors()
        #expect(result.map(\.id) == [7, 525, 3, 488, 1032, 138, 608])
        #expect(result.prefix(3).map(\.name) == ["Director Seven", "Director 525", "Director Three"])
        #expect(result.map(\.popularity) == [90, 70, 50, 50, 40, 35, 30])
        #expect(result.first?.portraitURL == "https://image.tmdb.org/t/p/w185/seven.jpg")
        #expect(result.first(where: { $0.id == 3 })?.portraitURL == nil)
    }

    @Test func actorHeavyPopularFeedStillShowsMultipleRankedDirectors() async throws {
        let result = try await client("sparse").popularDirectors()
        #expect(result.map(\.id) == [525, 488, 1032, 138, 608])
        #expect(result.map(\.popularity) == [85, 50, 40, 35, 30])
        #expect(result.first?.portraitURL == "https://image.tmdb.org/t/p/w185/nolan.jpg")
    }

    @Test func emptyPopularFeedStillRanksKnownDirectorsUsingCurrentProviderScores() async throws {
        let result = try await client("emptyPeople").popularDirectors()
        #expect(result.map(\.id) == [525, 488, 1032, 138, 608])
        #expect(result.first?.popularity == 70)
    }

    @Test func removedDirectorDoesNotHideRemainingCandidatesButInvalidIdentityAndAuthenticationFail() async throws {
        let result = try await client("removedSeed").popularDirectors()
        #expect(!result.contains { $0.id == 138 })
        #expect(result.count == 6)
        await #expect(throws: TMDBError.invalidResponse) { try await client("wrongSeedIdentity").popularDirectors() }
        await #expect(throws: TMDBError.unauthorized) { try await client("unauthorizedSeed").popularDirectors() }
    }

    @Test func reviewPagesPreservePlainTextAndValidateLinksAndRatings() async throws {
        for type in ["movie", "series"] {
            let first = try await client().reviews(imdbID: "tt123", type: type)
            #expect(first.page == 1)
            #expect(first.totalPages == 2)
            #expect(first.reviews.map(\.id) == ["one", "two"])
            #expect(first.reviews[0].content == "**A review**\n\n<script>plain text</script>")
            #expect(first.reviews[0].plainText == "**A review**\n\nplain text")
            #expect(first.reviews[0].rating == 8)
            #expect(first.reviews[0].url?.host() == "www.themoviedb.org")
            #expect(first.reviews[1].rating == nil)
            #expect(first.reviews[1].url == nil)
            #expect(first.reviews[1].author == "TMDB member")
            let next = try await client().reviews(imdbID: "tt123", type: type, page: 2)
            #expect(next.reviews.isEmpty)
        }
    }

    @Test func formattingPreservesParagraphsAndStripsHTMLMarkup() {
        let review = TMDBReview(id: "one", author: "A", content: "A &amp; B<br><em>Emphasis</em></p>Next &quot;line&quot;",
                                rating: nil, createdAt: nil, url: nil)
        #expect(review.plainText == "A & B\nEmphasis\nNext \"line\"")
    }

    @Test func malformedIdentityAndPaginationRemainRetryableFailures() async {
        for scenario in ["wrongIdentity", "wrongPage", "malformed"] {
            await #expect(throws: TMDBError.invalidResponse) {
                try await client(scenario).reviews(imdbID: "tt123", type: "movie")
            }
        }
        await #expect(throws: TMDBError.invalidResponse) { try await client("wrongPage").popularDirectors() }
        await #expect(throws: TMDBError.notFound) { try await client("noMatch").reviews(imdbID: "tt123", type: "movie") }
        for id in ["nm123", "tt123/credits", ""] {
            await #expect(throws: TMDBError.notFound) { try await client().reviews(imdbID: id, type: "movie") }
        }
        for page in [0, 501] {
            await #expect(throws: TMDBError.notFound) { try await client().reviews(imdbID: "tt123", type: "movie", page: page) }
        }
    }
}

private final class DiscoveryProtocol: StubURLProtocol, @unchecked Sendable {
    override func startLoading() {
        guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scenario = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: ""),
              components.queryItems?.contains(.init(name: "language", value: "en-US")) == true,
              !url.absoluteString.contains("Bearer") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let page = components.queryItems?.first { $0.name == "page" }?.value ?? "1"
        let body: String
        var status = 200
        switch url.path {
        case "/3/person/popular":
            let people = scenario == "sparse" ? Self.sparsePeople : (scenario == "emptyPeople" ? "[]" : Self.people)
            body = #"{"page":\#(scenario == "wrongPage" ? "99" : page),"total_pages":2,"results":\#(page == "1" ? people : "[]")}"#
        case let path where path.hasPrefix("/3/person/"):
            guard let id = Int(path.split(separator: "/").last ?? ""),
                  let popularity = [525: 70, 488: 50, 1032: 40, 138: 35, 608: 30][id],
                  !(scenario == "sparse" && id == 525),
                  components.queryItems?.contains(where: { $0.name == "append_to_response" }) != true else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            if scenario == "removedSeed" && id == 138 { status = 404 }
            if scenario == "unauthorizedSeed" { status = 401 }
            let responseID = scenario == "wrongSeedIdentity" ? 999 : id
            body = #"{"id":\#(responseID),"name":"Director \#(id)","known_for_department":"Directing","popularity":\#(popularity),"profile_path":"/director-\#(id).jpg"}"#
        case "/3/find/tt123":
            body = scenario == "noMatch" ? #"{"movie_results":[],"tv_results":[]}"#
                : #"{"movie_results":[{"id":42}],"tv_results":[{"id":84}]}"#
        case "/3/movie/42/reviews", "/3/tv/84/reviews":
            let identity = scenario == "wrongIdentity" ? 99 : (url.path.contains("/movie/") ? 42 : 84)
            body = scenario == "malformed" ? #"{"error":"failed"}"#
                : #"{"id":\#(identity),"page":\#(scenario == "wrongPage" ? "99" : page),"total_pages":2,"results":\#(page == "1" ? Self.reviews : "[]")}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        respond(status, body: Data(body.utf8))
    }

    static let sparsePeople = #"""
    [{"id":525,"name":"Christopher Nolan","known_for_department":"Directing","popularity":85,"profile_path":"/nolan.jpg"},
     {"id":8,"name":"Popular Actor","known_for_department":"Acting","popularity":1000}]
    """#
    static let people = #"""
    [{"id":3,"name":"Director Three","known_for_department":"Directing","popularity":50,"profile_path":"https://evil.example/a.jpg"},
     {"id":7,"name":"Director Seven","known_for_department":"Directing","popularity":90,"profile_path":"/seven.jpg"},
     {"id":7,"name":"Duplicate","known_for_department":"Directing","popularity":90},
     {"id":8,"name":"Actor","known_for_department":"Acting","popularity":1000},
     {"id":9,"name":"Adult","known_for_department":"Directing","popularity":200,"adult":true},
     {"id":0,"name":"Invalid","known_for_department":"Directing","popularity":200},
     {"id":10,"name":" ","known_for_department":"Directing","popularity":200}]
    """#
    static let reviews = #"""
    [{"id":"one","author":"A member","content":" **A review**\n\n<script>plain text</script> ","author_details":{"rating":8},"url":"https://www.themoviedb.org/review/one"},
     {"id":"one","author":"Duplicate","content":"Duplicate"},
     {"id":"two","author":"","content":"Another review","author_details":{"rating":11},"url":"https://www.themoviedb.org.evil.example/review/two"},
     {"id":"empty","author":"A member","content":" "}]
    """#
}
