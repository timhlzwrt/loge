import Foundation
import Testing
@testable import LogeCore

struct DiscoveryCatalogsTests {
    @Test func homeProvidesDistinctBrowsableShelves() {
        let shelves = DiscoveryCatalogs.home
        #expect(shelves.count == 8)
        #expect(Set(shelves.map(\.id)).count == shelves.count)
        #expect(shelves.filter { $0.manifestURL != AddonStore.cinemetaURL }.map(\.title) == ["Popular on Letterboxd"])
        #expect(shelves.allSatisfy { $0.catalog.supportsPaging })
        #expect(shelves.allSatisfy { $0.catalog.isBrowsable })
        #expect(shelves.compactMap(\.defaultGenre) == ["Crime", "Sci-Fi", "Animation"])
        #expect(shelves.first?.title == "Popular Movies")
    }

    @Test func detailsFillOnlyWhatAPreviewLacks() {
        let preview = MetaPreview(id: "tt1", type: "movie", name: "Film", logo: "https://img/own", runtime: "90 min")
        let meta = Meta(id: "tt1", type: "movie", name: "Film", logo: "https://img/meta", description: "Plot",
                        releaseInfo: "2024", runtime: "95 min", genres: ["Drama"], imdbRating: "7.5")
        let filled = preview.fillingDetails(from: meta)
        #expect(filled.logo == "https://img/own")
        #expect(filled.runtime == "90 min")
        #expect(filled.description == "Plot")
        #expect(filled.releaseInfo == "2024")
        #expect(filled.genres == ["Drama"])
        #expect(filled.imdbRating == "7.5")
    }

    @Test func featuredAlternatesTypesAndSkipsWeakOrBackdropFreeTitles() {
        func meta(_ id: String, _ type: String, rating: String? = nil, background: Bool = true) -> MetaPreview {
            MetaPreview(id: id, type: type, name: id, background: background ? "https://example.com/\(id)" : nil, imdbRating: rating)
        }
        let movies = [meta("m1", "movie", rating: "7.1"), meta("m2", "movie", rating: "5.9"),
                      meta("m3", "movie", background: false), meta("m4", "movie")]
        let series = [meta("s1", "series", rating: "8.4"), meta("m1", "movie")]
        #expect(DiscoveryCatalogs.featured(movies: movies, series: series).map(\.id) == ["m1", "s1", "m4"])

        let many = (0..<20).map { meta("m\($0)", "movie") }
        #expect(DiscoveryCatalogs.featured(movies: many, series: []).count == 10)
    }

    @Test func featuredBackgroundUsesTheLargeCinemetaImage() {
        let cinemeta = MetaPreview(id: "tt1", type: "movie", name: "A", background: "https://images.metahub.space/background/medium/tt1/img")
        #expect(cinemeta.featuredBackground == "https://images.metahub.space/background/large/tt1/img")
        let other = MetaPreview(id: "tt1", type: "movie", name: "A", background: "https://image.tmdb.org/t/p/w1280/x.jpg")
        #expect(other.featuredBackground == other.background)
    }

    @Test func featuredPosterUsesTheLargeCinemetaImage() {
        let cinemeta = MetaPreview(id: "tt1", type: "movie", name: "A", poster: "https://images.metahub.space/poster/small/tt1/img")
        #expect(cinemeta.featuredPoster == "https://images.metahub.space/poster/large/tt1/img")
        let other = MetaPreview(id: "tt1", type: "movie", name: "A", poster: "https://image.tmdb.org/t/p/w500/x.jpg")
        #expect(other.featuredPoster == other.poster)
    }

