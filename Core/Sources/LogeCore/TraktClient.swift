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
}

public enum TraktError: Error, Equatable {
    case notSignedIn
    /// The device code ran out or was declined before the user approved it.
    case codeExpired
    case denied
    case httpStatus(Int)
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
        let response: Response = try await send("oauth/device/code", body: ["client_id": credentials.clientID])
        return TraktDeviceCode(
            deviceCode: response.device_code, userCode: response.user_code,
            verificationURL: response.verification_url,
            expiresAt: .now.addingTimeInterval(TimeInterval(response.expires_in)),
            interval: response.interval)
    }

    /// The token once the user has approved the code, or nil while they haven't yet.
    public func token(for code: TraktDeviceCode) async throws -> TraktToken? {
        do {
            let response: TokenResponse = try await send("oauth/device/token", body: [
                "code": code.deviceCode,
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
            ])
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
        let response: TokenResponse = try await send("oauth/token", body: [
            "refresh_token": token.refreshToken,
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
            "grant_type": "refresh_token",
        ])
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
        body["progress"] = min(max(progress, 0), 100)
        _ = try await request("scrobble/\(action.rawValue)", body: body, token: token)
    }

    public func addToHistory(_ items: [WatchItem], token: TraktToken) async throws {
        guard let body = Self.history(items) else { return }
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

    // MARK: Request bodies

    /// Trakt identifies titles by IMDb ID, which is what Cinemeta uses. Items from addons
    /// with their own IDs (e.g. `kitsu:`) can't be matched and are left out.
    static func reference(for item: WatchItem) -> [String: Any]? {
        guard item.metaID.hasPrefix("tt") else { return nil }
        let ids = ["ids": ["imdb": item.metaID]]
        if let season = item.season, let episode = item.episode {
            return ["show": ids, "episode": ["season": season, "number": episode]]
        }
        return item.type == "movie" ? ["movie": ids] : nil
    }

    static func history(_ items: [WatchItem]) -> [String: Any]? {
        var movies: [[String: Any]] = []
        // Show → season → episode numbers.
        var shows: [String: [Int: [Int]]] = [:]
        for item in items {
            guard let reference = reference(for: item) else { continue }
            if reference["movie"] != nil {
                movies.append(["ids": ["imdb": item.metaID]])
            } else if let season = item.season, let episode = item.episode {
                shows[item.metaID, default: [:]][season, default: []].append(episode)
            }
        }
        guard !movies.isEmpty || !shows.isEmpty else { return nil }
        let showBodies = shows.sorted { $0.key < $1.key }.map { imdb, seasons in
            [
                "ids": ["imdb": imdb],
                "seasons": seasons.sorted { $0.key < $1.key }.map { season, episodes in
                    ["number": season, "episodes": episodes.sorted().map { ["number": $0] }] as [String: Any]
                },
            ] as [String: Any]
        }
        return ["movies": movies, "shows": showBodies]
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
                return TraktPlayback(imdbID: imdb, progress: progress, pausedAt: paused_at)
            case "episode":
                guard let imdb = show?.ids.imdb, let episode else { return nil }
                return TraktPlayback(imdbID: imdb, season: episode.season, episode: episode.number,
                                     progress: progress, pausedAt: paused_at)
            default:
                return nil
            }
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

    private func send<T: Decodable>(_ path: String, body: [String: Any]? = nil, token: TraktToken? = nil) async throws -> T {
        try Self.decoder.decode(T.self, from: await request(path, body: body, token: token))
    }

    private func request(_ path: String, body: [String: Any]? = nil, token: TraktToken? = nil) async throws -> Data {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(credentials.clientID, forHTTPHeaderField: "trakt-api-key")
        if let token {
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TraktError.httpStatus(http.statusCode)
        }
        return data
    }
}
