import Foundation
import Observation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "trakt")

/// The Trakt account this device is signed in to. Reports what's watched here and brings
/// progress from other devices into the library, so playback continues where it stopped.
@MainActor @Observable
public final class TraktAccount {
    public enum State: Equatable, Sendable {
        case signedOut
        /// Waiting for the user to enter the code on Trakt's site.
        case awaitingApproval(TraktDeviceCode)
        case signedIn(username: String)
    }

    public private(set) var state: State = .signedOut
    public private(set) var credentials: TraktCredentials?

    private var token: TraktToken?
    private let library: LibraryStore
    private let addons: AddonStore
    private let defaults: UserDefaults
    private let session: URLSession
    private let saveToken: (TraktToken?) -> Void
    private var connectionID = UUID()
    private var refreshTask: Task<TraktToken, Error>?

    private static let service = "li.tjh.MediaApp.trakt"
    private static let usernameKey = "traktUsername"

    public convenience init(library: LibraryStore, addons: AddonStore, defaults: UserDefaults = .standard) {
        self.init(library: library, addons: addons, defaults: defaults, session: .shared,
                  credentials: Self.load(TraktCredentials.self, account: "credentials"),
                  token: Self.load(TraktToken.self, account: "token"),
                  saveToken: { Self.save($0, account: "token") })
    }

    init(library: LibraryStore, addons: AddonStore, defaults: UserDefaults,
         session: URLSession, credentials: TraktCredentials?, token: TraktToken?,
         saveToken: @escaping (TraktToken?) -> Void) {
        self.library = library
        self.addons = addons
        self.defaults = defaults
        self.session = session
        self.credentials = credentials
        self.token = token
        self.saveToken = saveToken
        if token != nil, let username = defaults.string(forKey: Self.usernameKey) {
            state = .signedIn(username: username)
        }
    }

    /// Trakt belongs to this device's own library. While a sync account's library is active,
    /// that account carries playback progress, so Trakt neither imports nor reports it.
    public var isPaused: Bool { library.activeProfileID != nil }

    private var client: TraktClient? { credentials.map { TraktClient(credentials: $0, session: session) } }

    /// Changing the app the device signs in with also signs it out.
    public func setCredentials(_ credentials: TraktCredentials?) {
        guard credentials != self.credentials else { return }
        self.credentials = credentials
        Self.save(credentials, account: "credentials")
        signOut()
    }

    // MARK: Sign-in

    /// Shows a code for the user to enter on Trakt's site, then waits for their approval.
    public func signIn() async throws {
        guard let client else { throw TraktError.notSignedIn }
        let connectionID = connectionID
        let code = try await client.deviceCode()
        try checkConnection(connectionID)
        state = .awaitingApproval(code)
        do {
            while Date.now < code.expiresAt {
                try await Task.sleep(for: .seconds(code.interval))
                try checkConnection(connectionID)
                guard let token = try await client.token(for: code) else { continue }
                try checkConnection(connectionID)
                let username = try await client.username(token: token)
                try checkConnection(connectionID)
                self.token = token
                saveToken(token)
                defaults.set(username, forKey: Self.usernameKey)
                state = .signedIn(username: username)
                await pullProgress()
                return
            }
            throw TraktError.codeExpired
        } catch {
            if self.connectionID == connectionID, case .awaitingApproval = state { state = .signedOut }
            throw error
        }
    }

    public func signOut() {
        connectionID = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        token = nil
        saveToken(nil)
        defaults.removeObject(forKey: Self.usernameKey)
        state = .signedOut
    }

    // MARK: Sync

    /// - Parameter progress: 0–100.
    public func scrobble(_ action: TraktClient.ScrobbleAction, _ item: WatchItem, progress: Double) {
        // Trakt completes a stop at 80%; keep partially watched items consistent
        // with the library's later credits threshold instead.
        let action = action == .stop && progress < LibraryStore.finishedFraction * 100 ? .pause : action
        send("scrobble") { client, token in try await client.scrobble(action, item, progress: progress, token: token) }
    }

    public func markWatched(_ items: [WatchItem]) {
        send("history") { client, token in try await client.addToHistory(items, token: token) }
    }

    public func markUnwatched(_ items: [WatchItem]) {
        send("history") { client, token in try await client.removeFromHistory(items, token: token) }
    }

