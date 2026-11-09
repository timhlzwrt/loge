import Foundation

/// The app registered on trakt.tv/oauth/applications. Kept out of the repository; the user
/// enters it in Settings.
public struct TraktCredentials: Codable, Sendable, Equatable {
    public var clientID: String
    public var clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

public struct TraktToken: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    /// Refreshed a day early so a request never races the expiry.
    public var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 24 * 60 * 60 }
}

/// What the user types at trakt.tv/activate to sign this device in.
public struct TraktDeviceCode: Sendable, Equatable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURL: String
    public var expiresAt: Date
    /// Seconds to wait between checks for the user's approval.
    public var interval: Int
}

/// Progress Trakt holds for something started on any device.
public struct TraktPlayback: Sendable, Equatable {
    public var imdbID: String
    public var season: Int?
    public var episode: Int?
    /// 0–100.
    public var progress: Double
    public var pausedAt: Date
    /// What removing this progress takes; history entries have none.
    public var id: Int?

    /// The same title and episode, whichever IDs the two sides know it by.
    func matches(_ item: WatchItem) -> Bool {
        imdbID == item.metaID && season == item.season && episode == item.episode
    }
}

public enum TraktError: Error, Equatable {
    case notSignedIn
    /// The device code ran out or was declined before the user approved it.
    case codeExpired
    case denied
    case httpStatus(Int)
    /// Trakt couldn't be reached; the code says why, such as no connection.
    case unavailable(URLError.Code)
    /// Trakt answered with something other than the expected JSON.
    case invalidResponse
}

/// Talks to the Trakt API: device sign-in, scrobbling, history and playback progress.
public struct TraktClient: Sendable {
    public enum ScrobbleAction: String, Sendable { case start, pause, stop }

    static let baseURL = URL(string: "https://api.trakt.tv")!
    public let credentials: TraktCredentials
    private let session: URLSession

