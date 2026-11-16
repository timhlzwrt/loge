import Foundation
import Testing
@testable import LogeCore

struct ReviewLinksTests {
    @Test func linksUseStableValidatedIMDbIDs() {
        #expect(ReviewLinks.imdb(imdbID: "tt0816692")?.path() == "/title/tt0816692/")
        #expect(ReviewLinks.letterboxd(imdbID: "tt0816692", type: "movie")?.host() == "letterboxd.com")
        #expect(ReviewLinks.letterboxd(imdbID: "tt0903747", type: "series") == nil)
        for id in ["nm123", "tt123/path", "https://example.org", ""] {
            #expect(ReviewLinks.imdb(imdbID: id) == nil)
            #expect(ReviewLinks.letterboxd(imdbID: id, type: "movie") == nil)
        }
    }
}
