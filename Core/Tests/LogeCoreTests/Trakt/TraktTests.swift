import Foundation
import Synchronization
import Testing
@testable import LogeCore

@MainActor
struct TraktTests {
    let movie = WatchItem(id: "tt0111161", type: "movie", metaID: "tt0111161", title: "Movie")

    func episode(_ season: Int, _ number: Int, show: String = "tt0903747") -> WatchItem {
        WatchItem(id: "\(show):\(season):\(number)", type: "series", metaID: show, title: "Show",
                  season: season, episode: number)
    }

    @Test func refersToMoviesAndEpisodesByIMDbID() throws {
        #expect(TraktClient.reference(for: movie) == .init(movie: .init(ids: .init(imdb: "tt0111161"))))
        #expect(TraktClient.reference(for: episode(1, 2))
                == .init(show: .init(ids: .init(imdb: "tt0903747")), episode: .init(season: 1, number: 2)))
        var scrobble = try #require(TraktClient.reference(for: movie))
        scrobble.progress = 50
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(scrobble)) as? [String: Any])
        #expect(Set(json.keys) == ["movie", "progress"])
    }

    @Test func skipsItemsTraktCantMatch() {
        let anime = WatchItem(id: "kitsu:1:1", type: "series", metaID: "kitsu:1", title: "Anime", season: 1, episode: 1)
        #expect(TraktClient.reference(for: anime) == nil)
        #expect(TraktClient.history([anime]) == nil)
    }

    @Test func groupsHistoryBySeason() throws {
        let body = try #require(TraktClient.history([episode(2, 1), movie, episode(1, 3), episode(1, 1)]))
        let seasons = try #require(body.shows.first?.seasons)
        #expect(seasons.map(\.number) == [1, 2])
        #expect(seasons[0].episodes == [.init(number: 1), .init(number: 3)])
        #expect(body.movies.count == 1)
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

@MainActor
struct TraktAccountTests {
    private let id = UUID().uuidString
    private let movie = WatchItem(id: "tt1", type: "movie", metaID: "tt1", title: "Saved movie")

    private func account(expired: Bool = false, save: @escaping (TraktToken?) -> Void = { _ in }) -> (TraktAccount, LibraryStore) {
        let defaults = UserDefaults(suiteName: "TraktAccountTests-\(id)")!
        let library = LibraryStore(defaults: defaults)
        library.record(movie, position: 600, duration: 6000, at: Date(timeIntervalSince1970: 1))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountTraktProtocol.self]
        configuration.httpAdditionalHeaders = ["fixture-account": id]
        let account = TraktAccount(
            library: library, addons: AddonStore(defaults: defaults), defaults: defaults,
            session: URLSession(configuration: configuration),
            credentials: TraktCredentials(clientID: id, clientSecret: "fixture"),
            token: TraktToken(accessToken: "fixture", refreshToken: "fixture",
                              expiresAt: expired ? .distantPast : .distantFuture), saveToken: save)
        return (account, library)
    }

    @Test func mergesKnownTitlesWithoutAnAddonMetadataRequest() async {
        let (account, library) = account()
        await account.pullProgress()
        #expect(library.progress[movie.id]?.position == 3000)
        #expect(library.progress[movie.id]?.item.title == "Saved movie")
        #expect(AccountTraktProtocol.count(id, path: "/sync/playback") == 1)
    }

    @Test func importsAnUnknownTitleThroughBuiltInMetadataWithNoInstalledAddons() async {
        let (account, library) = account()
        library.removeFromContinueWatching(metaID: movie.metaID)
        AccountTraktProtocol.configure(id, playback:
            #"[{"progress":50,"paused_at":"2026-11-04T08:00:00.000Z","type":"movie","movie":{"ids":{"imdb":"tt2"}}}]"#)
        await account.pullProgress()
        #expect(library.progress["tt2"]?.item.title == "Remote movie")
        #expect(library.progress["tt2"]?.fraction == 0.5)
        #expect(AccountTraktProtocol.count(id, path: "/meta/movie/tt2.json") == 1)
    }

    @Test func completedRemotePlayClearsContinueWatchingWithItsOriginalTimestamp() async {
        let (account, library) = account()
        AccountTraktProtocol.configure(id, playback: "[]", history:
            #"[{"watched_at":"2026-11-04T08:00:00.000Z","type":"movie","movie":{"ids":{"imdb":"tt1"}}}]"#)
        await account.pullProgress()
        #expect(library.continueWatching.isEmpty)
        #expect(library.progress[movie.id]?.isFinished == true)
        #expect(library.progress[movie.id]?.updatedAt == Date(timeIntervalSince1970: 1_793_779_200))
    }

    @Test func completedRemotePlayCannotOverwriteANewerLocalRewatch() async {
        let (account, library) = account()
        library.record(movie, position: 1200, duration: 6000, at: Date(timeIntervalSince1970: 1_793_865_600))
        AccountTraktProtocol.configure(id, playback: "[]", history:
            #"[{"watched_at":"2026-11-04T08:00:00.000Z","type":"movie","movie":{"ids":{"imdb":"tt1"}}}]"#)
        await account.pullProgress()
        #expect(library.progress[movie.id]?.position == 1200)
        #expect(library.continueWatching.count == 1)
    }

    @Test func completedEpisodeAndNextEpisodeProgressAgreeAfterSync() async {
        let (account, library) = account()
        library.removeFromContinueWatching(metaID: movie.metaID)
        let first = WatchItem(id: "ttshow:1:1", type: "series", metaID: "ttshow", title: "Remote show",
                              season: 1, episode: 1)
        library.record(first, position: 600, duration: 2700, at: Date(timeIntervalSince1970: 1))
        AccountTraktProtocol.configure(id, playback:
            #"[{"progress":40,"paused_at":"2026-11-04T09:00:00.000Z","type":"episode","show":{"ids":{"imdb":"ttshow"}},"episode":{"season":1,"number":2}}]"#,
            history: #"[{"watched_at":"2026-11-04T08:00:00.000Z","type":"episode","show":{"ids":{"imdb":"ttshow"}},"episode":{"season":1,"number":1}}]"#)
        await account.pullProgress()
        #expect(library.isWatched(first.id))
        #expect(library.continueWatching.map(\.item.id) == ["ttshow:1:2"])
        #expect(library.progress["ttshow:1:2"]?.fraction == 0.4)
    }

    @Test func watchedHistoryReadsEveryPage() async throws {
        let (account, library) = account()
        AccountTraktProtocol.configure(id, playback: "[]")
        AccountTraktProtocol.historyPages(id, pages: [
            #"[{"watched_at":"2026-11-04T08:00:00.000Z","type":"movie","movie":{"ids":{"imdb":"ttother"}}}]"#,
            #"[{"watched_at":"2026-11-04T08:00:00.000Z","type":"movie","movie":{"ids":{"imdb":"tt1"}}}]"#,
        ])
        await account.pullProgress()
        #expect(AccountTraktProtocol.count(id, path: "/sync/history") == 2)
        #expect(library.isWatched(movie.id))
    }

    @Test(arguments: [(85.0, "pause"), (92.0, "stop"), (93.0, "stop")])
    func stoppingUsesTheLibraryCompletionThreshold(_ progress: Double, _ action: String) async throws {
        let (account, _) = account()
        account.scrobble(.stop, movie, progress: progress)
        let path = "/scrobble/" + action
        try await waitForRequest(path)
        let other = action == "pause" ? "stop" : "pause"
        #expect(AccountTraktProtocol.count(id, path: "/scrobble/" + other) == 0)
    }

    @Test func overlappingPullsShareOneTokenRefresh() async throws {
        var saves: [TraktToken?] = []
        let (account, _) = account(expired: true, save: { saves.append($0) })
        AccountTraktProtocol.hold(id, path: "/oauth/token")
        let first = Task { await account.pullProgress() }
        try await waitForRequest("/oauth/token")
        let second = Task { await account.pullProgress() }
        // Give the second pull a chance to join the suspended refresh.
        for _ in 0..<20 { await Task.yield() }
        AccountTraktProtocol.release(id, path: "/oauth/token")
        await first.value
        await second.value
        #expect(AccountTraktProtocol.count(id, path: "/oauth/token") == 1)
        #expect(saves.count == 1)
        #expect(saves.compactMap { $0 }.map(\.accessToken) == ["refreshed"])
    }

    @Test func signOutCannotBeUndoneByAnOutstandingRefresh() async throws {
        var saves: [TraktToken?] = []
        let (account, library) = account(expired: true, save: { saves.append($0) })
        AccountTraktProtocol.hold(id, path: "/oauth/token")
        let pull = Task { await account.pullProgress() }
        try await waitForRequest("/oauth/token")
        account.signOut()
        AccountTraktProtocol.release(id, path: "/oauth/token")
        await pull.value
        #expect(account.state == .signedOut)
        #expect(saves.count == 1 && saves[0] == nil)
        #expect(AccountTraktProtocol.count(id, path: "/sync/playback") == 0)
        #expect(library.progress[movie.id]?.position == 600)
    }

    @Test func signOutDiscardsAnOutstandingProgressResponse() async throws {
        let (account, library) = account()
        AccountTraktProtocol.hold(id, path: "/sync/playback")
        let pull = Task { await account.pullProgress() }
        try await waitForRequest("/sync/playback")
        account.signOut()
        AccountTraktProtocol.release(id, path: "/sync/playback")
        await pull.value
        #expect(library.progress[movie.id]?.position == 600)
    }

    @Test func accountProfileDoesNotImportOrExportTheDevicesTraktAccount() async throws {
        let (account, library) = account()
        library.activateProfile(id: "separate-person")
        await account.pullProgress()
        account.scrobble(.pause, movie, progress: 50)
        account.markWatched([movie])
        await Task.yield()
        #expect(library.progress.isEmpty)
        #expect(AccountTraktProtocol.count(id, path: "/sync/playback") == 0)
        #expect(AccountTraktProtocol.count(id, path: "/scrobble/pause") == 0)
        #expect(AccountTraktProtocol.count(id, path: "/sync/history") == 0)
        library.activateProfile(id: nil)
        #expect(library.progress[movie.id]?.position == 600)
    }

    @Test func profileSwitchDiscardsAnOutstandingTraktImport() async throws {
        let (account, library) = account()
        AccountTraktProtocol.hold(id, path: "/sync/playback")
        let pull = Task { await account.pullProgress() }
        try await waitForRequest("/sync/playback")
        library.activateProfile(id: "separate-person")
        AccountTraktProtocol.release(id, path: "/sync/playback")
        await pull.value
        #expect(library.progress.isEmpty)
        library.activateProfile(id: nil)
        #expect(library.progress[movie.id]?.position == 600)
    }

    private func waitForRequest(_ path: String) async throws {
        let deadline = Date.now.addingTimeInterval(5)
        while AccountTraktProtocol.count(id, path: path) == 0, Date.now < deadline {
            await Task.yield()
        }
        try #require(AccountTraktProtocol.count(id, path: path) > 0)
    }
}

private final class AccountTraktProtocol: StubURLProtocol, @unchecked Sendable {
    private struct Requests {
        var counts: [String: Int] = [:]
        var playback: [String: String] = [:]
        var history: [String: [String]] = [:]
        var holds: Set<String> = []
        var responses: [String: @Sendable () -> Void] = [:]
    }
    private static let requests = Mutex(Requests())

    static func configure(_ id: String, playback: String, history: String = "[]") {
        requests.withLock {
            $0.playback[id] = playback
            $0.history[id] = [history]
        }
    }

    static func historyPages(_ id: String, pages: [String]) {
        requests.withLock { $0.history[id] = pages }
    }

    static func hold(_ id: String, path: String) {
        _ = requests.withLock { $0.holds.insert(id + path) }
    }

    static func release(_ id: String, path: String) {
        let response = requests.withLock { $0.responses.removeValue(forKey: id + path) }
        response?()
    }

    static func count(_ id: String, path: String) -> Int {
        requests.withLock { $0.counts[id + path] ?? 0 }
    }

    override func startLoading() {
        let key = (request.value(forHTTPHeaderField: "trakt-api-key") ?? request.value(forHTTPHeaderField: "fixture-account") ?? "") + (request.url?.path ?? "")
        let held = Self.requests.withLock { requests in
            if requests.holds.contains(key) {
                requests.responses[key] = { @Sendable [weak self] in self?.respond() }
            }
            requests.counts[key, default: 0] += 1
            return requests.holds.contains(key)
        }
        if !held { respond() }
    }

    private func respond() {
        guard let url = request.url else { return }
        let id = request.value(forHTTPHeaderField: "trakt-api-key") ?? request.value(forHTTPHeaderField: "fixture-account") ?? ""
        let histories = Self.requests.withLock { $0.history[id] ?? ["[]"] }
        let headers = url.path == "/sync/history" ? ["X-Pagination-Page-Count": String(histories.count)] : [:]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers) else { return }
        let body: String
        switch url.path {
        case "/oauth/token":
            body = #"{"access_token":"refreshed","refresh_token":"next","expires_in":9999999999,"created_at":1790000000}"#
        case "/sync/history":
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "page" }?.value.flatMap(Int.init) ?? 1
            body = histories.indices.contains(page - 1) ? histories[page - 1] : "[]"
        case "/meta/series/ttshow.json":
            body = #"{"meta":{"id":"ttshow","type":"series","name":"Remote show","runtime":"45 min","videos":[{"id":"ttshow:1:2","season":1,"episode":2}]}}"#
        case "/meta/movie/tt2.json":
            body = #"{"meta":{"id":"tt2","type":"movie","name":"Remote movie","runtime":"100 min"}}"#
        default:
            body = Self.requests.withLock { $0.playback[id] }
                ?? #"[{"progress":50,"paused_at":"2026-11-04T08:00:00.000Z","type":"movie","movie":{"ids":{"imdb":"tt1"}}}]"#
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

}