    /// Brings in progress from other devices. Titles not yet in the library are looked up
    /// through the installed addons for their names, artwork and runtime.
    public func pullProgress() async {
        guard !isPaused, let client else { return }
        let connectionID = connectionID
        let entries: [TraktPlayback]
        let historySince = library.progress.values.filter { !$0.isFinished }.map(\.updatedAt).min()
        var watched: [TraktPlayback] = []
        do {
            let token = try await validToken()
            try checkConnection(connectionID)
            entries = try await client.playback(token: token)
            try checkConnection(connectionID)
            if let historySince {
                do {
                    watched = try await client.watchedHistory(since: historySince, token: token)
                    try checkConnection(connectionID)
                } catch is CancellationError {
                    return
                } catch {
                    log.error("Couldn't load watched history: \(error)")
                }
            }
        } catch is CancellationError {
            return
        } catch TraktError.notSignedIn {
            return
        } catch {
            log.error("Couldn't load playback progress: \(error)")
            return
        }
        guard !isPaused, self.connectionID == connectionID, !Task.isCancelled else { return }
        var metas: [String: Meta] = [:]
        var attemptedIDs: Set<String> = []
        // A completed play disappears from Trakt's paused playback feed. Merge its
        // actual timestamp so it clears stale progress without undoing a newer rewatch.
        for entry in watched {
            guard let saved = library.progress.values.first(where: {
                $0.item.metaID == entry.imdbID && $0.item.season == entry.season && $0.item.episode == entry.episode
            }) else { continue }
            library.mergeRemote(saved.item, fraction: 1, estimatedDuration: max(saved.duration, 1), at: entry.pausedAt)
        }
        for entry in entries {
            let type = entry.season == nil ? MediaType.movie : MediaType.series
            if let saved = library.progress.values.first(where: {
                $0.item.metaID == entry.imdbID && $0.item.season == entry.season && $0.item.episode == entry.episode
            }) {
                library.mergeRemote(saved.item, fraction: entry.progress / 100,
                                    estimatedDuration: saved.duration > 0 ? saved.duration : (type == MediaType.movie ? 6_600 : 2_700),
                                    at: entry.pausedAt)
                continue
            }
            // Several paused episodes can share a show; unavailable metadata should only be requested once per sync.
            if attemptedIDs.insert(entry.imdbID).inserted,
               let provider = addons.addons.metaClient(type: type, id: entry.imdbID),
               let meta = try? await AddonClient(manifestURL: provider.manifestURL, session: session)
                .meta(type: type, id: entry.imdbID) {
                metas[entry.imdbID] = meta
            }
            guard !isPaused, self.connectionID == connectionID, !Task.isCancelled else { return }
            guard let meta = metas[entry.imdbID], let item = Self.item(for: entry, in: meta) else { continue }
            // Without a runtime, a typical length stands in until the file is played here.
            let minutes = Self.minutes(meta.runtime) ?? (type == MediaType.movie ? 110 : 45)
            library.mergeRemote(item, fraction: entry.progress / 100, estimatedDuration: minutes * 60, at: entry.pausedAt)
        }
    }

    // MARK: Helpers

    /// Runs a request in the background; Trakt being unreachable shouldn't disturb playback.
    private func send(_ what: String, _ request: @escaping @Sendable (TraktClient, TraktToken) async throws -> Void) {
        guard !isPaused, let client, token != nil else { return }
        let connectionID = connectionID
        Task {
            do {
                guard !isPaused else { return }
                let token = try await validToken()
                try checkConnection(connectionID)
                guard !isPaused else { return }
                try await request(client, token)
            } catch is CancellationError {
                return
            } catch {
                log.error("Couldn't send \(what, privacy: .public) to Trakt: \(error)")
            }
        }
    }

    private func checkConnection(_ id: UUID) throws {
        try Task.checkCancellation()
        guard connectionID == id else { throw CancellationError() }
    }

    private func validToken() async throws -> TraktToken {
        guard let client, let token else { throw TraktError.notSignedIn }
        guard token.needsRefresh else { return token }
        let connectionID = connectionID
        let task: Task<TraktToken, Error>
        if let refreshTask {
            task = refreshTask
        } else {
            task = Task { try await client.refresh(token) }
            refreshTask = task
        }
        do {
            let refreshed = try await task.value
            try checkConnection(connectionID)
            // Every waiter uses the same refreshed token; only the first persists it.
            if self.token == token {
                self.token = refreshed
                saveToken(refreshed)
            }
            refreshTask = nil
            return refreshed
        } catch {
            guard self.connectionID == connectionID else { throw CancellationError() }
            refreshTask = nil
            if error as? TraktError == .httpStatus(401) {
                signOut()
                throw TraktError.notSignedIn
            }
            throw error
        }
    }

    static func item(for entry: TraktPlayback, in meta: Meta) -> WatchItem? {
        let video = entry.season.flatMap { season in
            meta.videos?.first { $0.season == season && $0.episode == entry.episode }
        }
        if entry.season != nil && video == nil { return nil }
        return WatchItem(
            id: video?.id ?? meta.id, type: meta.type, metaID: meta.id, title: meta.name,
            season: video?.season, episode: video?.episode, episodeTitle: video?.displayTitle,
            poster: meta.poster, background: meta.background, thumbnail: video?.thumbnail)
    }

    /// Minutes in a runtime such as "45 min" or "2h 16min".
    public static func minutes(_ runtime: String?) -> Double? {
        guard let runtime else { return nil }
        let hours = runtime.firstMatch(of: /(\d+)\s*h/).flatMap { Double($0.1) } ?? 0
        let minutes = runtime.firstMatch(of: /(\d+)\s*min/).flatMap { Double($0.1) } ?? 0
        let total = hours * 60 + minutes
        return total > 0 ? total : nil
    }

    // Trakt has no screen for storage failures: a token that can't be read means signing in
    // again, so failures are logged rather than shown.
    private static func load<T: Decodable>(_ type: T.Type, account: String) -> T? {
        do {
            guard let data = try Keychain.read(service: service, account: account) else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            log.error("Couldn't read Trakt \(account, privacy: .public) from the keychain: \(error)")
            return nil
        }
    }

    private static func save<T: Encodable>(_ value: T?, account: String) {
        do {
            if let value { try Keychain.save(JSONEncoder().encode(value), service: service, account: account) }
            else { try Keychain.remove(service: service, account: account) }
        } catch {
            log.error("Couldn't save Trakt \(account, privacy: .public) to the keychain: \(error)")
        }
    }
}
