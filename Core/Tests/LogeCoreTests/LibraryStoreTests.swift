import Foundation
import Testing
@testable import LogeCore

@MainActor
struct LibraryStoreTests {
    let defaults = UserDefaults(suiteName: "LibraryStoreTests-\(UUID().uuidString)")!
    let movie = WatchItem(id: "tt1", type: "movie", metaID: "tt1", title: "Movie")
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func episode(_ season: Int, _ number: Int) -> WatchItem {
        WatchItem(id: "tt9:\(season):\(number)", type: "series", metaID: "tt9", title: "Show", season: season, episode: number)
    }

    func video(_ season: Int, _ number: Int) -> Video {
        Video(id: "tt9:\(season):\(number)", season: season, episode: number)
    }

    @Test func resumesUnfinishedItemsSlightlyEarly() {
        let store = LibraryStore(defaults: defaults)
        store.record(movie, position: 600, duration: 6000, at: t0)

        #expect(LibraryStore(defaults: defaults).resumePosition(for: "tt1") == 595)
    }

    @Test func ignoresBriefPlaybackAndFinishedItems() {
        let store = LibraryStore(defaults: defaults)
        store.record(movie, position: 10, duration: 6000, at: t0)
        #expect(store.progress.isEmpty)

        store.record(movie, position: 5800, duration: 6000, at: t0)
        #expect(store.resumePosition(for: "tt1") == nil)
        #expect(store.continueWatching.isEmpty)
    }

    @Test func rewindingAnEntryBelowTheThresholdStillUpdatesIt() {
        let store = LibraryStore(defaults: defaults)
        store.record(movie, position: 600, duration: 6000, at: t0)
        store.record(movie, position: 5, duration: 6000, at: t0.addingTimeInterval(10))

        #expect(store.resumePosition(for: "tt1") == nil)
    }

    @Test func aMomentOfPlaybackIsWorthKeepingOnlyForWhatsAlreadyTracked() {
        let store = LibraryStore(defaults: defaults)
        #expect(!store.recordsProgress(for: movie.id, at: 10))
        #expect(store.recordsProgress(for: movie.id, at: LibraryStore.minimumResumePosition))
        store.record(movie, position: 600, duration: 5000, at: t0)
        #expect(store.recordsProgress(for: movie.id, at: 10))
    }

    /// Libraries saved while Trakt was supported hold progress it reported as a percentage.
    @Test func progressSavedAsAPercentageResumesByFractionUntilPlayedHere() throws {
        let saved = WatchProgress(item: movie, position: 3000, duration: 6000, updatedAt: t0, isEstimated: true)
        defaults.set(try JSONEncoder().encode([movie.id: saved]), forKey: "watchProgress")
        let store = LibraryStore(defaults: defaults)

        #expect(store.estimatedFraction(for: movie.id) == 0.5)
        #expect(store.continueWatching.count == 1)
        store.record(movie, position: 600, duration: 5000, at: t0 + 60)
        #expect(store.estimatedFraction(for: movie.id) == nil)
    }

    @Test func continueWatchingShowsLatestEntryPerTitle() {
        let store = LibraryStore(defaults: defaults)
        store.record(episode(1, 1), position: 1000, duration: 2000, at: t0)
        store.record(movie, position: 600, duration: 6000, at: t0.addingTimeInterval(10))
        store.record(episode(1, 2), position: 300, duration: 2000, at: t0.addingTimeInterval(20))

        #expect(store.continueWatching.map(\.item.id) == ["tt9:1:2", "tt1"])
    }

    @Test func inProgressUsesTheLatestEpisodeRatherThanOlderUnfinishedOnes() throws {
        let store = LibraryStore(defaults: defaults)
        #expect(!store.isInProgress(metaID: "tt9"))
        store.record(episode(1, 1), position: 300, duration: 2000, at: t0)
        #expect(store.isInProgress(metaID: "tt9"))
        store.record(episode(1, 2), position: 1990, duration: 2000, at: t0 + 1)
        #expect(!store.isInProgress(metaID: "tt9"))
        // Another device's first seconds of the next episode aren't worth resuming either.
        var snapshot = store.playbackSyncSnapshot
        snapshot.entries["tt9:1:3"] = WatchProgress(item: episode(1, 3), position: 2, duration: 2000, updatedAt: t0 + 2)
        try store.applyPlaybackSyncSnapshot(snapshot)
        #expect(!store.isInProgress(metaID: "tt9"))
        store.record(episode(1, 3), position: 300, duration: 2000, at: t0 + 3)
        #expect(store.isInProgress(metaID: "tt9"))
    }

