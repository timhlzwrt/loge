import Foundation
import Network
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
    /// From asking for a code until signed in, cancelled or failed.
    public private(set) var isSigningIn = false
    /// Why the last sign-in failed. Kept here rather than in the page, which may have closed meanwhile.
    public private(set) var signInError: (any Error)?
    /// The app keys couldn't be written to Keychain, so they last only until the app quits.
    public private(set) var credentialsNotSaved = false
    /// Whether the last pull couldn't reach Trakt.
    public private(set) var pullFailed = false
    public var isPulling: Bool { pulls > 0 }
    /// Sign-out drops these, so the confirmation says so.
    public var hasUnsentChanges: Bool { !pending.isEmpty }

    private var token: TraktToken?
    private let library: LibraryStore
    private let addons: AddonStore
    private let defaults: UserDefaults
    private let session: URLSession
    private let saveToken: (TraktToken?) -> Void
    private var connectionID = UUID()
    private var refreshTask: Task<TraktToken, Error>?
    /// What this device hasn't managed to tell Trakt yet, oldest first.
    private var pending: [TraktChange]
    /// The progress Trakt listed at the last pull, to notice what has been removed since.
    private var listed: [String: Date]
    private var sending: Task<Void, Never>?
    private var pulls = 0
    private var connectionMonitor: NWPathMonitor?
    /// Trakt allows one write a second per user.
    var writeInterval = Duration.seconds(1)

    private static let service = "li.tjh.MediaApp.trakt"
    private static let usernameKey = "traktUsername"
    private static let pendingKey = "traktPendingChanges"
    private static let listedKey = "traktListedProgress"
    private static let maximumPending = 500
    /// Trakt keeps paused progress for six months, so older entries leave its list by themselves.
    private static let progressLifetime: TimeInterval = 180 * 24 * 60 * 60

    public convenience init(library: LibraryStore, addons: AddonStore, defaults: UserDefaults = .standard) {
        self.init(library: library, addons: addons, defaults: defaults, session: .shared,
                  credentials: Self.load(TraktCredentials.self, account: "credentials"),
                  token: Self.load(TraktToken.self, account: "token"),
                  // A token that isn't kept only means signing in again; `save` logs the failure.
                  saveToken: { try? Self.save($0, account: "token") })
    }

    #if DEBUG
    /// UI checks show a state, such as the sign-in code, without Keychain or network.
    public convenience init(library: LibraryStore, addons: AddonStore, defaults: UserDefaults, showing state: State) {
        self.init(library: library, addons: addons, defaults: defaults, session: .shared,
                  credentials: TraktCredentials(clientID: "ui-fixture", clientSecret: "ui-fixture"),
                  token: nil, saveToken: { _ in })
        self.state = state
    }
    #endif

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
        pending = Self.decode(defaults.data(forKey: Self.pendingKey)) ?? []
        listed = Self.decode(defaults.data(forKey: Self.listedKey)) ?? [:]
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
        do {
            try Self.save(credentials, account: "credentials")
            credentialsNotSaved = false
        } catch {
            credentialsNotSaved = true
        }
        signOut()
    }

    // MARK: Sign-in

    /// Shows a code for the user to enter on Trakt's site, then waits for their approval.
    /// A second call while one is in progress returns at once.
    public func signIn() async throws {
        guard let client else { throw TraktError.notSignedIn }
        guard !isSigningIn else { return }
        let connectionID = connectionID
        isSigningIn = true
        signInError = nil
        defer { if self.connectionID == connectionID { isSigningIn = false } }
        do {
            let code = try await client.deviceCode()
            try checkConnection(connectionID)
            state = .awaitingApproval(code)
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
            if self.connectionID == connectionID {
                if case .awaitingApproval = state { state = .signedOut }
                if !(error is CancellationError) { signInError = error }
            }
            throw error
        }
    }

    /// Ends a sign-in in progress; its polling stops at the next check.
    public func cancelSignIn() {
        guard isSigningIn else { return }
        connectionID = UUID()
        isSigningIn = false
        if case .awaitingApproval = state { state = .signedOut }
    }

    public func signOut() {
        connectionID = UUID()
        isSigningIn = false
        pullFailed = false
        refreshTask?.cancel()
        refreshTask = nil
        token = nil
        saveToken(nil)
        defaults.removeObject(forKey: Self.usernameKey)
        // They belong to the account signed out of, and the next may be someone else's.
        pending = []
        defaults.removeObject(forKey: Self.pendingKey)
        listed = [:]
        defaults.removeObject(forKey: Self.listedKey)
        state = .signedOut
    }

    // MARK: Sync

    /// - Parameter progress: 0–100.
    public func scrobble(_ action: TraktClient.ScrobbleAction, _ item: WatchItem, progress: Double) {
        // Trakt completes a stop at 80%; keep partially watched items consistent
        // with the library's later credits threshold instead.
        let action = action == .stop && progress < LibraryStore.finishedFraction * 100 ? .pause : action
        switch action {
        case .start:
            // Starting removes the paused progress, which isn't someone removing the title.
            listed[Self.listedKey(item)] = nil
            saveListed()
            sendStart(item, progress: progress)
        case .pause: record([TraktChange(item: item, action: .progress(progress))])
        case .stop: record([TraktChange(item: item, action: .finished(progress))])
        }
    }

    /// Keeps the position for the next send without sending it. After `start` Trakt holds no
    /// progress for the item, so a device that's killed mid-playback would otherwise lose it there.
    public func keepProgress(_ item: WatchItem, progress: Double) {
        record([TraktChange(item: item, action: .progress(progress))], send: false)
    }

    public func markWatched(_ items: [WatchItem]) {
        let date = Date.now
        record(items.map { TraktChange(item: $0, action: .watched, date: date) })
    }

    public func markUnwatched(_ items: [WatchItem]) {
        record(items.flatMap { [TraktChange(item: $0, action: .unwatched), TraktChange(item: $0, action: .removed)] })
    }

    /// Clears the title's paused progress, every episode of a series, so other devices drop it too.
    public func removeFromContinueWatching(_ item: WatchItem) {
        record([TraktChange(item: item, action: .removedTitle)])
    }

    /// Sends what's waiting, oldest first. A call made while another runs waits for that one,
    /// which also sends anything added in the meantime.
    public func sendPending() async {
        if let sending {
            await sending.value
            return
        }
        guard !pending.isEmpty else { return }
        let task = Task { await drainPending() }
        sending = task
        await task.value
        sending = nil
    }

    /// Sends what's waiting as soon as the device gets a connection back.
    public func sendPendingOnReconnect() {
        guard connectionMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in await self?.sendPending() }
        }
        monitor.start(queue: .global(qos: .utility))
        connectionMonitor = monitor
    }

    /// Brings in progress from other devices. Titles not yet in the library are looked up
    /// through the installed addons for their names, artwork and runtime.
    public func pullProgress() async {
        guard !isPaused, let client else { return }
        pulls += 1
        defer { pulls -= 1 }
        // First, so what this device removed or played while offline counts in what comes back.
        await sendPending()
        guard !isPaused else { return }
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
            if self.connectionID == connectionID { pullFailed = true }
            signOutIfRejected(error, connectionID: connectionID)
            return
        }
        guard !isPaused, self.connectionID == connectionID, !Task.isCancelled else { return }
        pullFailed = false
        var metas: [String: Meta] = [:]
        var attemptedIDs: Set<String> = []
        // Titles already in the library merge together, with one save.
        var known: [LibraryStore.RemoteProgress] = []
        // A completed play disappears from Trakt's paused playback feed. Merge its
        // actual timestamp so it clears stale progress without undoing a newer rewatch.
        for entry in watched {
            guard let saved = library.progress.values.first(where: {
                $0.item.metaID == entry.imdbID && $0.item.season == entry.season && $0.item.episode == entry.episode
            }) else { continue }
            known.append(.init(item: saved.item, fraction: 1, estimatedDuration: max(saved.duration, 1), date: entry.pausedAt))
        }
        var unknown: [TraktPlayback] = []
        for entry in entries {
            let type = entry.season == nil ? MediaType.movie : MediaType.series
            if let saved = library.progress.values.first(where: {
                $0.item.metaID == entry.imdbID && $0.item.season == entry.season && $0.item.episode == entry.episode
            }) {
                // Marking something watched without playing it stores a placeholder duration of 1.
                known.append(.init(item: saved.item, fraction: entry.progress / 100,
                                   estimatedDuration: saved.duration > 1 ? saved.duration : (type == MediaType.movie ? 6_600 : 2_700),
                                   date: entry.pausedAt))
            } else {
                unknown.append(entry)
            }
        }
        library.mergeRemote(known)
        for entry in unknown {
            let type = entry.season == nil ? MediaType.movie : MediaType.series
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
        await dropProgressRemovedElsewhere(listedNow: entries, client: client, connectionID: connectionID)
    }

    /// Trakt not listing something proves nothing by itself: this device may never have told it.
    /// Progress it did list and has since dropped was removed on another device, or started there.
    private func dropProgressRemovedElsewhere(listedNow entries: [TraktPlayback], client: TraktClient, connectionID: UUID) async {
        var current: [String: Date] = [:]
        for entry in entries {
            if let saved = savedProgress(for: entry) { current[Self.listedKey(saved.item)] = entry.pausedAt }
        }
        let cutoff = Date.now.addingTimeInterval(-Self.progressLifetime)
        var gone = listed.filter { key, pausedAt in current[key] == nil && pausedAt > cutoff }.compactMap { key, pausedAt in
            library.progress.first { Self.listedKey($0.value.item) == key }
                // Played here since, or waiting to be sent: this device's position stands.
                .flatMap { id, saved in
                    !saved.isFinished && saved.updatedAt <= pausedAt && !pending.contains { $0.item.id == id }
                        ? (item: saved.item, pausedAt: pausedAt) : nil
                }
        }
        var watching: TraktPlayback?
        if !gone.isEmpty {
            do {
                watching = try await client.watching(token: try await validToken())
                try checkConnection(connectionID)
            } catch {
                // Judged again at the next pull, so nothing is removed on a guess.
                log.error("Couldn't check what's playing on Trakt: \(error)")
                return
            }
            guard !isPaused else { return }
        }
        if let watching, let playing = gone.first(where: { watching.matches($0.item) }) {
            // It may yet be paused or finished; until then it's still in progress.
            current[Self.listedKey(playing.item)] = playing.pausedAt
            gone.removeAll { $0.item.id == playing.item.id }
        }
        for entry in gone {
            // Dated by the progress it replaces, so any newer pause brings the title back.
            library.markUnwatched([entry.item.id], at: entry.pausedAt)
        }
        listed = current
        saveListed()
    }

    private func savedProgress(for entry: TraktPlayback) -> WatchProgress? {
        library.progress.values.first { entry.matches($0.item) }
    }

    // MARK: Sending

    private func record(_ changes: [TraktChange], send: Bool = true) {
        guard !isPaused, credentials != nil, token != nil else { return }
        for change in changes where change.canReachTrakt {
            pending.removeAll { change.replaces($0) }
            pending.append(change)
        }
        pending = pending.suffix(Self.maximumPending)
        savePending()
        if send { Task { await sendPending() } }
    }

    private func drainPending() async {
        guard let client else { return }
        let connectionID = connectionID
        // Fetched at most once a pass, and only when a change needs it.
        var remote: [TraktPlayback]?
        do {
            while !isPaused, let change = pending.first {
                let token = try await validToken()
                try checkConnection(connectionID)
                if change.needsRemoteState, remote == nil {
                    remote = try await client.playback(token: token)
                    try checkConnection(connectionID)
                }
                let batch = pending.filter { change.isSentWith($0) }
                do {
                    try await send(batch, remote: remote ?? [], client: client, token: token)
                } catch TraktError.httpStatus(let status) where Self.permanentFailures.contains(status) {
                    // Trying again can't help, and it would hold up everything behind it.
                    log.error("Trakt refused a change with status \(status)")
                }
                try checkConnection(connectionID)
                pending.removeAll { batch.contains($0) }
                savePending()
                if !pending.isEmpty { try await Task.sleep(for: writeInterval) }
            }
        } catch is CancellationError {
            return
        } catch {
            // The changes stay saved for the next attempt.
            log.error("Couldn't send changes to Trakt: \(error)")
            signOutIfRejected(error, connectionID: connectionID)
        }
    }

    /// Unknown title, already scrobbled and the like. Limits, outages and locked accounts pass in time.
    private static let permanentFailures: Set<Int> = [400, 404, 405, 409, 412, 420, 422]

    private func send(_ batch: [TraktChange], remote: [TraktPlayback], client: TraktClient, token: TraktToken) async throws {
        guard let change = batch.first else { return }
        switch change.action {
        case .progress(let progress):
            // Trakt dates a pause when it arrives, so an old one would overwrite newer progress.
            if remote.contains(where: { $0.matches(change.item) && $0.pausedAt > change.date }) { return }
            try await client.scrobble(.pause, change.item, progress: progress, token: token)
        case .finished(let progress):
            if change.isFresh {
                try await client.scrobble(.stop, change.item, progress: progress, token: token)
            } else {
                // A scrobble would count as watched now.
                try await client.addToHistory([change.item], watchedAt: change.date, token: token)
            }
        case .watched:
            try await client.addToHistory(batch.map(\.item), watchedAt: change.date, token: token)
        case .unwatched:
            try await client.removeFromHistory(batch.map(\.item), token: token)
        case .removed, .removedTitle:
            let targets = remote.filter { entry in
                let isCovered = change.action == .removedTitle ? entry.imdbID == change.item.metaID : entry.matches(change.item)
                // Played elsewhere since the removal: that's the newer intent.
                return isCovered && entry.pausedAt <= change.date
            }
            for (index, id) in targets.compactMap(\.id).enumerated() {
                if index > 0 { try await Task.sleep(for: writeInterval) }
                try await client.removePlayback(id: id, token: token)
            }
        }
    }

    private func savePending() {
        save(pending, forKey: Self.pendingKey)
    }

    private func saveListed() {
        save(listed, forKey: Self.listedKey)
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
            log.error("Couldn't read saved Trakt changes: \(error)")
            return nil
        }
    }

    private static func listedKey(_ item: WatchItem) -> String {
        "\(item.type)/\(item.id)"
    }

    // MARK: Helpers

    /// Not kept for later: "started watching" means nothing once the moment has passed.
    private func sendStart(_ item: WatchItem, progress: Double) {
        guard !isPaused, let client, token != nil else { return }
        let connectionID = connectionID
        Task {
            do {
                guard !isPaused else { return }
                let token = try await validToken()
                try checkConnection(connectionID)
                guard !isPaused else { return }
                try await client.scrobble(.start, item, progress: progress, token: token)
            } catch is CancellationError {
                return
            } catch {
                log.error("Couldn't send scrobble to Trakt: \(error)")
                signOutIfRejected(error, connectionID: connectionID)
            }
        }
    }

    /// A token revoked on Trakt's site never comes up for refresh, so without this the device
    /// would go on showing as signed in while nothing syncs.
    private func signOutIfRejected(_ error: Error, connectionID: UUID) {
        if error as? TraktError == .httpStatus(401), self.connectionID == connectionID { signOut() }
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

    // A token or keys that can't be read mean signing in again, so read failures are logged
    // rather than shown. Saving the app keys reports failure through `credentialsNotSaved`.
    private static func load<T: Decodable>(_ type: T.Type, account: String) -> T? {
        do {
            guard let data = try Keychain.read(service: service, account: account) else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            log.error("Couldn't read Trakt \(account, privacy: .public) from the keychain: \(error)")
            return nil
        }
    }

    private static func save<T: Encodable>(_ value: T?, account: String) throws {
        do {
            if let value { try Keychain.save(JSONEncoder().encode(value), service: service, account: account) }
            else { try Keychain.remove(service: service, account: account) }
        } catch {
            log.error("Couldn't save Trakt \(account, privacy: .public) to the keychain: \(error)")
            throw error
        }
    }
}