    public init(credentials: TraktCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: Sign-in

    public func deviceCode() async throws -> TraktDeviceCode {
        struct Response: Decodable {
            var device_code: String
            var user_code: String
            var verification_url: String
            var expires_in: Int
            var interval: Int
        }
        struct Request: Encodable { let client_id: String }
        let response: Response = try await send("oauth/device/code", body: Request(client_id: credentials.clientID))
        return TraktDeviceCode(
            deviceCode: response.device_code, userCode: response.user_code,
            verificationURL: response.verification_url,
            expiresAt: .now.addingTimeInterval(TimeInterval(response.expires_in)),
            interval: response.interval)
    }

    /// The token once the user has approved the code, or nil while they haven't yet.
    public func token(for code: TraktDeviceCode) async throws -> TraktToken? {
        do {
            struct Request: Encodable { let code: String; let client_id: String; let client_secret: String }
            let response: TokenResponse = try await send("oauth/device/token", body: Request(
                code: code.deviceCode, client_id: credentials.clientID, client_secret: credentials.clientSecret))
            return response.token
        } catch TraktError.httpStatus(let status) {
            switch status {
            case 400, 429: return nil // Still waiting, or asked to slow down.
            case 404, 409, 410: throw TraktError.codeExpired
            case 418: throw TraktError.denied
            default: throw TraktError.httpStatus(status)
            }
        }
    }

    public func refresh(_ token: TraktToken) async throws -> TraktToken {
        struct Request: Encodable {
            let refresh_token: String
            let client_id: String
            let client_secret: String
            var redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
            var grant_type = "refresh_token"
        }
        let response: TokenResponse = try await send("oauth/token", body: Request(
            refresh_token: token.refreshToken, client_id: credentials.clientID, client_secret: credentials.clientSecret))
        return response.token
    }

    public func username(token: TraktToken) async throws -> String {
        struct Response: Decodable {
            struct User: Decodable { var username: String }
            var user: User
        }
        let response: Response = try await send("users/settings", token: token)
        return response.user.username
    }

    // MARK: Watching

    /// - Parameter progress: 0–100. Stopping past 80 marks the item watched on Trakt.
    public func scrobble(_ action: ScrobbleAction, _ item: WatchItem, progress: Double, token: TraktToken) async throws {
        guard var body = Self.reference(for: item) else { return }
        body.progress = min(max(progress, 0), 100)
        _ = try await request("scrobble/\(action.rawValue)", body: body, token: token)
    }

    /// - Parameter watchedAt: When they were watched, for changes sent later than they happened.
    public func addToHistory(_ items: [WatchItem], watchedAt: Date? = nil, token: TraktToken) async throws {
        guard let body = Self.history(items, watchedAt: watchedAt) else { return }
        _ = try await request("sync/history", body: body, token: token)
    }

    public func removeFromHistory(_ items: [WatchItem], token: TraktToken) async throws {
        guard let body = Self.history(items) else { return }
        _ = try await request("sync/history/remove", body: body, token: token)
    }

    public func playback(token: TraktToken) async throws -> [TraktPlayback] {
        let entries: [PlaybackEntry] = try await send("sync/playback", token: token)
        return entries.compactMap(\.playback)
    }

    /// Clears paused progress, so other devices stop offering to resume it.
    public func removePlayback(id: Int, token: TraktToken) async throws {
        _ = try await response("sync/playback/\(id)", token: token, method: "DELETE")
    }

    /// What the account is playing right now, if anything. Starting playback removes its paused
    /// progress, so this tells that apart from someone removing the title.
    public func watching(token: TraktToken) async throws -> TraktPlayback? {
        let data = try await request("users/me/watching", token: token)
        // 204 when nothing is playing.
        return data.isEmpty ? nil : try Self.decode(HistoryEntry.self, from: data).playback
    }

    /// Completed plays newer than the progress this device still considers unfinished.
    public func watchedHistory(since date: Date, token: TraktToken) async throws -> [TraktPlayback] {
        var result: [TraktPlayback] = []
        var page = 1
        while true {
            try Task.checkCancellation()
            let query = [URLQueryItem(name: "start_at", value: date.ISO8601Format()),
                         URLQueryItem(name: "limit", value: "100"),
                         URLQueryItem(name: "page", value: String(page))]
            let (data, response) = try await response("sync/history", token: token, query: query)
            let entries = try Self.decode([HistoryEntry].self, from: data)
            result.append(contentsOf: entries.compactMap(\.playback))
            if let count = response?.value(forHTTPHeaderField: "X-Pagination-Page-Count").flatMap(Int.init) {
                if page >= count { break }
            } else if entries.count < 100 {
                break
            }
            page += 1
        }
        return result
    }

    // MARK: Request bodies

    struct IDs: Encodable, Equatable { let imdb: String }
    struct Title: Encodable, Equatable {
        let ids: IDs
        var watched_at: String?
    }
    struct EpisodeNumber: Encodable, Equatable { let season: Int; let number: Int }
    struct Number: Encodable, Equatable {
        let number: Int
        var watched_at: String?
    }

    /// A movie, or an episode of a show, as scrobbles name it.
    struct Reference: Encodable, Equatable {
        var movie: Title?
        var show: Title?
        var episode: EpisodeNumber?
        /// 0–100; only scrobbles send it.
        var progress: Double?
    }

    struct History: Encodable, Equatable {
        struct Show: Encodable, Equatable { let ids: IDs; let seasons: [Season] }
        struct Season: Encodable, Equatable { let number: Int; let episodes: [Number] }
        let movies: [Title]
        let shows: [Show]
    }

    /// Trakt identifies titles by IMDb ID, which is what Cinemeta uses. Items from addons
    /// with their own IDs (e.g. `kitsu:`) can't be matched and are left out.
    static func reference(for item: WatchItem) -> Reference? {
        guard item.metaID.hasPrefix("tt") else { return nil }
        let title = Title(ids: IDs(imdb: item.metaID))
        if let season = item.season, let episode = item.episode {
            return Reference(show: title, episode: EpisodeNumber(season: season, number: episode))
        }
        return item.type == MediaType.movie ? Reference(movie: title) : nil
    }

    static func history(_ items: [WatchItem], watchedAt: Date? = nil) -> History? {
        let time = watchedAt?.ISO8601Format()
        var movies: [Title] = []
        // Show → season → episode numbers.
        var shows: [String: [Int: [Int]]] = [:]
        for item in items {
            guard let reference = reference(for: item) else { continue }
            if let movie = reference.movie {
                movies.append(Title(ids: movie.ids, watched_at: time))
            } else if let episode = reference.episode {
                shows[item.metaID, default: [:]][episode.season, default: []].append(episode.number)
            }
        }
        guard !movies.isEmpty || !shows.isEmpty else { return nil }
        return History(movies: movies, shows: shows.sorted { $0.key < $1.key }.map { imdb, seasons in
            History.Show(ids: IDs(imdb: imdb), seasons: seasons.sorted { $0.key < $1.key }.map { season, episodes in
                History.Season(number: season, episodes: episodes.sorted().map { Number(number: $0, watched_at: time) })
            })
        })
    }

    // MARK: Transport

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String
        var expires_in: Int
        var created_at: Int

        var token: TraktToken {
            TraktToken(accessToken: access_token, refreshToken: refresh_token,
                       expiresAt: Date(timeIntervalSince1970: TimeInterval(created_at + expires_in)))
        }
    }