    @Test func followedSeriesAreTheLatestEntryOfEachSeriesMostRecentFirst() {
        let store = LibraryStore(defaults: defaults)
        let other = WatchItem(id: "tt8:2:1", type: "series", metaID: "tt8", title: "Other", season: 2, episode: 1)
        store.record(movie, position: 600, duration: 6000, at: t0 + 30)
        store.record(other, position: 600, duration: 2000, at: t0)
        // Marked together, a season's episodes share a time: the last one is where the viewer is.
        store.markWatched([episode(1, 1), episode(1, 3), episode(1, 2)], at: t0 + 10)

        #expect(store.followedSeries.map(\.item.id) == ["tt9:1:3", "tt8:2:1"])
    }

    @Test func upNextResumesOrAdvances() {
        let store = LibraryStore(defaults: defaults)
        let videos = [video(0, 1), video(2, 1), video(1, 2), video(1, 1)]
        #expect(store.upNext(metaID: "tt9", videos: videos) == nil)

        store.record(episode(1, 1), position: 900, duration: 2000, at: t0)
        #expect(store.upNext(metaID: "tt9", videos: videos) == UpNext(video: video(1, 1), resumeAt: 895))

        store.record(episode(1, 1), position: 1990, duration: 2000, at: t0.addingTimeInterval(10))
        #expect(store.upNext(metaID: "tt9", videos: videos) == UpNext(video: video(1, 2), resumeAt: nil))

        // Finishing the last episode of a season moves on to the next season, skipping specials.
        store.record(episode(1, 2), position: 1990, duration: 2000, at: t0.addingTimeInterval(20))
        #expect(store.upNext(metaID: "tt9", videos: videos)?.video == video(2, 1))

        store.record(episode(2, 1), position: 1990, duration: 2000, at: t0.addingTimeInterval(30))
        #expect(store.upNext(metaID: "tt9", videos: videos) == nil)
    }

    @Test func removingFromContinueWatchingForgetsTheWholeTitle() {
        let store = LibraryStore(defaults: defaults)
        store.record(episode(1, 1), position: 1990, duration: 2000, at: t0)
        store.record(episode(1, 2), position: 300, duration: 2000, at: t0.addingTimeInterval(10))
        store.removeFromContinueWatching(metaID: "tt9")

        #expect(LibraryStore(defaults: defaults).progress.isEmpty)
    }

    @Test func historyListsEveryEpisodeNewestFirst() {
        let store = LibraryStore(defaults: defaults)
        store.markWatched([episode(1, 1), episode(1, 2)], at: t0)
        store.record(movie, position: 5900, duration: 6000, at: t0.addingTimeInterval(10))
        store.record(episode(1, 3), position: 300, duration: 2000, at: t0.addingTimeInterval(20))

        #expect(store.history.map(\.item.id) == ["tt9:1:3", "tt1", "tt9:1:2", "tt9:1:1"])
        #expect(store.continueWatching.map(\.item.id) == ["tt9:1:3"])
    }

    @Test func recentlyWatchedShowsEachSeriesByItsLatestFinishedEpisode() {
        let store = LibraryStore(defaults: defaults)
        store.markWatched([episode(1, 1), episode(1, 2)], at: t0)
        store.record(movie, position: 5900, duration: 6000, at: t0 + 10)
        store.record(episode(1, 3), position: 10, duration: 2000, at: t0 + 20)

        #expect(store.recentlyWatched().map(\.item.id) == ["tt1", "tt9:1:2"])
    }

    @Test func recentlyWatchedLeavesOutWhatContinueWatchingShows() {
        let store = LibraryStore(defaults: defaults)
        store.record(episode(1, 1), position: 1990, duration: 2000, at: t0)
        store.record(episode(1, 2), position: 300, duration: 2000, at: t0 + 10)
        let other = WatchItem(id: "tt5:1:1", type: "series", metaID: "tt5", title: "New episode out")
        store.markWatched([movie, other], at: t0 + 20)

        #expect(store.recentlyWatched(excluding: ["tt5"]).map(\.item.id) == ["tt1"])
    }

    @Test func recentlyWatchedIsTheLatestTwelveNewestFirst() {
        let store = LibraryStore(defaults: defaults)
        for index in 0..<20 {
            let item = WatchItem(id: "tt\(index)", type: "movie", metaID: "tt\(index)", title: "")
            store.markWatched([item], at: t0 + Double(index))
        }

        #expect(store.recentlyWatched().map(\.item.id) == (8..<20).reversed().map { "tt\($0)" })
    }

