import Foundation
import Observation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "library")

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

/// Where to pick a series back up.
public struct UpNext: Sendable, Equatable {
    public var video: Video
    /// Nil when the episode should start from the beginning.
    public var resumeAt: Double?
}

/// A named collection of titles, newest additions first.
public struct SavedList: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var titles: [MetaPreview]
}

/// Watch progress and the user's saved titles, kept on this device.
///
/// Persisted in `UserDefaults`, like `AddonStore`, because tvOS may purge an
/// app's files at any time.
@MainActor @Observable
public final class LibraryStore {
    public nonisolated static let finishedFraction = 0.92
    /// Playback shorter than this isn't worth resuming; it's usually someone sampling a source.
    public nonisolated static let minimumResumePosition: Double = 30
    /// Keeps the stored progress small; the oldest entries are dropped first.
    nonisolated static let maximumEntries = 500

    private static let progressKey = "watchProgress"
    private static let savedKey = "savedTitles"
    private static let sourcesKey = "lastSources"
    private static let listsKey = "customSavedLists"
    public nonisolated static let watchLaterID = "watch-later"

    public private(set) var progress: [String: WatchProgress]
    public private(set) var saved: [MetaPreview]
    public private(set) var customLists: [SavedList]

    public var lists: [SavedList] {
        [SavedList(id: Self.watchLaterID, name: "Watch Later", titles: saved)] + customLists
    }
    /// Keyed by movie or series ID.
    public private(set) var sources: [String: RememberedSource]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progress = Self.decode(defaults.data(forKey: Self.progressKey)) ?? [:]
        saved = Self.decode(defaults.data(forKey: Self.savedKey)) ?? []
        customLists = Self.decode(defaults.data(forKey: Self.listsKey)) ?? []
        sources = Self.decode(defaults.data(forKey: Self.sourcesKey)) ?? [:]
    }

    // MARK: Progress

    public func record(_ item: WatchItem, position: Double, duration: Double, at date: Date = .now) {
        guard duration.isFinite, duration > 0, position.isFinite, position >= 0,
              position >= Self.minimumResumePosition || progress[item.id] != nil else { return }
        progress[item.id] = WatchProgress(item: item, position: position, duration: duration, updatedAt: date)
        saveProgress()
    }

    /// Progress reported by another device, as a fraction. Newer local progress wins.
    /// Without a duration known here, `estimatedDuration` (the runtime) stands in.
    public func mergeRemote(_ item: WatchItem, fraction: Double, estimatedDuration: Double, at date: Date) {
        let local = progress[item.id]
        guard local.map({ $0.updatedAt < date }) ?? true else { return }
        let knownDuration = local.flatMap { $0.isEstimated == true ? nil : $0.duration }
        let duration = knownDuration ?? estimatedDuration
        guard duration.isFinite, duration > 0, fraction.isFinite else { return }
        progress[item.id] = WatchProgress(
            item: local?.item ?? item, position: min(max(fraction, 0), 1) * duration, duration: duration,
            updatedAt: date, isEstimated: knownDuration == nil ? true : nil)
        saveProgress()
    }

    /// For progress from another device that hasn't been played here: how far in it is,
    /// so playback can seek once the real duration is known.
    public func estimatedFraction(for id: String) -> Double? {
        guard let entry = progress[id], entry.isEstimated == true, !entry.isFinished else { return nil }
        return entry.fraction
    }

    /// Where to start this item, or nil to start from the beginning.
    public func resumePosition(for id: String) -> Double? {
        guard let entry = progress[id], !entry.isFinished, entry.position >= Self.minimumResumePosition else { return nil }
        // Back up a little so the viewer can find their place again.
        return max(entry.position - 5, 0)
    }

    /// Unfinished items, most recent first, at most one per movie or series.
    public var continueWatching: [WatchProgress] {
        var seen = Set<String>()
        return progress.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { seen.insert($0.item.metaID).inserted }
            .filter { !$0.isFinished && $0.position >= Self.minimumResumePosition }
    }

    /// Checks one title's resume state without building and sorting Continue Watching.
    public func isInProgress(metaID: String) -> Bool {
        guard let latest = progress.values.lazy.filter({ $0.item.metaID == metaID })
            .max(by: { $0.updatedAt < $1.updatedAt }) else { return false }
        return !latest.isFinished && latest.position >= Self.minimumResumePosition
    }

    /// Marks items watched without playing them, e.g. a whole season the viewer saw elsewhere.
    public func markWatched(_ items: [WatchItem], at date: Date = .now) {
        for item in items {
            let existing = progress[item.id]
            let duration = existing?.duration ?? 1
            progress[item.id] = WatchProgress(
                item: item, position: duration, duration: duration, updatedAt: date,
                isEstimated: existing == nil ? true : existing?.isEstimated)
        }
        saveProgress()
    }

    public func markUnwatched(_ ids: [String]) {
        ids.forEach { progress[$0] = nil }
        saveProgress()
    }

    public func isWatched(_ id: String) -> Bool {
        progress[id]?.isFinished == true
    }

    /// Hides a title from Continue Watching by forgetting its progress.
    public func removeFromContinueWatching(metaID: String) {
        progress = progress.filter { $0.value.item.metaID != metaID }
        saveProgress()
    }

    /// The episode to play next: the most recently watched one if it's unfinished,
    /// otherwise the one after it. Nil if nothing has been watched, or the last
    /// episode is done.
    public func upNext(metaID: String, videos: [Video]) -> UpNext? {
        let latest = progress.values
            .filter { $0.item.metaID == metaID }
            .max {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
                // A whole season marked watched shares one timestamp; advance from its last episode.
                return ($0.item.season ?? 0, $0.item.episode ?? 0) < ($1.item.season ?? 0, $1.item.episode ?? 0)
            }
        guard let latest else { return nil }
        guard latest.isFinished else {
            guard let video = videos.first(where: { $0.id == latest.item.id }) else { return nil }
            return UpNext(video: video, resumeAt: resumePosition(for: video.id))
        }
        return Self.episode(after: latest.item.id, in: videos).map { UpNext(video: $0, resumeAt: nil) }
    }

    /// The episode after `id` in viewing order, if there is one.
    public nonisolated static func episode(after id: String, in videos: [Video]) -> Video? {
        let ordered = playOrder(videos)
        guard let index = ordered.firstIndex(where: { $0.id == id }), index + 1 < ordered.count else { return nil }
        return ordered[index + 1]
    }

    /// Episodes in viewing order, specials (season 0) excluded.
    nonisolated static func playOrder(_ videos: [Video]) -> [Video] {
        videos
            .filter { ($0.season ?? 1) > 0 }
            .sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
    }

    // MARK: Sources

    public func rememberSource(_ source: RememberedSource, metaID: String) {
        sources[metaID] = source
        save(sources, forKey: Self.sourcesKey)
    }

    /// Forgets a source that no longer plays, so the next attempt offers the full list.
    public func forgetSource(metaID: String) {
        sources[metaID] = nil
        save(sources, forKey: Self.sourcesKey)
    }

    // MARK: Saved lists

    public func isSaved(_ id: String) -> Bool {
        saved.contains { $0.id == id }
    }

    public func toggleSaved(_ meta: MetaPreview) {
        if let index = saved.firstIndex(where: { $0.id == meta.id }) {
            saved.remove(at: index)
        } else {
            saved.insert(meta, at: 0)
        }
        save(saved, forKey: Self.savedKey)
    }

    public func contains(_ titleID: String, in listID: String) -> Bool {
        if listID == Self.watchLaterID { return isSaved(titleID) }
        return customLists.first { $0.id == listID }?.titles.contains { $0.id == titleID } == true
    }

    public func toggleSaved(_ meta: MetaPreview, in listID: String) {
        if listID == Self.watchLaterID {
            toggleSaved(meta)
            return
        }
        guard let list = customLists.firstIndex(where: { $0.id == listID }) else { return }
        if let title = customLists[list].titles.firstIndex(where: { $0.id == meta.id }) {
            customLists[list].titles.remove(at: title)
        } else {
            customLists[list].titles.insert(meta, at: 0)
        }
        save(customLists, forKey: Self.listsKey)
    }

    @discardableResult
    public func createList(name: String) -> String? {
        guard let name = validListName(name) else { return nil }
        let id = UUID().uuidString
        customLists.append(SavedList(id: id, name: name, titles: []))
        save(customLists, forKey: Self.listsKey)
        return id
    }

    @discardableResult
    public func renameList(_ id: String, to name: String) -> Bool {
        guard let index = customLists.firstIndex(where: { $0.id == id }),
              let name = validListName(name, excluding: id) else { return false }
        customLists[index].name = name
        save(customLists, forKey: Self.listsKey)
        return true
    }

    public func deleteList(_ id: String) {
        customLists.removeAll { $0.id == id }
        save(customLists, forKey: Self.listsKey)
    }

    private func validListName(_ name: String, excluding id: String? = nil) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !lists.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return nil }
        return name
    }

    // MARK: Persistence

    private func saveProgress() {
        if progress.count > Self.maximumEntries {
            let oldest = progress.values.sorted { $0.updatedAt < $1.updatedAt }.prefix(progress.count - Self.maximumEntries)
            oldest.forEach { progress[$0.item.id] = nil }
        }
        save(progress, forKey: Self.progressKey)
    }

    private func save(_ value: some Encodable, forKey key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            log.error("Couldn't save \(key, privacy: .public): \(error)")
        }
    }

    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Leave the stored data alone so a fixed build can still read it.
            log.error("Couldn't decode library data: \(error)")
            return nil
        }
    }
}