    struct PlaybackEntry: Decodable {
        struct IDs: Decodable { var imdb: String? }
        struct Titled: Decodable { var ids: IDs }
        struct Episode: Decodable { var season: Int; var number: Int }

        var id: Int?
        var progress: Double
        var paused_at: Date
        var type: String
        var movie: Titled?
        var show: Titled?
        var episode: Episode?

        var playback: TraktPlayback? {
            switch type {
            case "movie":
                guard let imdb = movie?.ids.imdb else { return nil }
                return TraktPlayback(imdbID: imdb, progress: progress, pausedAt: paused_at, id: id)
            case "episode":
                guard let imdb = show?.ids.imdb, let episode else { return nil }
                return TraktPlayback(imdbID: imdb, season: episode.season, episode: episode.number,
                                     progress: progress, pausedAt: paused_at, id: id)
            default:
                return nil
            }
        }
    }

    private struct HistoryEntry: Decodable {
        var watched_at: Date?
        var type: String
        var movie: PlaybackEntry.Titled?
        var show: PlaybackEntry.Titled?
        var episode: PlaybackEntry.Episode?

        var playback: TraktPlayback? {
            PlaybackEntry(progress: 100, paused_at: watched_at ?? .now, type: type,
                          movie: movie, show: show, episode: episode).playback
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Trakt sends fractional seconds, which `.iso8601` rejects.
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
                return date
            }
            return try Date(string, strategy: .iso8601)
        }
        return decoder
    }()

    private func send<T: Decodable>(_ path: String, body: (any Encodable)? = nil, token: TraktToken? = nil) async throws -> T {
        try Self.decode(T.self, from: await request(path, body: body, token: token))
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) } catch { throw TraktError.invalidResponse }
    }

    private func request(_ path: String, body: (any Encodable)? = nil, token: TraktToken? = nil) async throws -> Data {
        try await response(path, body: body, token: token).0
    }

    private func response(_ path: String, body: (any Encodable)? = nil, token: TraktToken? = nil,
                          query: [URLQueryItem] = [], method: String? = nil) async throws -> (Data, HTTPURLResponse?) {
        let url = Self.baseURL.appending(path: path).appending(queryItems: query)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(credentials.clientID, forHTTPHeaderField: "trakt-api-key")
        if let token {
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(body)
        }
        if let method { request.httpMethod = method }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw TraktError.unavailable(error.code)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TraktError.httpStatus(http.statusCode)
        }
        return (data, response as? HTTPURLResponse)
    }
}
