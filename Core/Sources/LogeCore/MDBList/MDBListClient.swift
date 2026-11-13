import Foundation

public enum MDBListError: Error, Sendable, Equatable {
    case unauthorized, rateLimited, notFound, unavailable, invalidResponse
}

/// A title's scores on other sites, each on that site's own scale.
public struct TitleScores: Sendable, Equatable {
    /// Letterboxd's average, out of 5.
    public var letterboxd: Double?
    /// Rotten Tomatoes' critics score, in percent.
    public var tomatometer: Int?
    /// The title's page on Rotten Tomatoes, which can't be worked out from an IMDb ID.
    public var rottenTomatoesURL: URL?

    public init(letterboxd: Double? = nil, tomatometer: Int? = nil, rottenTomatoesURL: URL? = nil) {
        self.letterboxd = letterboxd
        self.tomatometer = tomatometer
        self.rottenTomatoesURL = rottenTomatoesURL
    }
}

/// Scores collected by MDBList, asked for by IMDb ID with the user's own API key.
public struct MDBListClient: Sendable {
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    /// Asks for the key's own account, which costs nothing but one of the day's requests.
    public func validate() async throws {
        let _: UserResponse = try await fetch("user")
    }

    public func scores(imdbID: String, type: String) async throws -> TitleScores {
        guard imdbID.wholeMatch(of: /tt\d+/) != nil, type == MediaType.movie || type == MediaType.series else {
            throw MDBListError.notFound
        }
        let response: MediaResponse = try await fetch("imdb/\(type == MediaType.movie ? "movie" : "show")/\(imdbID)/")
        return response.scores
    }

    private func fetch<Response: Decodable>(_ path: String) async throws -> Response {
        try Task.checkCancellation()
        guard !apiKey.isEmpty, apiKey.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw MDBListError.unauthorized
        }
        // MDBList takes its key in the query, so this URL never goes into a log or an error.
        var components = URLComponents(string: "https://api.mdblist.com/\(path)")!
        components.queryItems = [.init(name: "apikey", value: apiKey)]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            try Task.checkCancellation()
            throw MDBListError.unavailable
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw MDBListError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw MDBListError.unauthorized
        case 404: throw MDBListError.notFound
        case 429: throw MDBListError.rateLimited
        default: throw MDBListError.unavailable
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw MDBListError.invalidResponse
        }
    }
}

private struct UserResponse: Decodable {}

struct MediaResponse: Decodable {
    struct Rating: Decodable {
        let source: String?
        let value: Double?
        let url: String?

        enum CodingKeys: CodingKey { case source, value, url }

        /// Each field on its own: a source this doesn't read may type them differently.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            source = try? container.decode(String.self, forKey: .source)
            value = try? container.decode(Double.self, forKey: .value)
            url = try? container.decode(String.self, forKey: .url)
        }
    }
    let ratings: [Rating]?

    /// A score outside its site's scale is left out rather than shown.
    var scores: TitleScores {
        func rating(_ source: String) -> Rating? { ratings?.first { $0.source == source && $0.value != nil } }
        let tomatoes = rating("tomatoes")
        return TitleScores(
            letterboxd: rating("letterboxd")?.value.flatMap { $0 > 0 && $0 <= 5 ? $0 : nil },
            tomatometer: tomatoes?.value.flatMap { $0 >= 0 && $0 <= 100 ? Int($0.rounded()) : nil },
            rottenTomatoesURL: tomatoes?.url.flatMap(Self.rottenTomatoesURL))
    }

    /// The page's address, or its path on the site (`/m/…`, `/tv/…`); anything else is no link.
    static func rottenTomatoesURL(_ value: String) -> URL? {
        if value.wholeMatch(of: /\/(m|tv)\/[A-Za-z0-9_\-\/]+/) != nil {
            return URL(string: "https://www.rottentomatoes.com\(value)")
        }
        guard let url = URL(string: value), url.scheme == "https",
              url.host() == "www.rottentomatoes.com" || url.host() == "rottentomatoes.com" else { return nil }
        return url
    }
}
