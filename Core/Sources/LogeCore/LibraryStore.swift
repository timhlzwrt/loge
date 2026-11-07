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
    private static let listsKey = "titleLists"
    private static let activeProfileKey = "libraryActiveProfile"
    private static let archiveKey = "playbackSyncArchive"
    private static let removalsKey = "playbackSyncRemovals"
    private static let titleRemovalsKey = "playbackSyncTitleRemovals"
    private static let resumeFractionsKey = "playbackSyncResumeFractions"

    public private(set) var progress: [String: WatchProgress]
    public private(set) var activeProfileID: String?
    @ObservationIgnored private var playbackArchive: [String: WatchProgress]
    @ObservationIgnored private var playbackRemovals: [String: Date]
    @ObservationIgnored private var playbackTitleRemovals: [String: Date]
    @ObservationIgnored private var remoteResumeFractions: [String: Double]
    /// Watch Later, newest first: the one list older builds saved, so it needs no migration.
    public private(set) var saved: [MetaPreview]
    /// The user's own lists, oldest first.
    public private(set) var lists: [TitleList]
    /// Keyed by movie or series ID.
    public private(set) var sources: [String: RememberedSource]

    private let defaults: UserDefaults
    /// Titles already looked up for artwork, so one that has none isn't fetched again.
    @ObservationIgnored private var artworkLookedUp = Set<String>()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let profile = defaults.string(forKey: Self.activeProfileKey)
        activeProfileID = profile
        progress = Self.decode(defaults.data(forKey: Self.storageKey(Self.progressKey, profile: profile))) ?? [:]
        saved = Self.decode(defaults.data(forKey: Self.storageKey(Self.savedKey, profile: profile))) ?? []
        lists = Self.decode(defaults.data(forKey: Self.storageKey(Self.listsKey, profile: profile))) ?? []
        sources = Self.decode(defaults.data(forKey: Self.storageKey(Self.sourcesKey, profile: profile))) ?? [:]
        playbackArchive = Self.decode(defaults.data(forKey: Self.storageKey(Self.archiveKey, profile: profile))) ?? [:]
        playbackRemovals = Self.decode(defaults.data(forKey: Self.storageKey(Self.removalsKey, profile: profile))) ?? [:]
        playbackTitleRemovals = Self.decode(defaults.data(forKey: Self.storageKey(Self.titleRemovalsKey, profile: profile))) ?? [:]
        remoteResumeFractions = Self.decode(defaults.data(forKey: Self.storageKey(Self.resumeFractionsKey, profile: profile))) ?? [:]
    }

    /// Profile-local library data is kept when signing out, rather than copied into another account.
    public func activateProfile(id: String?) {
        guard id != activeProfileID else { return }
        saveProgress()
        save(saved, forKey: Self.savedKey)
        save(lists, forKey: Self.listsKey)
        save(sources, forKey: Self.sourcesKey)
        activeProfileID = id
        if let id { defaults.set(id, forKey: Self.activeProfileKey) }
        else { defaults.removeObject(forKey: Self.activeProfileKey) }
        progress = Self.decode(data(forKey: Self.progressKey)) ?? [:]
        saved = Self.decode(data(forKey: Self.savedKey)) ?? []
        lists = Self.decode(data(forKey: Self.listsKey)) ?? []
        sources = Self.decode(data(forKey: Self.sourcesKey)) ?? [:]
        playbackArchive = Self.decode(data(forKey: Self.archiveKey)) ?? [:]
        playbackRemovals = Self.decode(data(forKey: Self.removalsKey)) ?? [:]
        playbackTitleRemovals = Self.decode(data(forKey: Self.titleRemovalsKey)) ?? [:]
        remoteResumeFractions = Self.decode(data(forKey: Self.resumeFractionsKey)) ?? [:]
        artworkLookedUp = []
    }

    public var playbackSyncSnapshot: PlaybackSyncSnapshot {
        PlaybackSyncSnapshot(entries: playbackArchive.merging(progress) { _, current in current },
                             removals: playbackRemovals, titleRemovals: playbackTitleRemovals)
    }

    /// Validate everything before replacing progress. Private sources and lists are unaffected.
    public func applyPlaybackSyncSnapshot(_ snapshot: PlaybackSyncSnapshot) throws {
        let snapshot = try snapshot.validated()
        let previous = playbackSyncSnapshot.entries
        remoteResumeFractions = remoteResumeFractions.filter { snapshot.entries[$0.key]?.isFinished == false }
        for (id, entry) in snapshot.entries where entry != previous[id] && !entry.isFinished {
            remoteResumeFractions[id] = entry.fraction
        }
        progress = snapshot.entries
        playbackArchive = [:]
        playbackRemovals = snapshot.removals
        playbackTitleRemovals = snapshot.titleRemovals
        saveProgress()
    }

    // MARK: Progress

    public func record(_ item: WatchItem, position: Double, duration: Double, at date: Date = .now) {
        guard duration.isFinite, duration > 0, position.isFinite, position >= 0,
              position >= Self.minimumResumePosition || progress[item.id] != nil || playbackArchive[item.id] != nil else { return }
        progress[item.id] = WatchProgress(item: item, position: position, duration: duration, updatedAt: date)
        playbackArchive[item.id] = nil
        playbackRemovals[item.id] = nil
        remoteResumeFractions[item.id] = nil
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
        playbackArchive[item.id] = nil
        playbackRemovals[item.id] = nil
        remoteResumeFractions[item.id] = nil
        saveProgress()
    }

    /// For progress from another device that hasn't been played here: how far in it is,
    /// so playback can seek once the real duration is known.
    public func estimatedFraction(for id: String) -> Double? {
        guard let entry = progress[id] ?? playbackArchive[id], !entry.isFinished else { return nil }
        return remoteResumeFractions[id] ?? (entry.isEstimated == true ? entry.fraction : nil)
    }

    /// Where to start this item, or nil to start from the beginning.
    public func resumePosition(for id: String) -> Double? {
        guard let entry = progress[id] ?? playbackArchive[id], !entry.isFinished, entry.position >= Self.minimumResumePosition else { return nil }
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

    /// Everything played or marked watched, most recent first, every episode on its own.
    /// Episodes marked watched together share a time, so they list last episode first.
    public var history: [WatchProgress] {
        progress.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return ($0.item.season ?? 0, $0.item.episode ?? 0, $0.item.id)
                > ($1.item.season ?? 0, $1.item.episode ?? 0, $1.item.id)
        }
    }

    /// Checks one title's resume state without building and sorting Continue Watching.
    public func isInProgress(metaID: String) -> Bool {
        guard let latest = latestProgress(metaID: metaID) else { return false }
        return !latest.isFinished && latest.position >= Self.minimumResumePosition
    }

    /// Marks items watched without playing them, e.g. a whole season the viewer saw elsewhere.
    public func markWatched(_ items: [WatchItem], at date: Date = .now) {
        for item in items {
            let existing = progress[item.id] ?? playbackArchive[item.id]
            let duration = existing?.duration ?? 1
            progress[item.id] = WatchProgress(
                item: item, position: duration, duration: duration, updatedAt: date,
                isEstimated: existing == nil ? true : existing?.isEstimated)
            playbackArchive[item.id] = nil
            playbackRemovals[item.id] = nil
            remoteResumeFractions[item.id] = nil
        }
        saveProgress()
    }

    public func markUnwatched(_ ids: [String], at date: Date = .now) {
        for id in ids {
            progress[id] = nil
            playbackArchive[id] = nil
            playbackRemovals[id] = date
            remoteResumeFractions[id] = nil
        }
        saveProgress()
    }

    public func isWatched(_ id: String) -> Bool {
        (progress[id] ?? playbackArchive[id])?.isFinished == true
    }

    /// Hides a title from Continue Watching by forgetting its progress.
    public func removeFromContinueWatching(metaID: String, at date: Date = .now) {
        let ids = playbackSyncSnapshot.entries.values.filter { $0.item.metaID == metaID }.map(\.item.id)
        for id in ids {
            progress[id] = nil
            playbackArchive[id] = nil
            playbackRemovals[id] = date
            remoteResumeFractions[id] = nil
        }
        playbackTitleRemovals[metaID] = date
        saveProgress()
    }

    /// The episode to play next: the most recently watched one if it's unfinished,
    /// otherwise the one after it. Nil if nothing has been watched, or the last
    /// episode is done.
    public func upNext(metaID: String, videos: [Video]) -> UpNext? {
        guard let latest = latestProgress(metaID: metaID) else { return nil }
        guard latest.isFinished else {
            guard let video = videos.first(where: { $0.id == latest.item.id }) else { return nil }
            return UpNext(video: video, resumeAt: resumePosition(for: video.id))
        }
        return Self.episode(after: latest.item.id, in: videos).map { UpNext(video: $0, resumeAt: nil) }
    }

    private func latestProgress(metaID: String) -> WatchProgress? {
        var latest: WatchProgress?
        for entries in [progress, playbackArchive] {
            for entry in entries.values where entry.item.metaID == metaID {
                if let current = latest {
                    if entry.updatedAt < current.updatedAt { continue }
                    if entry.updatedAt == current.updatedAt,
                       (entry.item.season ?? 0, entry.item.episode ?? 0) <= (current.item.season ?? 0, current.item.episode ?? 0) { continue }
                }
                latest = entry
            }
        }
        return latest
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

    // MARK: My List

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

    // MARK: Lists

    /// A blank name becomes "Untitled List". Returns the new list's ID.
    @discardableResult
    public func createList(named name: String) -> TitleList.ID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = TitleList(name: trimmed.isEmpty ? "Untitled List" : trimmed)
        lists.append(list)
        save(lists, forKey: Self.listsKey)
        return list.id
    }

    public func renameList(_ id: TitleList.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[index].name = trimmed
        save(lists, forKey: Self.listsKey)
    }

    public func deleteList(_ id: TitleList.ID) {
        lists.removeAll { $0.id == id }
        save(lists, forKey: Self.listsKey)
    }

    public func isInList(_ metaID: String, list id: TitleList.ID) -> Bool {
        lists.first { $0.id == id }?.titles.contains { $0.id == metaID } == true
    }

    public func toggle(_ meta: MetaPreview, inList id: TitleList.ID) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        if let position = lists[index].titles.firstIndex(where: { $0.id == meta.id }) {
            lists[index].titles.remove(at: position)
        } else {
            lists[index].titles.insert(meta, at: 0)
        }
        save(lists, forKey: Self.listsKey)
    }

    // MARK: Artwork

    /// Titles with a saved entry that can't be drawn: a list entry without a poster, or a
    /// Continue Watching entry without a backdrop or poster. Entries keep the artwork they
    /// were saved with, and catalogs, other devices' progress and older builds can leave it out.
    public var titlesMissingArtwork: [MetaPreview] {
        let listed = (saved + lists.flatMap(\.titles)).filter { $0.poster == nil }
        let watching = continueWatching.map(\.item)
            .filter { $0.background == nil || $0.poster == nil }
            .map { MetaPreview(id: $0.metaID, type: $0.type, name: $0.title) }
        var seen = Set<String>()
        return (listed + watching).filter { seen.insert($0.id).inserted }
    }

    /// Fills in artwork missing from this title's entries everywhere in the library.
    /// Artwork already there stays: it's what the user saw when they saved it.
    public func fillArtwork(from meta: Meta) {
        let before = (saved: saved, lists: lists, progress: progress)
        saved = saved.map { $0.id == meta.id ? $0.fillingArtwork(from: meta) : $0 }
        for index in lists.indices {
            lists[index].titles = lists[index].titles.map { $0.id == meta.id ? $0.fillingArtwork(from: meta) : $0 }
        }
        for (id, entry) in progress where entry.item.metaID == meta.id {
            progress[id]?.item = entry.item.fillingArtwork(from: meta)
        }
        if saved != before.saved { save(saved, forKey: Self.savedKey) }
        if lists != before.lists { save(lists, forKey: Self.listsKey) }
        if progress != before.progress { save(progress, forKey: Self.progressKey) }
    }

    /// Looks up the details of titles saved without artwork through the installed addons.
    public func fillMissingArtwork(from addons: AddonStore) async {
        await fillMissingArtwork { type, id in
            guard let client = addons.addons.metaClient(type: type, id: id) else { return nil }
            do {
                return try await client.meta(type: type, id: id)
            } catch {
                // Tried again next launch; the entry keeps drawing its title meanwhile.
                log.error("Couldn't look up artwork for \(id, privacy: .public): \(error)")
                return nil
            }
        }
    }

    /// Looks up each title in `titlesMissingArtwork` once per launch.
    func fillMissingArtwork(lookup: (_ type: String, _ id: String) async -> Meta?) async {
        for title in titlesMissingArtwork where artworkLookedUp.insert(title.id).inserted {
            if let meta = await lookup(title.type, title.id) {
                fillArtwork(from: meta)
            }
        }
    }

    // MARK: Persistence

    private func saveProgress() {
        if progress.count > Self.maximumEntries {
            let oldest = progress.values.sorted { $0.updatedAt < $1.updatedAt }.prefix(progress.count - Self.maximumEntries)
            for entry in oldest {
                if activeProfileID != nil { playbackArchive[entry.item.id] = entry }
                progress[entry.item.id] = nil
            }
        }
        save(progress, forKey: Self.progressKey)
        save(playbackArchive, forKey: Self.archiveKey)
        save(playbackRemovals, forKey: Self.removalsKey)
        save(playbackTitleRemovals, forKey: Self.titleRemovalsKey)
        save(remoteResumeFractions, forKey: Self.resumeFractionsKey)
    }

    private static func storageKey(_ key: String, profile: String?) -> String {
        guard let profile else { return key }
        return "libraryProfile." + Data(profile.utf8).base64EncodedString() + "." + key
    }

    private func data(forKey key: String) -> Data? {
        defaults.data(forKey: Self.storageKey(key, profile: activeProfileID))
    }

    private func save(_ value: some Encodable, forKey key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: Self.storageKey(key, profile: activeProfileID))
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
