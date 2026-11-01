import Foundation
import Testing
@testable import MediaCore

struct CatalogFiltersTests {
    let cinemeta = try! decodeFixture("cinemeta-manifest", as: AddonManifest.self)

    @Test func sortOptionsAreTheSameTypesListableCatalogs() {
        let popular = DiscoveryCatalogs.search[0]
        // "New" needs a genre, which it offers as years; the video catalogs need IDs.
        #expect(cinemeta.sortOptions(for: popular).map(\.id) == ["top", "year", "imdbRating"])
        let new = cinemeta.catalogs.first { $0.id == "year" }!
        #expect(new.requiresGenre && new.genresAreYears)
        #expect(!popular.catalog.requiresGenre && !popular.catalog.genresAreYears)
    }

    @Test func sortOptionsKeepAFixedGenre() {
        let crime = DiscoveryCatalogs.home.first { $0.defaultGenre == "Crime" }!
        #expect(cinemeta.sortOptions(for: crime).map(\.id) == ["top", "imdbRating"])
    }

    @Test func sortOptionsNeedSomethingToSwitchTo() {
        let other = CatalogSource(manifestURL: AddonStore.cinemetaURL,
                                  catalog: .init(type: "movie", id: "unlisted"))
        #expect(cinemeta.sortOptions(for: other).isEmpty)
    }

    @Test func searchFeedsNarrowToTypeAndGenre() {
        let search = DiscoveryCatalogs.search
        #expect(search.genres.first == "Action")
        #expect(search.genres.last == "Game-Show")
        #expect(Set(search.genres).count == search.genres.count)

        #expect(search.filtered(type: nil, genre: nil) == search)
        #expect(search.filtered(type: "series", genre: nil).map(\.title) == ["Series"])
        let comedy = search.filtered(type: nil, genre: "Comedy")
        #expect(comedy.map(\.title) == ["Movies · Comedy", "Series · Comedy"])
        #expect(comedy.allSatisfy { $0.defaultGenre == "Comedy" })
        #expect(search.filtered(type: nil, genre: "Reality-TV").map(\.catalog.type) == ["series"])
        #expect(search.filtered(type: "movie", genre: "Reality-TV").isEmpty)
    }

    @Test func narrowingLooksUpResultsThatListNoGenres() async throws {
        let results = [
            MetaPreview(id: "tt1", type: "movie", name: "Listed", genres: ["comedy"]),
            MetaPreview(id: "tt2", type: "movie", name: "Unlisted comedy"),
            MetaPreview(id: "tt3", type: "movie", name: "Unlisted drama"),
            MetaPreview(id: "tt4", type: "movie", name: "Failed lookup"),
            MetaPreview(id: "tt5", type: "movie", name: "Linked comedy"),
        ]
        let narrowed = try await CatalogSource.narrow(results, to: "Comedy") { preview in
            switch preview.id {
            case "tt2": return Meta(id: "tt2", type: "movie", name: "", genres: ["Comedy"])
            case "tt3": return Meta(id: "tt3", type: "movie", name: "", genres: ["Drama"])
            case "tt5": return Meta(id: "tt5", type: "movie", name: "",
                                    links: [MetaLink(name: "Comedy", category: "Genres")])
            default: throw URLError(.badServerResponse)
            }
        }
        #expect(narrowed.map(\.id) == ["tt1", "tt2", "tt5"])
    }

    @Test func narrowingFailsWhenNoLookupSucceeds() async {
        let results = [MetaPreview(id: "tt1", type: "movie", name: "A")]
        await #expect(throws: URLError.self) {
            try await CatalogSource.narrow(results, to: "Comedy") { _ in throw URLError(.notConnectedToInternet) }
        }
    }
}
