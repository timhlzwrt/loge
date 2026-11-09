import Foundation

/// One change waiting to reach Trakt, saved so it survives being offline or the app being closed.
struct TraktChange: Codable, Equatable, Sendable {
    enum Action: Codable, Equatable, Sendable {
        case progress(Double)
        /// Played to the end, with how far playback got.
        case finished(Double)
        case watched, unwatched
        /// Paused progress cleared, for the episode or movie, or for every episode of the title.
        case removed, removedTitle
    }

    var item: WatchItem
    var action: Action
    var date = Date.now

    /// Sent this soon, it can't have been overtaken and needs no look at Trakt first.
    var isFresh: Bool { date.timeIntervalSinceNow > -60 }

    var canReachTrakt: Bool {
        action == .removedTitle ? item.metaID.hasPrefix("tt") : TraktClient.reference(for: item) != nil
    }

    var needsRemoteState: Bool {
        switch action {
        case .removed, .removedTitle: true
        case .progress: !isFresh
        case .finished, .watched, .unwatched: false
        }
    }

    /// The latest word on an item wins. A rewatch doesn't undo the finished play before it,
    /// but a finished or unwatched one does make its older position pointless.
    func replaces(_ older: Self) -> Bool {
        let sameItem = older.item.id == item.id
        switch action {
        case .progress, .removed:
            if case .progress = older.action { return sameItem }
            return sameItem && older.action == .removed
        case .finished, .watched, .unwatched:
            switch older.action {
            case .progress, .finished, .watched, .unwatched: return sameItem
            case .removed, .removedTitle: return false
            }
        case .removedTitle:
            if case .progress = older.action { return older.item.metaID == item.metaID }
            return older.action == .removedTitle && older.item.metaID == item.metaID
        }
    }

    /// Marking a season sends one request, not one per episode at Trakt's one write a second.
    func isSentWith(_ other: Self) -> Bool {
        switch action {
        case .watched: other.action == .watched && other.date == date
        case .unwatched: other.action == .unwatched
        default: other == self
        }
    }
}
