import Foundation

// Image fields stay `String` rather than `URL`: addons routinely send empty or
// malformed values, and one bad poster must not fail a whole catalog.

/// A catalog entry: just enough to draw a poster tile.
public struct MetaPreview: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var type: String
    public var name: String
    public var poster: String?
    /// `"poster"` (2:3, the default), `"landscape"` or `"square"`.
    public var posterShape: String?
    public var releaseInfo: String?
    // Optional extras that richer addons like Cinemeta include, enough to
    // feature an item without fetching its full meta.
    public var background: String?
    public var logo: String?
    public var description: String?
    public var imdbRating: String?
    public var genres: [String]?
    public var runtime: String?
}

/// Full details for one title, from the `meta` resource.
public struct Meta: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var type: String
    public var name: String
    public var poster: String?
    public var background: String?
    public var logo: String?
    public var description: String?
    public var releaseInfo: String?
    public var runtime: String?
    public var genres: [String]?
    public var imdbRating: String?
    public var cast: [String]?
    public var director: [String]?
    /// Episodes for series; absent or empty for movies.
    public var videos: [Video]?
}

/// An episode (or other playable item) within a `Meta`. Its `id` is what
/// gets passed to the `stream` resource, e.g. `tt0903747:1:1`.
public struct Video: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String?
    public var name: String?
    public var season: Int?
    public var episode: Int?
    public var released: String?
    public var thumbnail: String?
    public var overview: String?

    /// Addons disagree on whether the episode name lives in `title` or `name`.
    public var displayTitle: String? { title ?? name }
}

/// One playable source returned by a `stream` resource.
public struct StreamSource: Codable, Sendable, Equatable {
    public var name: String?
    public var title: String?
    public var description: String?
    /// Direct HTTP(S) link — the only kind v1 plays.
    public var url: String?
    /// Torrent streams; listed but not playable until a torrent backend exists.
    public var infoHash: String?
    public var fileIdx: Int?
    public var externalUrl: String?
    public var behaviorHints: BehaviorHints?

    public struct BehaviorHints: Codable, Sendable, Equatable {
        public var bingeGroup: String?
        public var filename: String?
        public var proxyHeaders: ProxyHeaders?
    }

    /// Some debrid addons require these headers on the media request itself.
    public struct ProxyHeaders: Codable, Sendable, Equatable {
        public var request: [String: String]?
    }
}

struct CatalogResponse: Decodable {
    var metas: [MetaPreview]
}

struct MetaResponse: Decodable {
    var meta: Meta
}

struct StreamsResponse: Decodable {
    var streams: [StreamSource]
}
