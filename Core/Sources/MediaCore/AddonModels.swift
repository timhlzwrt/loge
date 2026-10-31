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

    public init(
        id: String, type: String, name: String, poster: String? = nil, posterShape: String? = nil,
        releaseInfo: String? = nil, background: String? = nil, logo: String? = nil,
        description: String? = nil, imdbRating: String? = nil, genres: [String]? = nil, runtime: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.poster = poster
        self.posterShape = posterShape
        self.releaseInfo = releaseInfo
        self.background = background
        self.logo = logo
        self.description = description
        self.imdbRating = imdbRating
        self.genres = genres
        self.runtime = runtime
    }
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
public struct Video: Codable, Sendable, Hashable, Identifiable {
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

    /// Addons send ISO 8601 dates both with and without fractional seconds.
    public var releaseDate: Date? {
        guard let released else { return nil }
        return (try? Date(released, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(released, strategy: .iso8601))
    }

    /// False for announced episodes that haven't aired, which addons have no streams for yet.
    public func isReleased(asOf date: Date = .now) -> Bool {
        releaseDate.map { $0 <= date } ?? true
    }
}

/// One playable source returned by a `stream` resource.
public struct StreamSource: Codable, Sendable, Hashable {
    public var name: String?
    public var title: String?
    public var description: String?
    /// Direct HTTP(S) link — the only kind v1 plays.
    public var url: String?
    /// Torrent streams; listed but not playable until a torrent backend exists.
    public var infoHash: String?
    public var fileIdx: Int?
    public var externalUrl: String?
    /// Subtitles that belong to this particular file, offered alongside its own tracks.
    public var subtitles: [Subtitle]?
    public var behaviorHints: BehaviorHints?

    public struct BehaviorHints: Codable, Sendable, Hashable {
        public var bingeGroup: String?
        public var filename: String?
        public var proxyHeaders: ProxyHeaders?
    }

    /// Some debrid addons require these headers on the media request itself.
    public struct ProxyHeaders: Codable, Sendable, Hashable {
        public var request: [String: String]?
    }

    /// The direct HTTP(S) link, if this source has one. Torrents, YouTube IDs
    /// and external links (which open another app) don't.
    public var playbackURL: URL? {
        guard let url = url.flatMap(URL.init(string:)), url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        return url
    }

    /// `name` without the padding addons add to line things up in Stremio's UI:
    /// runs of spaces, zero-width joiners and blank lines.
    public var cleanName: String? {
        guard let name else { return nil }
        let invisible = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}")
        let lines = name.components(separatedBy: .newlines).map { line in
            String(String.UnicodeScalarView(line.unicodeScalars.filter { !invisible.contains($0) }))
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }
        let kept = lines.filter { !$0.isEmpty }
        return kept.isEmpty ? nil : kept.joined(separator: "\n")
    }

    public var requestHeaders: [String: String] {
        behaviorHints?.proxyHeaders?.request ?? [:]
    }

    /// The source to continue a series with: the playable stream in the same binge group
    /// as the one last watched, which addons use to mean "same release, same quality".
    public static func continuing(bingeGroup: String?, in streams: [StreamSource]) -> StreamSource? {
        guard let bingeGroup else { return nil }
        return streams.first { $0.behaviorHints?.bingeGroup == bingeGroup && $0.playbackURL != nil }
    }
}

/// An external subtitle file, from a stream or a `subtitles` resource.
public struct Subtitle: Codable, Sendable, Hashable {
    public var id: String?
    public var url: String
    /// Usually ISO 639-2, e.g. `eng`; OpenSubtitles adds a few of its own, such as `pob`.
    public var lang: String

    public init(id: String? = nil, url: String, lang: String) {
        self.id = id
        self.url = url
        self.lang = lang
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

struct SubtitlesResponse: Decodable {
    var subtitles: [Subtitle]
}