    @Test func hidingFromRecentlyWatchedKeepsWatchedMarksUntilFinishedAgain() {
        let store = LibraryStore(defaults: defaults)
        store.markWatched([movie], at: t0)
        store.hideFromRecentlyWatched(metaID: movie.metaID, at: t0 + 10)

        let restored = LibraryStore(defaults: defaults)
        #expect(restored.recentlyWatched().isEmpty)
        #expect(restored.isWatched(movie.id))
        restored.record(movie, position: 5900, duration: 6000, at: t0 + 20)
        #expect(restored.recentlyWatched().map(\.item.id) == ["tt1"])
    }

    @Test func recentlyWatchedHidesPerProfile() {
        let store = LibraryStore(defaults: defaults)
        store.markWatched([movie], at: t0)
        store.activateProfile(id: "account")
        store.markWatched([movie], at: t0)
        store.hideFromRecentlyWatched(metaID: movie.metaID, at: t0 + 10)
        store.activateProfile(id: nil)

        #expect(store.recentlyWatched().map(\.item.id) == ["tt1"])
        store.activateProfile(id: "account")
        #expect(store.recentlyWatched().isEmpty)
    }

    @Test func dropsOldestEntriesBeyondTheLimit() {
        let store = LibraryStore(defaults: defaults)
        for index in 0...LibraryStore.maximumEntries {
            let item = WatchItem(id: "tt\(index)", type: "movie", metaID: "tt\(index)", title: "")
            store.record(item, position: 60, duration: 600, at: t0.addingTimeInterval(Double(index)))
        }

        #expect(store.progress.count == LibraryStore.maximumEntries)
        #expect(store.progress["tt0"] == nil)
    }

    @Test func ignoresNonFinitePlaybackWithoutBreakingPersistence() {
        let store = LibraryStore(defaults: defaults)
        store.record(movie, position: 600, duration: 6000, at: t0)
        store.record(movie, position: .infinity, duration: 6000, at: t0 + 1)
        store.record(movie, position: 900, duration: .infinity, at: t0 + 1)
        store.record(movie, position: .nan, duration: 6000, at: t0 + 1)

        #expect(store.progress[movie.id]?.position == 600)
        #expect(LibraryStore(defaults: defaults).progress[movie.id]?.position == 600)
    }

    @Test func markingASeasonAdvancesFromItsLastEpisode() {
        let store = LibraryStore(defaults: defaults)
        let videos = (1...12).map { video(1, $0) } + [video(2, 1)]
        store.markWatched((1...12).reversed().map { episode(1, $0) }, at: t0)

        #expect(store.upNext(metaID: "tt9", videos: videos)?.video == video(2, 1))
    }

    @Test func markingWatchedAlsoBoundsStoredHistory() {
        let store = LibraryStore(defaults: defaults)
        let items = (0...LibraryStore.maximumEntries).map {
            WatchItem(id: "tt\($0)", type: "movie", metaID: "tt\($0)", title: "")
        }
        store.markWatched(items, at: t0)

        #expect(store.progress.count == LibraryStore.maximumEntries)
        #expect(LibraryStore(defaults: defaults).progress.count == LibraryStore.maximumEntries)
    }

    @Test func myListTogglesAndPersistsNewestFirst() {
        let store = LibraryStore(defaults: defaults)
        let first = MetaPreview(id: "tt1", type: "movie", name: "First")
        let second = MetaPreview(id: "tt2", type: "movie", name: "Second")
        store.toggleSaved(first)
        store.toggleSaved(second)
        #expect(LibraryStore(defaults: defaults).saved.map(\.id) == ["tt2", "tt1"])

        store.toggleSaved(first)
        #expect(!LibraryStore(defaults: defaults).isSaved("tt1"))
    }

    @Test func myListFromOlderBuildsLoadsUnchanged() {
        // As older builds wrote it: one list, no custom lists alongside.
        let json = #"[{"id":"tt9","type":"series","name":"Show","poster":"https://img/9"},{"id":"tt1","type":"movie","name":"Movie"},{"id":"ch1","type":"channel","name":"Channel"}]"#
        defaults.set(Data(json.utf8), forKey: "savedTitles")

        let store = LibraryStore(defaults: defaults)
        #expect(store.saved.map(\.id) == ["tt9", "tt1", "ch1"])
        #expect(store.saved.first?.poster == "https://img/9")
    }

