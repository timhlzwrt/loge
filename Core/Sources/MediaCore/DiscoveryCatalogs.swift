import Foundation

/// Public Cinemeta feeds keep discovery available without installing a catalog addon.
/// These are editorial shelves, not recommendations derived from viewing history.
public enum DiscoveryCatalogs {
    public static let home: [CatalogSource] = [
        source(type: "movie", id: "top", title: "Popular Movies"),
        source(type: "series", id: "top", title: "Popular Series"),
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
