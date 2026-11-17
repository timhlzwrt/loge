import Foundation
import Testing
@testable import LogeCore

struct ReviewLinksTests {
    @Test func linksUseStableValidatedIMDbIDs() {
        #expect(ReviewLinks.imdb(imdbID: "tt0816692")?.path() == "/title/tt0816692/")
        for id in ["nm123", "tt123/path", "https://example.org", ""] {
            #expect(ReviewLinks.imdb(imdbID: id) == nil)
        }
    }
}
