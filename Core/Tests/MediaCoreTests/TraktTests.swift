import Foundation
import Testing
@testable import MediaCore

@MainActor
struct TraktTests {
    let movie = WatchItem(id: "tt0111161", type: "movie", metaID: "tt0111161", title: "Movie")

    func episode(_ season: Int, _ number: Int, show: String = "tt0903747") -> WatchItem {
        WatchItem(id: "\(show):\(season):\(number)", type: "series", metaID: show, title: "Show",
                  season: season, episode: number)
    }

    @Test func refersToMoviesAndEpisodesByIMDbID() throws {
        let movieBody = try #require(TraktClient.reference(for: movie))
        #expect((movieBody["movie"] as? [String: [String: String]])?["ids"]?["imdb"] == "tt0111161")

        let episodeBody = try #require(TraktClient.reference(for: episode(1, 2)))
        #expect((episodeBody["show"] as? [String: [String: String]])?["ids"]?["imdb"] == "tt0903747")
        #expect((episodeBody["episode"] as? [String: Int]) == ["season": 1, "number": 2])
    }

    @Test func skipsItemsTraktCantMatch() {
        let anime = WatchItem(id: "kitsu:1:1", type: "series", metaID: "kitsu:1", title: "Anime", season: 1, episode: 1)
        #expect(TraktClient.reference(for: anime) == nil)
        #expect(TraktClient.history([anime]) == nil)
    }

    @Test func groupsHistoryBySeason() throws {
        let body = try #require(TraktClient.history([episode(2, 1), movie, episode(1, 3), episode(1, 1)]))
        let shows = try #require(body["shows"] as? [[String: Any]])
        let seasons = try #require(shows.first?["seasons"] as? [[String: Any]])
        #expect(seasons.map { $0["number"] as? Int } == [1, 2])
        #expect((seasons[0]["episodes"] as? [[String: Int]]) == [["number": 1], ["number": 3]])
        #expect((body["movies"] as? [Any])?.count == 1)
    }

    @Test func decodesPlaybackProgress() throws {
        let url = try #require(Bundle.module.url(forResource: "trakt-playback", withExtension: "json", subdirectory: "Fixtures"))
        let entries = try TraktClient.decoder.decode([TraktClient.PlaybackEntry].self, from: Data(contentsOf: url))
        let playback = entries.compactMap(\.playback)

        #expect(playback.count == 2)
        #expect(playback[0] == TraktPlayback(imdbID: "tt0111161", progress: 42.5,
                                             pausedAt: Date(timeIntervalSince1970: 1_793_218_503)))
        #expect(playback[1].season == 1 && playback[1].episode == 2)
    }

    @Test(arguments: [("45 min", 45.0), ("2h 16min", 136.0), ("1h", 60.0), ("unknown", nil), (nil, nil)] as [(String?, Double?)])
    func readsRuntimes(_ runtime: String?, _ minutes: Double?) {
        #expect(TraktAccount.minutes(runtime) == minutes)
    }

    @Test func matchesEpisodesInTheSeriesMeta() throws {
        let meta = Meta(id: "tt0903747", type: "series", name: "Breaking Bad",
                        videos: [Video(id: "tt0903747:1:2", season: 1, episode: 2)])
        let entry = TraktPlayback(imdbID: "tt0903747", season: 1, episode: 2, progress: 50, pausedAt: .now)
        #expect(TraktAccount.item(for: entry, in: meta)?.id == "tt0903747:1:2")

        var missing = entry
        missing.episode = 9
        #expect(TraktAccount.item(for: missing, in: meta) == nil)
    }
}

@MainActor
struct RemoteProgressTests {
    let defaults = UserDefaults(suiteName: "RemoteProgressTests-\(UUID().uuidString)")!
    let movie = WatchItem(id: "tt1", type: "movie", metaID: "tt1", title: "Movie")
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func estimatesFromTheRuntimeUntilPlayedHere() {
        let store = LibraryStore(defaults: defaults)
        store.mergeRemote(movie, fraction: 0.5, estimatedDuration: 6000, at: t0)

        #expect(store.progress["tt1"]?.position == 3000)
        #expect(store.estimatedFraction(for: "tt1") == 0.5)
        #expect(store.continueWatching.count == 1)
    }

    @Test func usesTheDurationKnownHere() {
        let store = LibraryStore(defaults: defaults)
        store.record(movie, position: 600, duration: 5000, at: t0)
        store.mergeRemote(movie, fraction: 0.5, estimatedDuration: 6000, at: t0 + 60)

        #expect(store.progress["tt1"]?.position == 2500)
        #expect(store.estimatedFraction(for: "tt1") == nil)
    }

    @Test func finishedEstimatedItemsReplayFromTheBeginning() {
        let store = LibraryStore(defaults: defaults)
        store.mergeRemote(movie, fraction: 0.98, estimatedDuration: 6000, at: t0)
        #expect(store.estimatedFraction(for: movie.id) == nil)
        #expect(store.resumePosition(for: movie.id) == nil)

        store.markWatched([movie], at: t0 + 1)
        #expect(store.estimatedFraction(for: movie.id) == nil)
    }

    @Test func usesRuntimeAfterAnUnplayedItemWasMarkedWatched() {
        let store = LibraryStore(defaults: defaults)
        store.markWatched([movie], at: t0)
        store.mergeRemote(movie, fraction: 0.5, estimatedDuration: 6000, at: t0 + 60)

        #expect(store.progress[movie.id]?.position == 3000)
        #expect(store.estimatedFraction(for: movie.id) == 0.5)
    }

    @Test func rejectsNonFiniteRemoteProgressAndClampsItsRange() {
        let store = LibraryStore(defaults: defaults)
        store.mergeRemote(movie, fraction: .nan, estimatedDuration: 6000, at: t0)
        store.mergeRemote(movie, fraction: 0.5, estimatedDuration: .infinity, at: t0)
        #expect(store.progress.isEmpty)

        store.mergeRemote(movie, fraction: 2, estimatedDuration: 6000, at: t0)
        #expect(store.progress[movie.id]?.fraction == 1)
        store.mergeRemote(movie, fraction: -1, estimatedDuration: 6000, at: t0 + 1)
        #expect(store.progress[movie.id]?.fraction == 0)
    }

    @Test func keepsNewerLocalProgress() {
        let store = LibraryStore(defaults: defaults)
        store.record(movie, position: 600, duration: 5000, at: t0 + 60)
        store.mergeRemote(movie, fraction: 0.9, estimatedDuration: 6000, at: t0)

        #expect(store.progress["tt1"]?.position == 600)
    }
}
