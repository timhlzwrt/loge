import Foundation

/// One addon stream as the sources list shows it.
public struct ListedSource: Identifiable, Sendable {
    public let id: String
    public let stream: StreamSource
    public let provider: StreamProvider
    public let details: StreamDetails

    public init(id: String, stream: StreamSource, provider: StreamProvider, details: StreamDetails) {
        self.id = id
        self.stream = stream
        self.provider = provider
        self.details = details
    }
}

/// How the sources list orders streams, and which one autoplay or a fallback picks.
/// None of it depends on how the list is drawn.
public enum SourceSelection {
    public struct Group: Identifiable, Sendable {
        public let title: String
        public let entries: [ListedSource]
        public var id: String { title }
    }

    /// By resolution, best first, with anything unrecognised under "Other". Within a
    /// resolution, sources the debrid service holds come first, then those it doesn't say
    /// about, then ones it has to fetch; otherwise the addons' own order.
    public static func grouped(_ sources: [ListedSource]) -> [Group] {
        func rank(_ source: ListedSource) -> Int {
            switch source.details.isCached { case true: 0; case nil: 1; case false: 2 }
        }
        let listed = StreamDetails.listedResolutions
        let buckets = listed.map { resolution in
            Group(title: resolution.label, entries: sources.filter { $0.details.resolution == resolution })
        } + [Group(title: "Other", entries: sources.filter { source in !listed.contains { $0 == source.details.resolution } })]
        return buckets.filter { !$0.entries.isEmpty }.map { group in
            let sorted = group.entries.enumerated().sorted { lhs, rhs in
                (rank(lhs.element), lhs.offset) < (rank(rhs.element), rhs.offset)
            }
            return Group(title: group.title, entries: sorted.map(\.element))
        }
    }

    /// What the sources list's Filter narrows it to. A source that doesn't say what it has
    /// stays listed, since it could match.
    public struct Filter: Equatable, Sendable {
        public enum Picture: Sendable { case any, hdr, sdr }

        /// An ISO 639-1 code, or nil for any language.
        public var audioLanguage: String?
        public var picture = Picture.any
        /// In Mbps; 0 for no limit.
        public var maximumBitrate = 0

        public init(audioLanguage: String? = nil, picture: Picture = .any, maximumBitrate: Int = 0) {
            self.audioLanguage = audioLanguage
            self.picture = picture
            self.maximumBitrate = maximumBitrate
        }

        public func matches(_ details: StreamDetails) -> Bool {
            let audioMatches = audioLanguage.map { details.languages.isEmpty || details.languages.contains($0) } ?? true
            let pictureMatches = switch picture {
            case .any: true
            case .hdr: details.isHDR != false
            case .sdr: details.isHDR != true
            }
            return audioMatches && pictureMatches && details.isWithin(maximumBitrate: maximumBitrate) != false
        }
    }

    /// What Play, Resume and Up Next may start by themselves, in the order to try them:
    /// sources whose bitrate is known to be within `maximumBitrate` Mbps (0 for no limit),
    /// then those that don't say, which could be far above it. Never one known to exceed it.
    public static func automatic<Source>(_ sources: [Source], maximumBitrate: Int,
                                         details: (Source) -> StreamDetails) -> [Source] {
        let fits = sources.map { details($0).isWithin(maximumBitrate: maximumBitrate) }
        return zip(sources, fits).filter { $0.1 == true }.map(\.0) + zip(sources, fits).filter { $0.1 == nil }.map(\.0)
    }

    /// The remembered source: the same file, or for another episode the same release from
    /// the same addon.
    public static func remembered(_ remembered: RememberedSource?, in sources: [ListedSource]) -> ListedSource? {
        guard let remembered else { return nil }
        return sources.first { $0.stream.playbackURL == remembered.url }
            ?? sources.first {
                remembered.bingeGroup != nil && $0.provider.id == remembered.providerURL
                    && $0.stream.behaviorHints?.bingeGroup == remembered.bingeGroup
            }
    }

    /// What autoplay continues with among the remembered addon's `streams`, already limited
    /// and ordered by `automatic`: the same file when it's the same item, else the same release.
    public static func continuing(_ remembered: RememberedSource, itemID: String, in streams: [StreamSource]) -> StreamSource? {
        streams.first { remembered.itemID == itemID && $0.playbackURL == remembered.url }
            ?? StreamSource.continuing(bingeGroup: remembered.bingeGroup, in: streams)
    }

    /// What Up Next plays among the addon's `streams`, already limited and ordered by
    /// `automatic`: the same release as the episode before, else the first playable one.
    public static func next(afterBingeGroup bingeGroup: String?, in streams: [StreamSource]) -> StreamSource? {
        StreamSource.continuing(bingeGroup: bingeGroup, in: streams) ?? streams.first { $0.playbackURL != nil }
    }

    /// What to try if `url` doesn't open: the same release first, then the others in the
    /// order given. Only a few, so a dead account doesn't spend minutes on every link.
    public static func fallbacks(for url: URL, bingeGroup: String?, among sources: [ListedSource]) -> [ListedSource] {
        let others = sources.filter { $0.stream.playbackURL != url }
        func isSameRelease(_ source: ListedSource) -> Bool {
            bingeGroup != nil && source.stream.behaviorHints?.bingeGroup == bingeGroup
        }
        return Array((others.filter(isSameRelease) + others.filter { !isSameRelease($0) }).prefix(3))
    }
}
