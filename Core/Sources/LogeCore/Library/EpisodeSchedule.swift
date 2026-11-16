import Foundation
import Observation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "library")

/// An episode with the day it aired, carrying its series' artwork.
public struct ScheduledEpisode: Sendable, Equatable, Identifiable {
    public var item: WatchItem
    public var date: Date

    public var id: String { item.id }
}

/// When the series being watched got their latest episodes: the episode lists of the series
/// in the library, looked up through the addons and kept in memory. What's new is worked out
/// from them against the library, so it follows what's watched without another request.
@MainActor @Observable
public final class EpisodeSchedule {
    /// Long-running viewers have hundreds of series in their history; the recent ones are
    /// the ones still being followed.
    static let maximumSeries = 30
    /// Air dates change rarely, and every refresh asks for each series' whole episode list.
    static let lifetime: TimeInterval = 6 * 60 * 60

    /// Each series' episodes in viewing order, without specials. Written only when they
    /// change: Continue Watching on Home is rebuilt from them.
    private var episodes: [String: [Video]] = [:]
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    /// Being looked up, so overlapping refreshes (launch and Home appearing) ask once.
    @ObservationIgnored private var inFlight = Set<String>()

    public init() {}

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
        let series = library.followedSeries.prefix(Self.maximumSeries)
        let followed = series.map(\.item.metaID)
        if episodes.keys.contains(where: { !followed.contains($0) }) {
            episodes = episodes.filter { followed.contains($0.key) }
        }
        fetchedAt = fetchedAt.filter { followed.contains($0.key) }
        // Only a series whose latest episode was finished can have a new one waiting. The
        // others keep what was looked up, for when that episode is finished.
        for id in series.filter(\.isFinished).map(\.item.metaID) where !inFlight.contains(id) {
            if !force, let known = fetchedAt[id], now.timeIntervalSince(known) < Self.lifetime { continue }
            guard !Task.isCancelled else { return }
            inFlight.insert(id)
            let meta = await lookup(id)
            inFlight.remove(id)
            guard let meta else { continue }
            let videos = LibraryStore.playOrder(meta.videos ?? [])
            fetchedAt[id] = now
            if episodes[id] != videos { episodes[id] = videos }
        }
    }

    /// Episodes that came out since their series was last watched to the end of the one
    /// before, newest first: what Continue Watching has no entry for yet.
    public func newEpisodes(in library: LibraryStore, at now: Date = .now) -> [ScheduledEpisode] {
        library.followedSeries.compactMap { latest -> ScheduledEpisode? in
            guard latest.isFinished, let videos = episodes[latest.item.metaID],
                  let index = videos.firstIndex(where: { $0.id == latest.item.id }), index + 1 < videos.count,
                  let date = videos[index + 1].releaseDate, date > latest.updatedAt, !(date > now) else { return nil }
            return ScheduledEpisode(item: latest.item.episode(videos[index + 1]), date: date)
        }
        .sorted { $0.date > $1.date }
    }
}
