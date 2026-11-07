import Foundation

/// Something playable: a movie, or one episode of a series. Carries enough to
/// draw it in Continue Watching without fetching anything.
public struct WatchItem: Codable, Sendable, Hashable {
    /// What the `stream` resource is asked for: the movie ID, or the episode's video ID.
    public var id: String
    public var type: String
    /// The movie or series this belongs to.
    public var metaID: String
    public var title: String
    public var season: Int?
    public var episode: Int?
    public var episodeTitle: String?
    public var poster: String?
    public var background: String?
    public var thumbnail: String?

    public init(
        id: String, type: String, metaID: String, title: String,
        season: Int? = nil, episode: Int? = nil, episodeTitle: String? = nil,
        poster: String? = nil, background: String? = nil, thumbnail: String? = nil
    ) {
        self.id = id
        self.type = type
        self.metaID = metaID
        self.title = title
        self.season = season
        self.episode = episode
        self.episodeTitle = episodeTitle
        self.poster = poster
        self.background = background
        self.thumbnail = thumbnail
    }

    /// The same series, pointed at another of its episodes.
    public func episode(_ video: Video) -> WatchItem {
        var item = self
        item.id = video.id
        item.season = video.season
        item.episode = video.episode
        item.episodeTitle = video.displayTitle
        item.thumbnail = video.thumbnail
        return item
    }

    /// "S1 E2", or nil for movies.
    public var episodeCode: String? {
        guard let season, let episode else { return nil }
        return "S\(season) E\(episode)"
    }
}

public struct WatchProgress: Codable, Sendable, Equatable {
    public var item: WatchItem
    public var position: Double
    public var duration: Double
    public var updatedAt: Date
    /// From another device, which only reports a percentage: `duration` is the title's
    /// runtime until the file is played here. Nil rather than false in older saved data.
    public var isEstimated: Bool?

    public var fraction: Double {
        duration > 0 ? min(position / duration, 1) : 0
    }

    /// Credits usually start in the last few percent, so past this point counts as watched.
    public var isFinished: Bool {
        fraction >= LibraryStore.finishedFraction
    }
}

/// The stream last played for a movie or series, so playback can continue
/// without choosing a source again.
public struct RememberedSource: Codable, Sendable, Equatable {
    /// The movie or episode it was played for.
    public var itemID: String
    public var providerURL: String
    public var url: URL
    public var headers: [String: String]
    public var bingeGroup: String?

    public init(itemID: String, providerURL: String, url: URL, headers: [String: String], bingeGroup: String?) {
        self.itemID = itemID
        self.providerURL = providerURL
        self.url = url
        self.headers = headers
        self.bingeGroup = bingeGroup
    }
}

/// A list the user named and fills from titles' pages, beside My List.
public struct TitleList: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// Newest first, like My List.
    public var titles: [MetaPreview]

    public init(id: UUID = UUID(), name: String, titles: [MetaPreview] = []) {
        self.id = id
        self.name = name
        self.titles = titles
    }
}

extension MetaPreview {
    /// Artwork this entry was saved without, taken from the title's full details.
    public func fillingArtwork(from meta: Meta) -> MetaPreview {
        var preview = self
        preview.poster = poster ?? meta.poster
        preview.background = background ?? meta.background
        preview.logo = logo ?? meta.logo
        return preview
    }
}

extension WatchItem {
    func fillingArtwork(from meta: Meta) -> WatchItem {
        var item = self
        item.poster = poster ?? meta.poster
        item.background = background ?? meta.background
        item.thumbnail = thumbnail ?? meta.videos?.first { $0.id == id }?.thumbnail
        return item
    }
}

/// Where to pick a series back up.
public struct UpNext: Sendable, Equatable {
    public var video: Video
    /// Nil when the episode should start from the beginning.
    public var resumeAt: Double?
}