    @Test func laterRowsLeadWithTitlesTheRowsAboveDoNotShow() {
        func row(_ ids: String...) -> [MetaPreview] {
            ids.map { MetaPreview(id: $0, type: "series", name: $0) }
        }
        let rows = DiscoveryCatalogs.varyingLeads([
            row("a", "b", "c", "d"),
            row("a", "b", "e", "f", "g"),
            // Compares with the second row as reordered: e and f lead it, so they move here too.
            row("e", "f", "b", "h"),
            // Has nothing new, and keeps its titles rather than coming up short.
            row("a", "e"),
        ], leadCount: 2).map { $0.map(\.id) }
        #expect(rows[0] == ["a", "b", "c", "d"])
        #expect(rows[1] == ["e", "f", "a", "b", "g"])
        #expect(rows[2] == ["h", "e", "f", "b"])
        #expect(rows[3] == ["a", "e"])
    }

    @Test func everyGenreSearchListsHasATile() {
        for genre in DiscoveryCatalogs.search.genres {
            #expect(DiscoveryCatalogs.genre(named: genre) != nil, "\(genre)")
        }
    }

    @Test func letterboxdTitlesGetPlainCinemetaArtwork() throws {
        let response = try JSONDecoder().decode(CatalogResponse.self, from: Data("""
        {"metas": [
          {"id": "tt34890576", "type": "movie", "name": "Clayface",
           "poster": "https://api.stremboxd.com/poster?url=https%3A%2F%2Fa.ltrbxd.com%2Fx.jpg&rating=3.7"},
          {"id": "lb:clayface", "type": "movie", "name": "Unmatched", "poster": "https://a.ltrbxd.com/y.jpg"}
        ]}
        """.utf8))
        let metas = response.metas.map(\.withCinemetaArtwork)
        #expect(metas.map(\.poster) == ["https://images.metahub.space/poster/small/tt34890576/img", "https://a.ltrbxd.com/y.jpg"])
        #expect(metas.map(\.logo) == ["https://images.metahub.space/logo/medium/tt34890576/img", nil])
    }

    @Test func everyGenreOffersPopularAndAllTimeShelves() {
        let genres = DiscoveryCatalogs.genres
        #expect(Set(genres.map(\.id)).count == genres.count)
        for genre in genres {
            #expect(genre.popular.manifestURL == AddonStore.cinemetaURL)
            #expect(genre.popular.catalog.genres.contains(genre.name))
            #expect(genre.popular.defaultGenre == genre.name)
            #expect(genre.bestOfAllTime.catalog.id == "letterboxd-top250")
            #expect(genre.bestOfAllTime.catalog.genres.contains(genre.bestOfAllTime.defaultGenre ?? ""))
            #expect(genre.bestOfAllTime.usesCinemetaArtwork)
        }
        #expect(genres.first { $0.name == "Sci-Fi" }?.bestOfAllTime.defaultGenre == "Science Fiction")
    }

    @Test func searchProvidesOneUnfilteredFeedPerContentType() {
        let search = DiscoveryCatalogs.search
        #expect(search.map(\.catalog.type) == ["movie", "series"])
        #expect(search.allSatisfy { $0.catalog.supportsSearch && $0.defaultGenre == nil })
        #expect(Set(search.map(\.id)).count == 2)
    }

    @Test func builtinMetadataWorksWithoutInstalledAddons() {
        let addons: [InstalledAddon] = []
        #expect(addons.metaClient(type: "movie", id: "tt0111161")?.manifestURL == AddonStore.cinemetaURL)
        #expect(addons.metaClient(type: "series", id: "tt0903747")?.manifestURL == AddonStore.cinemetaURL)
        #expect(addons.metaClient(type: "movie", id: "kitsu:1") == nil)
        #expect(addons.metaClient(type: "channel", id: "tt1") == nil)
    }

    @Test func installedMetadataKeepsUserPriority() throws {
        let manifest = try decodeFixture("cinemeta-manifest", as: AddonManifest.self)
        let custom = InstalledAddon(manifestURL: "https://custom.example/manifest.json", manifest: manifest)
        #expect([custom].metaClient(type: "movie", id: "tt0111161")?.manifestURL == custom.manifestURL)
    }
}
