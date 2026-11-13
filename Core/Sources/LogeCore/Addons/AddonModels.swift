import Foundation

// Image fields stay `String` rather than `URL`: addons routinely send empty or
// malformed values, and one bad poster must not fail a whole catalog.

/// A catalog entry: just enough to draw a poster tile.
/// Stremio's content types are open-ended strings; these are the two the app treats specially.
public enum MediaType {
    public static let movie = "movie"
    public static let series = "series"
}

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
    // Credits, which tell a search by a person's name apart from titles that only contain it.
    public var cast: [String]?
    public var director: [String]?
    public var writer: [String]?

    public init(
        id: String, type: String, name: String, poster: String? = nil, posterShape: String? = nil,
        releaseInfo: String? = nil, background: String? = nil, logo: String? = nil,
        description: String? = nil, imdbRating: String? = nil, genres: [String]? = nil, runtime: String? = nil,
        cast: [String]? = nil, director: [String]? = nil, writer: [String]? = nil
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
        self.cast = cast
        self.director = director
        self.writer = writer
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
    public var writer: [String]?
    /// ISO 8601: the premiere for a movie, the first episode for a series.
    public var released: String?
    public var country: String?
    public var awards: String?
    /// The protocol's newer form of credits and genres, which some addons send instead of
    /// `cast`, `director` and `writer`.
    public var links: [MetaLink]?
    /// Episodes for series; absent or empty for movies.
    public var videos: [Video]?
    public var trailers: MetaTrailers?

    public var releaseDate: Date? { released.flatMap(isoDate) }

    /// Minutes in a runtime such as "45 min" or "2h 16min".
    public static func minutes(inRuntime runtime: String?) -> Double? {
        guard let runtime else { return nil }
        let hours = runtime.firstMatch(of: /(\d+)\s*h/).flatMap { Double($0.1) } ?? 0
        let minutes = runtime.firstMatch(of: /(\d+)\s*min/).flatMap { Double($0.1) } ?? 0
        let total = hours * 60 + minutes
        return total > 0 ? total : nil
    }
}

/// A title's trailers, by YouTube video ID. An extra: a shape this doesn't know reads as no
/// trailers rather than failing the title's details.
public struct MetaTrailers: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        var source: String?
        /// `Trailer` or `Clip`.
        var type: String?
    }
    var entries: [Entry]

    public init(from decoder: any Decoder) throws {
        entries = (try? [Entry](from: decoder)) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        try entries.encode(to: encoder)
    }

    /// The first trailer, ahead of any clips.
    public var youTubeID: String? {
        entries.filter { $0.type == "Trailer" }.lazy.compactMap { youTubeVideoID($0.source) }.first
    }
}

/// The ID as it goes into a YouTube link, or nil for anything that isn't one.
func youTubeVideoID(_ value: String?) -> String? {
    guard let value, value.wholeMatch(of: /[A-Za-z0-9_-]{11}/) != nil else { return nil }
    return value
}

public struct MetaLink: Codable, Sendable, Equatable {
    public var name: String?
    /// `Cast`, `Directors`, `Writers` or `Genres`, among others.
    public var category: String?
    public var url: String?
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

    public var releaseDate: Date? { released.flatMap(isoDate) }

    /// False for announced episodes that haven't aired, which addons have no streams for yet.
    public func isReleased(asOf date: Date = .now) -> Bool {
        // Not `<=`: the iOS 27.2 SDK binds it to a Foundation symbol that 27.2 betas lack,
        // which crashes the details screen there.
        releaseDate.map { !($0 > date) } ?? true
    }
}

/// Addons send ISO 8601 dates both with and without fractional seconds.
private func isoDate(_ string: String) -> Date? {
    (try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        ?? (try? Date(string, strategy: .iso8601))
}

/// One playable source returned by a `stream` resource.
public struct StreamSource: Codable, Sendable, Hashable {
    public var name: String?
    public var title: String?
    public var description: String?
    /// Direct HTTP(S) media link. Peer-to-peer sources are never playable.
    public var url: String?
    /// Retained only to reject torrent descriptors, including ones with a URL attached.
    private var infoHash: String?
    private var fileIdx: Int?
    public var externalUrl: String?
    /// Subtitles that belong to this particular file, offered alongside its own tracks.
    public var subtitles: [Subtitle]?
    public var behaviorHints: BehaviorHints?

    public struct BehaviorHints: Codable, Sendable, Hashable {
        public var bingeGroup: String?
        public var filename: String?
        /// The selected video file's size in bytes, distinct from a torrent or season pack.
        public var videoSize: Int64?
        public var proxyHeaders: ProxyHeaders?
    }

    /// Some debrid addons require these headers on the media request itself.
    public struct ProxyHeaders: Codable, Sendable, Hashable {
        public var request: [String: String]?
    }

    /// The direct HTTP(S) link, if this source has one. Torrents, YouTube IDs
    /// and external links (which open another app) don't.
    public var playbackURL: URL? {
        guard infoHash == nil, fileIdx == nil,
              let url = url.flatMap(URL.init(string:)), Self.isDirectPlaybackURL(url) else {
            return nil
        }
        return url
    }

    /// Applied again at the player boundary to cover remembered sources as well as addons.
    public static func isDirectPlaybackURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "")
            && url.host?.isEmpty == false
            && url.pathExtension.lowercased() != "torrent"
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
