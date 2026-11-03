import Foundation
import Testing
@testable import LogeCore

/// Opt-in checks use a temporary credential file; no credential belongs in fixtures or logs.
struct TMDBLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TMDB_TEST_TOKEN_FILE"] != nil))
    func realMovieSeriesCreditsAndIdentity() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["TMDB_TEST_TOKEN_FILE"])
        let credential = try String(contentsOfFile: path, encoding: .utf8)
        let client = TMDBClient(readAccessToken: credential)
        try await client.validate()
        let movie = try await client.details(imdbID: "tt0816692", type: "movie")
        #expect(movie.people.contains { $0.id == 525 && $0.roles.contains(.director) })
        #expect(movie.runtime == "169 min")
        #expect(movie.tagline?.isEmpty == false)
        #expect(movie.studios?.isEmpty == false)
        let show = try await client.details(imdbID: "tt0903747", type: "series")
        #expect(show.seasonCount == 5)
        #expect(show.episodeCount == 62)
        let person = try await client.person(id: 31)
        #expect(person.name == "Tom Hanks")
        #expect(person.titles.filter { $0.type == "movie" }.count > 100)
        #expect(person.titles.filter { $0.type == "series" }.count > 20)
        #expect(Set(person.titles.map(\.id)).count == person.titles.count)
        let director = try await client.person(id: 525)
        #expect(director.titles.contains { $0.tmdbID == 157336 && $0.roles.contains("Director") })
        #expect(try await client.imdbID(tmdbID: 157336, type: "movie") == "tt0816692")
        #expect(try await client.imdbID(tmdbID: 1396, type: "series") == "tt0903747")
    }
}
