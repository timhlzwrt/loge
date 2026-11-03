import Foundation

/// Public Cinemeta feeds keep discovery available without installing a catalog addon.
/// These are editorial shelves, not recommendations derived from viewing history.
public enum DiscoveryCatalogs {
    public static let home: [CatalogSource] = [
        source(type: "movie", id: "top", title: "Popular Movies"),
        source(type: "series", id: "top", title: "Popular Series"),
        letterboxd(id: "letterboxd-popular", title: "Popular on Letterboxd"),
        source(type: "movie", id: "imdbRating", title: "IMDb Favourites · Movies"),
        source(type: "series", id: "imdbRating", title: "IMDb Favourites · Series"),
        source(type: "series", id: "top", title: "Crime Series", genre: "Crime"),
        source(type: "movie", id: "top", title: "Science Fiction", genre: "Sci-Fi"),
        source(type: "movie", id: "top", title: "Animation", genre: "Animation"),
    ]

    public static let search: [CatalogSource] = [
        source(type: "movie", id: "top", title: "Movies"),
        source(type: "series", id: "top", title: "Series"),
    ]

    /// Up to ten titles for the Home carousel, alternating movies and series. Each needs a
    /// backdrop to fill the hero, and titles rated below 6.5 are left to the rows; unrated
    /// ones stay, since new releases often have no rating yet.
    public static func featured(movies: [MetaPreview], series: [MetaPreview]) -> [MetaPreview] {
        func isFeaturable(_ meta: MetaPreview) -> Bool {
            guard meta.background != nil else { return false }
            guard let rating = meta.imdbRating.flatMap(Double.init) else { return true }
            return rating >= 6.5
        }
        let movies = movies.filter(isFeaturable)
        let series = series.filter(isFeaturable)
        var picks: [MetaPreview] = []
        for index in 0..<max(movies.count, series.count) {
            if index < movies.count { picks.append(movies[index]) }
            if index < series.count { picks.append(series[index]) }
        }
        var seen = Set<String>()
        return Array(picks.filter { seen.insert($0.id).inserted }.prefix(10))
    }

    /// Movie genres on Home, each with a still from a film that defines it.
    public static let genres: [Genre] = [
        Genre(name: "Action", stillID: "tt1392190"),  // Mad Max: Fury Road
        Genre(name: "Animation", stillID: "tt0245429"),  // Spirited Away
        Genre(name: "Comedy", stillID: "tt2278388"),  // The Grand Budapest Hotel
        Genre(name: "Crime", stillID: "tt0113277"),  // Heat
        Genre(name: "Drama", stillID: "tt0469494"),  // There Will Be Blood
        Genre(name: "Fantasy", stillID: "tt0120737"),  // The Fellowship of the Ring
        Genre(name: "Horror", stillID: "tt0081505"),  // The Shining
        Genre(name: "Mystery", stillID: "tt0114369"),  // Se7en
        Genre(name: "Romance", stillID: "tt0118694"),  // In the Mood for Love
        Genre(name: "Sci-Fi", letterboxdName: "Science Fiction", stillID: "tt1856101"),  // Blade Runner 2049
        Genre(name: "Thriller", stillID: "tt0443706"),  // Zodiac
        Genre(name: "War", stillID: "tt0078788"),  // Apocalypse Now
        Genre(name: "Western", stillID: "tt0060196"),  // The Good, the Bad and the Ugly
    ]

    public struct Genre: Sendable, Hashable, Identifiable {
        /// Cinemeta's name, which is also what's shown.
        public let name: String
        let letterboxdName: String
        let stillID: String

        init(name: String, letterboxdName: String? = nil, stillID: String) {
            self.name = name
            self.letterboxdName = letterboxdName ?? name
            self.stillID = stillID
        }

        public var id: String { name }

        public var still: String {
            "https://images.metahub.space/background/medium/\(stillID)/img"
        }

        /// The same still at 480 × 270, about 20 KB against the full one's megabyte, to show
        /// while that loads.
        public var stillPreview: String {
            "https://images.metahub.space/background/small/\(stillID)/img"
        }

        /// What's being watched now, from Cinemeta.
        public var popular: CatalogSource {
            source(type: "movie", id: "top", title: "Popular \(name)", genre: name)
        }

        /// Letterboxd's Top 250 narrative features in this genre; Cinemeta has no all-time ranking.
        public var bestOfAllTime: CatalogSource {
            letterboxd(id: "letterboxd-top250", title: "Best \(name) of All Time", genre: letterboxdName)
        }
    }

    /// Stremboxd mirrors Letterboxd's public lists as a Stremio addon, already matched to IMDb
    /// IDs. Letterboxd has no public API; used without configuration, it needs no account.
    static let letterboxdURL = "https://api.stremboxd.com/manifest.json"

    private static func letterboxd(id: String, title: String, genre: String? = nil) -> CatalogSource {
        let catalog = AddonManifest.Catalog(type: "movie", id: id, extra: [
            AddonManifest.Catalog.Extra(name: "genre", options: letterboxdGenres),
            AddonManifest.Catalog.Extra(name: "skip"),
        ])
        var source = CatalogSource(manifestURL: letterboxdURL, catalog: catalog, title: title, genre: genre)
        source.usesCinemetaArtwork = true
        return source
    }

    /// The addon's genre filter also takes sort orders and decades; only genres are offered.
    private static let letterboxdGenres = [
        "Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary", "Drama", "Family",
        "Fantasy", "History", "Horror", "Music", "Mystery", "Romance", "Science Fiction", "Thriller",
        "War", "Western",
    ]

    private static func source(type: String, id: String, title: String, genre: String? = nil) -> CatalogSource {
        var extras = [
            AddonManifest.Catalog.Extra(name: "genre", options: genres(for: type)),
            AddonManifest.Catalog.Extra(name: "skip"),
        ]
        if id == "top" { extras.append(.init(name: "search")) }
        let catalog = AddonManifest.Catalog(type: type, id: id, extra: extras)
        return CatalogSource(manifestURL: AddonStore.cinemetaURL, catalog: catalog, title: title, genre: genre)
    }

    private static func genres(for type: String) -> [String] {
        let movies = [
            "Action", "Adventure", "Animation", "Biography", "Comedy", "Crime", "Documentary",
            "Drama", "Family", "Fantasy", "History", "Horror", "Mystery", "Romance", "Sci-Fi",
            "Sport", "Thriller", "War", "Western",
        ]
        return type == "series" ? movies + ["Reality-TV", "Talk-Show", "Game-Show"] : movies
    }
}

extension MetaPreview {
    /// The hero's backdrop: Cinemeta's 1920-pixel image rather than the 1280-pixel one its
    /// catalogs list, which looks soft across a TV or a Retina iPad.
    public var featuredBackground: String? {
        background?.replacingOccurrences(of: "images.metahub.space/background/medium/", with: "images.metahub.space/background/large/")
    }

    /// Cinemeta's plain poster, and its title logo where the addon gives none, which the
    /// tvOS Home header shows for the focused title.
    var withCinemetaArtwork: MetaPreview {
        guard id.hasPrefix("tt") else { return self }
        var meta = self
        meta.poster = "https://images.metahub.space/poster/small/\(id)/img"
        meta.logo = logo ?? "https://images.metahub.space/logo/medium/\(id)/img"
        return meta
    }
}