    @Test func customListsFoldIntoWatchLaterOnce() {
        defaults.set(Data(#"[{"id":"tt1","type":"movie","name":"Kept"}]"#.utf8), forKey: "savedTitles")
        // As older builds wrote them: oldest list first, each newest first, a title in two of them.
        let lists = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Horror","titles":[{"id":"tt3","type":"movie","name":"Three"},{"id":"tt1","type":"movie","name":"Kept"}]},"#
            + #"{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Empty","titles":[]},"#
            + #"{"id":"8F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Shows","titles":[{"id":"tt4","type":"series","name":"Four"},{"id":"tt3","type":"movie","name":"Three"}]}]"#
        defaults.set(Data(lists.utf8), forKey: "titleLists")

        let store = LibraryStore(defaults: defaults)
        #expect(store.saved.map(\.id) == ["tt1", "tt3", "tt4"])
        #expect(defaults.data(forKey: "titleLists") == nil)

        // Once folded, removing a title doesn't bring it back.
        store.toggleSaved(MetaPreview(id: "tt3", type: "movie", name: "Three"))
        #expect(LibraryStore(defaults: defaults).saved.map(\.id) == ["tt1", "tt4"])
    }

    @Test func watchLaterKeepsDatesAndTitlesFromOlderBuildsStayBelowNewOnes() throws {
        defaults.set(Data(#"[{"id":"tt9","type":"series","name":"Show"},{"id":"tt1","type":"movie","name":"Movie"}]"#.utf8), forKey: "savedTitles")
        let store = LibraryStore(defaults: defaults)
        let now = Date.now
        store.toggleSaved(MetaPreview(id: "tt2", type: "movie", name: "New"), at: now)
        let entries = store.watchLaterSyncSnapshot.entries
        #expect(entries.map(\.title.id) == ["tt2", "tt9", "tt1"])
        #expect(entries[0].addedAt == now && entries[2].addedAt < entries[1].addedAt)
        #expect(entries[1].addedAt < Date(timeIntervalSince1970: 60))

        // A removal anywhere, at any real time, wins over an undated title.
        let removed = WatchLaterSyncSnapshot(removals: ["tt9": now - 1_000_000])
        try store.applyWatchLaterSyncSnapshot(.merged(local: store.watchLaterSyncSnapshot, remote: removed))
        #expect(LibraryStore(defaults: defaults).saved.map(\.id) == ["tt2", "tt1"])
    }

    @Test func watchLaterMergeTakesTheLatestActionAndDropsOldRemovals() {
        let now = Date.now
        func entry(_ id: String, _ added: Date, poster: String? = nil) -> WatchLaterSyncSnapshot.Entry {
            .init(title: MetaPreview(id: id, type: "movie", name: id, poster: poster, description: "local only"), addedAt: added)
        }
        let local = WatchLaterSyncSnapshot(entries: [entry("readded", now - 5), entry("removedLater", now - 20), entry("bare", now - 30)],
                                           removals: ["old": now - 91 * 86_400, "recent": now - 89 * 86_400])
        let remote = WatchLaterSyncSnapshot(entries: [entry("new", now - 1), entry("bare", now - 30, poster: "https://img/p")],
                                            removals: ["readded": now - 10, "removedLater": now - 15])
        let merged = WatchLaterSyncSnapshot.merged(local: local, remote: remote, now: now)
        #expect(merged.entries.map(\.title.id) == ["new", "readded", "bare"])
        #expect(merged.removals.keys.sorted() == ["recent", "removedLater"])
        #expect(merged.entries.last?.title.poster == "https://img/p")
        // Only what My Lists draws syncs.
        #expect(merged.entries.allSatisfy { $0.title.description == nil })
        #expect(WatchLaterSyncSnapshot.merged(local: remote, remote: local, now: now) == merged)

        let store = LibraryStore(defaults: defaults)
        store.toggleSaved(MetaPreview(id: "tt1", type: "movie", name: "Movie"), at: now - 100 * 86_400)
        store.toggleSaved(MetaPreview(id: "tt1", type: "movie", name: "Movie"), at: now - 95 * 86_400)
        store.toggleSaved(MetaPreview(id: "tt2", type: "movie", name: "Other"), at: now)
        #expect(store.watchLaterSyncSnapshot.removals.isEmpty)
    }

    @Test func fillsArtworkMissingFromSavedEntries() async throws {
        let store = LibraryStore(defaults: defaults)
        let bare = MetaPreview(id: "tt9", type: "series", name: "Show")
        let drawn = MetaPreview(id: "tt1", type: "movie", name: "Movie", poster: "https://img/own")
        store.toggleSaved(bare)
        store.toggleSaved(drawn)
        store.record(episode(1, 2), position: 300, duration: 2000, at: t0)
        #expect(store.titlesMissingArtwork.map(\.id) == ["tt9"])

        let meta = Meta(id: "tt9", type: "series", name: "Show", poster: "https://img/poster",
                        background: "https://img/backdrop",
                        videos: [Video(id: "tt9:1:2", season: 1, episode: 2, thumbnail: "https://img/still")])
        var lookups: [String] = []
        await store.fillMissingArtwork { type, id in
            lookups.append("\(type)/\(id)")
            return id == meta.id ? meta : nil
        }
        // Once per launch, even for a title whose artwork couldn't be found.
        await store.fillMissingArtwork { _, id in
            lookups.append(id)
            return nil
        }
        #expect(lookups == ["series/tt9"])

        let reloaded = LibraryStore(defaults: defaults)
        #expect(reloaded.titlesMissingArtwork.isEmpty)
        #expect(reloaded.saved.map(\.poster) == ["https://img/own", "https://img/poster"])
        #expect(reloaded.saved.last?.background == "https://img/backdrop")
        let item = try #require(reloaded.progress["tt9:1:2"]?.item)
        #expect(item.poster == "https://img/poster")
        #expect(item.thumbnail == "https://img/still")
    }
}

@MainActor
struct LibraryMarkingTests {
    let defaults = UserDefaults(suiteName: "LibraryMarkingTests-\(UUID().uuidString)")!
    let show = WatchItem(id: "tt9", type: "series", metaID: "tt9", title: "Show")

    @Test func markingWatchedAdvancesUpNextAndUnmarkingUndoesIt() {
        let store = LibraryStore(defaults: defaults)
        let videos = [Video(id: "tt9:1:1", season: 1, episode: 1), Video(id: "tt9:1:2", season: 1, episode: 2)]
        store.markWatched([show.episode(videos[0])])

        #expect(store.isWatched("tt9:1:1"))
        #expect(store.upNext(metaID: "tt9", videos: videos)?.video == videos[1])
        #expect(store.continueWatching.isEmpty)

        store.markUnwatched(["tt9:1:1"])
        #expect(LibraryStore(defaults: defaults).progress.isEmpty)
    }

    @Test func remembersSourcesPerTitle() {
        let store = LibraryStore(defaults: defaults)
        let source = RememberedSource(itemID: "tt9:1:1", providerURL: "https://a.example/manifest.json",
                                      url: URL(string: "https://cdn.example/1.mkv")!, headers: [:], bingeGroup: "a|1080p")
        store.rememberSource(source, metaID: "tt9")
        #expect(LibraryStore(defaults: defaults).sources["tt9"] == source)

        store.forgetSource(metaID: "tt9")
        #expect(LibraryStore(defaults: defaults).sources.isEmpty)
    }

    @Test func continuingPicksTheSameBingeGroup() throws {
        let json = #"""
            [
              {
                "url": "https://a/1",
                "behaviorHints": {
                  "bingeGroup": "x|720p"
                }
              },
              {
                "url": "https://a/2",
                "behaviorHints": {
                  "bingeGroup": "x|1080p"
                }
              },
              {
                "infoHash": "00",
                "behaviorHints": {
                  "bingeGroup": "x|4k"
                }
              }
            ]
            """#
        let streams = try JSONDecoder().decode([StreamSource].self, from: Data(json.utf8))
        #expect(StreamSource.continuing(bingeGroup: "x|1080p", in: streams)?.url == "https://a/2")
        #expect(StreamSource.continuing(bingeGroup: "x|4k", in: streams) == nil)
        #expect(StreamSource.continuing(bingeGroup: nil, in: streams) == nil)
        // Up Next falls back to the first playable source, never the torrent-only one.
        #expect(SourceSelection.next(afterBingeGroup: "x|1080p", in: streams)?.url == "https://a/2")
        #expect(SourceSelection.next(afterBingeGroup: "x|4k", in: streams)?.url == "https://a/1")
    }

    @Test func readsCatalogGenresAndPaging() throws {
        let manifest = try decodeFixture("cinemeta-manifest", as: AddonManifest.self)
        let popular = try #require(manifest.catalogs.first { $0.id == "top" && $0.type == "movie" })
        #expect(popular.supportsPaging)
        #expect(popular.genres.contains("Comedy"))
    }
}
