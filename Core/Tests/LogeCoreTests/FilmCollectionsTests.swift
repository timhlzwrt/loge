import Foundation
import Testing
@testable import LogeCore

struct FilmCollectionsTests {
    @Test func festivalQueryKeepsAwardDatesAndWorksAwardedToDirectors() throws {
        let query = FilmCollection.cannes.query
        #expect(query.contains("ps:P166 wd:Q179808"))
        #expect(query.contains("pq:P1686 ?film"))
        #expect(query.contains("pq:P585 ?when"))
        #expect(query.contains("ORDER BY DESC(?date)"))
        #expect(query.contains("LIMIT 40"))
        #expect(query.contains("hint:optimizer \"None\""))
        let request = FilmCollectionClient.request(for: .cannes)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "query" }?.value == query)
        #expect(request.timeoutInterval == 30)
    }

    /// Wikidata's planner once took over a minute on these; the app gives up after 30 seconds.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WIKIDATA_LIVE"] != nil))
    func everyCollectionLoadsFromWikidata() async throws {
        let client = FilmCollectionClient()
        for collection in FilmCollection.allCases {
            let started = Date.now
            let films = try await client.films(in: collection)
            #expect(!films.isEmpty, "\(collection) returned nothing")
            #expect(Date.now.timeIntervalSince(started) < 15, "\(collection) took too long")
        }
    }

    @Test func directorQueryUsesFilmCreditsNotNameSearch() {
        #expect(FilmCollection.nolan.query.contains("?film wdt:P57 wd:Q25191"))
        #expect(FilmCollection.directors.allSatisfy { $0.query.contains("?film wdt:P31/wdt:P279* wd:Q11424") })
        #expect(FilmCollection.nolan.query.contains("MIN(?when)"))
        #expect(FilmCollection.festivals.allSatisfy { $0.isFestival })
        #expect(FilmCollection.directors.allSatisfy { !$0.isFestival })
    }

    @Test func addedFestivalsUseTheirDeclaredPrizes() {
        let awards: [(FilmCollection, String)] = [
            (.sundance, "Q3774974"), (.toronto, "Q39087364"),
            (.locarno, "Q1700510"), (.sanSebastian, "Q775086"),
        ]
        for (festival, award) in awards {
            #expect(festival.isFestival)
            #expect(festival.query.contains("wd:" + award))
            #expect(festival.officialResultsURL?.scheme == "https")
        }
        #expect(FilmCollection.locarno.query.contains("wd:Q30894009"))
        #expect(FilmCollection.locarno.awardScopeNote != nil)
        #expect(FilmCollection.sundance.awardScopeNote == nil)
        #expect(Set(FilmCollection.festivals).isDisjoint(with: FilmCollection.directors))
        #expect(Set(FilmCollection.festivals + FilmCollection.directors) == Set(FilmCollection.allCases))
    }

    @Test func collectionArtworkHasSecureSourceAndCompleteAttribution() throws {
        for collection in FilmCollection.allCases {
            #expect(collection.artworkCreditURL.scheme == "https")
            #expect(!collection.artworkCredit.isEmpty)
            if collection.isFestival {
                #expect(collection.logoAssetName == "festival-" + collection.rawValue)
                #expect(collection.artworkURL == nil)
            } else {
                let address = try #require(collection.artworkURL)
                let url = try #require(URL(string: address))
                #expect(url.scheme == "https")
                #expect(["thumb.wikimedia.org", "upload.wikimedia.org"].contains(url.host() ?? ""))
                #expect(collection.artworkCreditURL.host() == "commons.wikimedia.org")
                #expect(collection.artworkCreditURL.path().contains("/wiki/File:"))
                #expect(collection.artworkCredit.contains(" · CC"))
                #expect(collection.logoAssetName == nil)
            }
        }
    }

    @Test func decodeRejectsNonTitlesAndDeduplicatesIMDbIDs() throws {
        let data = Data(#"""
        {"results":{"bindings":[
          {"imdb":{"value":"tt123"},"filmLabel":{"value":"A Winner"},"date":{"value":"2026-05-24T00:00:00Z"}},
          {"imdb":{"value":"tt123"},"filmLabel":{"value":"A Winner"},"date":{"value":"2026-01-01T00:00:00Z"}},
          {"imdb":{"value":"nm123"},"filmLabel":{"value":"A Director"}},
          {"imdb":{"value":"tt123/path"},"filmLabel":{"value":"Invalid"}},
          {"imdb":{"value":"tt456"},"filmLabel":{"value":"Undated"}}
        ]}}
        """#.utf8)
        let films = try FilmCollectionClient.decode(data)
        #expect(films.map(\.id) == ["tt123", "tt456"])
        #expect(films.first?.year == 2026)
        #expect(films.last?.year == nil)
        #expect(films.first?.title.type == "movie")
        #expect(films.first?.title.name == "A Winner")
    }

    @Test func malformedResponseThrowsInsteadOfShowingAnEmptySuccess() {
        #expect(throws: (any Error).self) {
            try FilmCollectionClient.decode(Data(#"{"error":"timed out"}"#.utf8))
        }
    }

    @Test func reviewsUseStableValidatedIMDbIDs() {
        #expect(ReviewLinks.critics(imdbID: "tt0816692")?.path() == "/title/tt0816692/externalreviews/")
        #expect(ReviewLinks.letterboxd(imdbID: "tt0816692", type: "movie")?.host() == "letterboxd.com")
        #expect(ReviewLinks.letterboxd(imdbID: "tt0903747", type: "series") == nil)
        for id in ["nm123", "tt123/path", "https://example.org", ""] {
            #expect(ReviewLinks.critics(imdbID: id) == nil)
            #expect(ReviewLinks.letterboxd(imdbID: id, type: "movie") == nil)
        }
    }
}
