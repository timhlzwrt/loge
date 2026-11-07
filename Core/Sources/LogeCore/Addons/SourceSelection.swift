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
    /// resolution `orders` decide, and ties keep the addons' own order.
    public static func grouped(_ sources: [ListedSource], by orders: [StreamDetails.SortOrder]) -> [Group] {
        let listed = StreamDetails.listedResolutions
        let buckets = listed.map { resolution in
            Group(title: resolution.label, entries: sources.filter { $0.details.resolution == resolution })
        } + [Group(title: "Other", entries: sources.filter { source in !listed.contains { $0 == source.details.resolution } })]
        return buckets.filter { !$0.entries.isEmpty }.map { group in
            let sorted = group.entries.enumerated().sorted { lhs, rhs in
                if StreamDetails.SortOrder.precedes(lhs.element.details, rhs.element.details, by: orders) { return true }
                if StreamDetails.SortOrder.precedes(rhs.element.details, lhs.element.details, by: orders) { return false }
                return lhs.offset < rhs.offset
            }
            return Group(title: group.title, entries: sorted.map(\.element))
        }
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
    /// to ones allowed to play automatically: the same file when it's the same item, else
    /// the same release.
    public static func continuing(_ remembered: RememberedSource, itemID: String, in streams: [StreamSource]) -> StreamSource? {
        streams.first { remembered.itemID == itemID && $0.playbackURL == remembered.url }
            ?? StreamSource.continuing(bingeGroup: remembered.bingeGroup, in: streams)
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
