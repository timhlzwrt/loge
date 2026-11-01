import Foundation
import Testing
@testable import MediaCore

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

    @Test func continueWatchingShowsLatestEntryPerTitle() {
        let store = LibraryStore(defaults: defaults)
        store.record(episode(1, 1), position: 1000, duration: 2000, at: t0)
        store.record(movie, position: 600, duration: 6000, at: t0.addingTimeInterval(10))
        store.record(episode(1, 2), position: 300, duration: 2000, at: t0.addingTimeInterval(20))

        #expect(store.continueWatching.map(\.item.id) == ["tt9:1:2", "tt1"])
    }

    @Test func inProgressUsesTheLatestEpisodeRatherThanOlderUnfinishedOnes() {
        let store = LibraryStore(defaults: defaults)
        #expect(!store.isInProgress(metaID: "tt9"))
        store.record(episode(1, 1), position: 300, duration: 2000, at: t0)
        #expect(store.isInProgress(metaID: "tt9"))
        store.record(episode(1, 2), position: 1990, duration: 2000, at: t0 + 1)
        #expect(!store.isInProgress(metaID: "tt9"))
        store.mergeRemote(episode(1, 3), fraction: 0.001, estimatedDuration: 2000, at: t0 + 2)
        #expect(!store.isInProgress(metaID: "tt9"))
        store.record(episode(1, 3), position: 300, duration: 2000, at: t0 + 3)
        #expect(store.isInProgress(metaID: "tt9"))
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

    @Test func myListFromOlderBuildsSplitsIntoShowsAndMovies() {
        // As older builds wrote it: one list, no custom lists alongside.
        let json = #"[{"id":"tt9","type":"series","name":"Show","poster":"https://img/9"},{"id":"tt1","type":"movie","name":"Movie"},{"id":"ch1","type":"channel","name":"Channel"}]"#
        defaults.set(Data(json.utf8), forKey: "savedTitles")

        let store = LibraryStore(defaults: defaults)
        #expect(store.saved.map(\.id) == ["tt9", "tt1", "ch1"])
        #expect(store.savedSeries.map(\.id) == ["tt9"])
        #expect(store.savedMovies.map(\.id) == ["tt1", "ch1"])
        #expect(store.savedSeries.first?.poster == "https://img/9")
        #expect(store.lists.isEmpty)

        // Adding a custom list leaves My List as it was.
        store.toggle(MetaPreview(id: "tt5", type: "movie", name: "Other"), inList: store.createList(named: "Later"))
        #expect(LibraryStore(defaults: defaults).saved.map(\.id) == ["tt9", "tt1", "ch1"])
    }

    @Test func customListsPersistTheirTitlesNewestFirst() {
        let store = LibraryStore(defaults: defaults)
        let horror = store.createList(named: "  Horror  ")
        let empty = store.createList(named: " ")
        let first = MetaPreview(id: "tt1", type: "movie", name: "First")
        let second = MetaPreview(id: "tt2", type: "series", name: "Second")
        store.toggle(first, inList: horror)
        store.toggle(second, inList: horror)

        var reloaded = LibraryStore(defaults: defaults)
        #expect(reloaded.lists.map(\.name) == ["Horror", "Untitled List"])
        #expect(reloaded.lists.first?.titles.map(\.id) == ["tt2", "tt1"])
        #expect(reloaded.isInList("tt1", list: horror))
        #expect(!reloaded.isInList("tt1", list: empty))
        #expect(!reloaded.isSaved("tt1"))

        store.toggle(first, inList: horror)
        store.renameList(horror, to: "Scary")
        store.renameList(empty, to: "")
        reloaded = LibraryStore(defaults: defaults)
        #expect(!reloaded.isInList("tt1", list: horror))
        #expect(reloaded.lists.map(\.name) == ["Scary", "Untitled List"])

        store.deleteList(horror)
        #expect(LibraryStore(defaults: defaults).lists.map(\.id) == [empty])
    }

    @Test func fillsArtworkMissingFromSavedEntries() async throws {
        let store = LibraryStore(defaults: defaults)
        let list = store.createList(named: "Later")
        let bare = MetaPreview(id: "tt9", type: "series", name: "Show")
        let drawn = MetaPreview(id: "tt1", type: "movie", name: "Movie", poster: "https://img/own")
        store.toggleSaved(bare)
        store.toggleSaved(drawn)
        store.toggle(bare, inList: list)
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
        #expect(reloaded.lists.first?.titles.first?.background == "https://img/backdrop")
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
        let json = #"[{"url":"https://a/1","behaviorHints":{"bingeGroup":"x|720p"}},{"url":"https://a/2","behaviorHints":{"bingeGroup":"x|1080p"}},{"infoHash":"00","behaviorHints":{"bingeGroup":"x|4k"}}]"#
        let streams = try JSONDecoder().decode([StreamSource].self, from: Data(json.utf8))
        #expect(StreamSource.continuing(bingeGroup: "x|1080p", in: streams)?.url == "https://a/2")
        #expect(StreamSource.continuing(bingeGroup: "x|4k", in: streams) == nil)
        #expect(StreamSource.continuing(bingeGroup: nil, in: streams) == nil)
    }

    @Test func readsCatalogGenresAndPaging() throws {
        let manifest = try decodeFixture("cinemeta-manifest", as: AddonManifest.self)
        let popular = try #require(manifest.catalogs.first { $0.id == "top" && $0.type == "movie" })
        #expect(popular.supportsPaging)
        #expect(popular.genres.contains("Comedy"))
    }
}
