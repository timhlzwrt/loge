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

    private static let service = "li.tjh.MediaApp.trakt"
    private static let usernameKey = "traktUsername"

    public init(library: LibraryStore, addons: AddonStore, defaults: UserDefaults = .standard) {
        self.library = library
        self.addons = addons
        self.defaults = defaults
        credentials = Self.load(TraktCredentials.self, account: "credentials")
        token = Self.load(TraktToken.self, account: "token")
        if token != nil, let username = defaults.string(forKey: Self.usernameKey) {
            state = .signedIn(username: username)
        }
    }

    private var client: TraktClient? { credentials.map { TraktClient(credentials: $0) } }

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
        let code = try await client.deviceCode()
        state = .awaitingApproval(code)
        do {
            while Date.now < code.expiresAt {
                try await Task.sleep(for: .seconds(code.interval))
                guard let token = try await client.token(for: code) else { continue }
                let username = try await client.username(token: token)
                self.token = token
                Self.save(token, account: "token")
                defaults.set(username, forKey: Self.usernameKey)
                state = .signedIn(username: username)
                await pullProgress()
                return
            }
            throw TraktError.codeExpired
        } catch {
            if case .awaitingApproval = state { state = .signedOut }
            throw error
        }
    }

    public func signOut() {
        token = nil
        Self.save(TraktToken?.none, account: "token")
        defaults.removeObject(forKey: Self.usernameKey)
        state = .signedOut
    }

    // MARK: Sync

    /// - Parameter progress: 0–100.
    public func scrobble(_ action: TraktClient.ScrobbleAction, _ item: WatchItem, progress: Double) {
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
        guard let client, let token = try? await validToken() else { return }
        let entries: [TraktPlayback]
        do {
            entries = try await client.playback(token: token)
        } catch {
            log.error("Couldn't load playback progress: \(error)")
            return
        }
        var metas: [String: Meta] = [:]
        var attemptedIDs: Set<String> = []
        for entry in entries {
            let type = entry.season == nil ? "movie" : "series"
            // Several paused episodes can share a show; unavailable metadata should only be requested once per sync.
            if attemptedIDs.insert(entry.imdbID).inserted,
               let meta = try? await addons.addons.metaClient(type: type, id: entry.imdbID)?
                .meta(type: type, id: entry.imdbID) {
                metas[entry.imdbID] = meta
            }
            guard let meta = metas[entry.imdbID], let item = Self.item(for: entry, in: meta) else { continue }
            // Without a runtime, a typical length stands in until the file is played here.
            let minutes = Self.minutes(meta.runtime) ?? (type == "movie" ? 110 : 45)
            library.mergeRemote(item, fraction: entry.progress / 100, estimatedDuration: minutes * 60, at: entry.pausedAt)
        }
    }

    // MARK: Helpers

    /// Runs a request in the background; Trakt being unreachable shouldn't disturb playback.
    private func send(_ what: String, _ request: @escaping @Sendable (TraktClient, TraktToken) async throws -> Void) {
        guard let client, token != nil else { return }
        Task {
            do {
                try await request(client, try await validToken())
            } catch {
                log.error("Couldn't send \(what, privacy: .public) to Trakt: \(error)")
            }
        }
    }

    private func validToken() async throws -> TraktToken {
        guard let client, let token else { throw TraktError.notSignedIn }
        guard token.needsRefresh else { return token }
        do {
            let refreshed = try await client.refresh(token)
            self.token = refreshed
            Self.save(refreshed, account: "token")
            return refreshed
        } catch TraktError.httpStatus(401) {
            // The refresh token was revoked, e.g. from Trakt's connected apps page.
            signOut()
            throw TraktError.notSignedIn
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
    static func minutes(_ runtime: String?) -> Double? {
        guard let runtime else { return nil }
        let hours = runtime.firstMatch(of: /(\d+)\s*h/).flatMap { Double($0.1) } ?? 0
        let minutes = runtime.firstMatch(of: /(\d+)\s*min/).flatMap { Double($0.1) } ?? 0
        let total = hours * 60 + minutes
        return total > 0 ? total : nil
    }

    private static func load<T: Decodable>(_ type: T.Type, account: String) -> T? {
        guard let data = Keychain.data(for: account, service: service) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T?, account: String) {
        Keychain.set(value.flatMap { try? JSONEncoder().encode($0) }, for: account, service: service)
    }
}
