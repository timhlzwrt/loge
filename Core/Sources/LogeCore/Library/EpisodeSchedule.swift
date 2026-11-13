import Foundation
import Observation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "library")

/// An episode with the day it airs or aired, carrying its series' artwork.
public struct ScheduledEpisode: Sendable, Equatable, Identifiable {
    public var item: WatchItem
    public var date: Date

    public var id: String { item.id }
}

/// When the series being watched get their next episodes: the episode lists of the series
/// in the library, looked up through the addons and kept in memory. What's new or upcoming
/// is worked out from them against the library, so it follows what's watched without
/// another request.
@MainActor @Observable
public final class EpisodeSchedule {
    /// Long-running viewers have hundreds of series in their history; the recent ones are
    /// the ones still being followed.
    static let maximumSeries = 30
    /// Air dates change rarely, and every refresh asks for each series' whole episode list.
    static let lifetime: TimeInterval = 6 * 60 * 60

    private struct Episodes {
        /// In viewing order, without specials.
        var videos: [Video]
        var fetchedAt: Date
    }

    private var episodes: [String: Episodes] = [:]
    /// Being looked up, so overlapping refreshes (launch and Home appearing) ask once.
    @ObservationIgnored private var inFlight = Set<String>()

    public init() {}

    #if DEBUG
    /// UI checks show a series' schedule without the network.
    public func showForTesting(_ videos: [Video], of metaID: String) {
        episodes[metaID] = Episodes(videos: LibraryStore.playOrder(videos), fetchedAt: .now)
    }
    #endif

    /// Looks up the episodes of the series being followed through the installed addons.
    /// - Parameter force: Also those looked up recently, for pull-to-refresh.
    public func refresh(for library: LibraryStore, addons: AddonStore, force: Bool = false) async {
        await refresh(for: library, force: force) { id in
            guard let client = addons.addons.metaClient(type: MediaType.series, id: id) else { return nil }
            do {
                return try await client.meta(type: MediaType.series, id: id)
            } catch {
                // Tried again at the next refresh; the series shows nothing new meanwhile.
                if !(error is CancellationError) {
                    log.error("Couldn't look up episodes of \(id, privacy: .public): \(error)")
                }
                return nil
            }
        }
    }

    func refresh(for library: LibraryStore, force: Bool = false, at now: Date = .now,
                 lookup: (_ id: String) async -> Meta?) async {
        let followed = library.followedSeries.prefix(Self.maximumSeries).map(\.item.metaID)
        episodes = episodes.filter { followed.contains($0.key) }
        for id in followed where !inFlight.contains(id) {
            if !force, let known = episodes[id], now.timeIntervalSince(known.fetchedAt) < Self.lifetime { continue }
            guard !Task.isCancelled else { return }
            inFlight.insert(id)
            let meta = await lookup(id)
            inFlight.remove(id)
            guard let meta else { continue }
            episodes[id] = Episodes(videos: LibraryStore.playOrder(meta.videos ?? []), fetchedAt: now)
        }
    }

    /// Episodes that came out since their series was last watched to the end of the one
    /// before, newest first: what Continue Watching has no entry for yet.
    public func newEpisodes(in library: LibraryStore, at now: Date = .now) -> [ScheduledEpisode] {
        library.followedSeries.compactMap { latest -> ScheduledEpisode? in
            guard latest.isFinished, let videos = episodes[latest.item.metaID]?.videos,
                  let index = videos.firstIndex(where: { $0.id == latest.item.id }), index + 1 < videos.count,
                  let date = videos[index + 1].releaseDate, date > latest.updatedAt, !(date > now) else { return nil }
            return ScheduledEpisode(item: latest.item.episode(videos[index + 1]), date: date)
        }
        .sorted { $0.date > $1.date }
    }

    /// The next episode of each series that hasn't aired yet, soonest first.
    public func upcoming(in library: LibraryStore, at now: Date = .now) -> [ScheduledEpisode] {
        library.followedSeries.compactMap { latest -> ScheduledEpisode? in
            guard let next = episodes[latest.item.metaID]?.videos.first(where: { !$0.isReleased(asOf: now) }),
                  let date = next.releaseDate else { return nil }
            return ScheduledEpisode(item: latest.item.episode(next), date: date)
        }
        .sorted { $0.date < $1.date }
    }
}
