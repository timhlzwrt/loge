import Foundation

public enum TMDBError: Error, Sendable, Equatable {
    case unauthorized, rateLimited, notFound, unavailable, invalidResponse
}

/// Provider metadata only; the caller keeps its existing IMDb identity and playback routing.
public struct TMDBDetails: Sendable, Equatable {
    public var overview: String?
    public var posterURL: String?
    public var backgroundURL: String?
    public var releaseInfo: String?
    public var runtime: String?
    public var genres: [String]?
    public var people: [TMDBPerson]
    public var tagline: String?
    public var originalTitle: String?
    public var status: String?
    public var originalLanguage: String?
    public var countries: [String]?
    public var studios: [String]?
    public var releaseDate: String?
    public var lastAirDate: String?
    public var seasonCount: Int?
    public var episodeCount: Int?
    public var rating: Double?
    public var voteCount: Int?
    public var budget: Int?
    public var revenue: Int?

    public init(overview: String? = nil, posterURL: String? = nil, backgroundURL: String? = nil,
                releaseInfo: String? = nil, runtime: String? = nil, genres: [String]? = nil,
                people: [TMDBPerson] = [], tagline: String? = nil, originalTitle: String? = nil,
                status: String? = nil, originalLanguage: String? = nil, countries: [String]? = nil,
                studios: [String]? = nil, releaseDate: String? = nil, lastAirDate: String? = nil,
                seasonCount: Int? = nil, episodeCount: Int? = nil, rating: Double? = nil,
                voteCount: Int? = nil, budget: Int? = nil, revenue: Int? = nil) {
        self.overview = overview
        self.posterURL = posterURL
        self.backgroundURL = backgroundURL
        self.releaseInfo = releaseInfo
        self.runtime = runtime
        self.genres = genres
        self.people = people
        self.tagline = tagline
        self.originalTitle = originalTitle
        self.status = status
        self.originalLanguage = originalLanguage
        self.countries = countries
        self.studios = studios
        self.releaseDate = releaseDate
        self.lastAirDate = lastAirDate
        self.seasonCount = seasonCount
        self.episodeCount = episodeCount
        self.rating = rating
        self.voteCount = voteCount
        self.budget = budget
        self.revenue = revenue
    }
}

public struct TMDBPerson: Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var profileURL: String?
    public var roles: [Person.Role]
    public var character: String?

    public init(id: Int, name: String, profileURL: String? = nil, roles: [Person.Role], character: String? = nil) {
        self.id = id
        self.name = name
        self.profileURL = profileURL
        self.roles = roles
        self.character = character
    }
}

public struct TMDBPersonDetails: Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var biography: String?
    public var portraitURL: String?
    public var knownFor: String?
    public var birthday: String?
    public var placeOfBirth: String?
    public var titles: [TMDBCreditTitle]

    public init(id: Int, name: String, biography: String? = nil, portraitURL: String? = nil,
                knownFor: String? = nil, birthday: String? = nil, placeOfBirth: String? = nil,
                titles: [TMDBCreditTitle] = []) {
        self.id = id
        self.name = name
        self.biography = biography
        self.portraitURL = portraitURL
        self.knownFor = knownFor
        self.birthday = birthday
        self.placeOfBirth = placeOfBirth
        self.titles = titles
    }
}

public enum TMDBCreditRole: String, CaseIterable, Sendable {
    case acting = "Acting"
    case directing = "Directing"
    case otherCrew = "Other crew"
}

/// A filmography entry retains its TMDB identity until an IMDb ID is explicitly resolved.
public struct TMDBCreditTitle: Sendable, Hashable, Identifiable {
    public var tmdbID: Int
    public var type: String
    public var name: String
    public var posterURL: String?
    public var backgroundURL: String?
    public var overview: String?
    public var releaseDate: String?
    public var roles: [String]
    public var creditRoles: Set<TMDBCreditRole>

    public var id: String { "\(type):\(tmdbID)" }

    public init(tmdbID: Int, type: String, name: String, posterURL: String? = nil,
                backgroundURL: String? = nil, overview: String? = nil, releaseDate: String? = nil,
                roles: [String] = [], creditRoles: Set<TMDBCreditRole> = []) {
        self.tmdbID = tmdbID
        self.type = type
        self.name = name
        self.posterURL = posterURL
        self.backgroundURL = backgroundURL
        self.overview = overview
        self.releaseDate = releaseDate
        self.roles = roles
        self.creditRoles = creditRoles
    }
}

/// English details and credits from TMDB v3, authenticated with a read access token.
public struct TMDBClient: Sendable {
    private let readAccessToken: String
    private let session: URLSession

    public init(readAccessToken: String, session: URLSession = .shared) {
        self.readAccessToken = readAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    public func validate() async throws {
        struct Response: Decodable { let success: Bool }
        let response: Response = try await fetch("authentication")
        guard response.success else { throw TMDBError.unauthorized }
    }

    public func details(imdbID: String, type: String) async throws -> TMDBDetails {
        guard imdbID.wholeMatch(of: /tt\d+/) != nil, type == MediaType.movie || type == MediaType.series else {
            throw TMDBError.notFound
        }
        let found: FindResponse = try await fetch("find/\(imdbID)", query: [
            .init(name: "external_source", value: "imdb_id"),
        ])
        let match = type == MediaType.movie ? found.movie_results?.first : found.tv_results?.first
        guard let id = match?.id, id > 0 else { throw TMDBError.notFound }
        let resource = type == MediaType.movie ? "movie" : "tv"
        let response: DetailsResponse = try await fetch("\(resource)/\(id)", query: [
            .init(name: "append_to_response", value: "credits"),
        ])
        guard response.id == id else { throw TMDBError.invalidResponse }
        return response.details(isMovie: type == MediaType.movie)
    }

    public func person(id: Int) async throws -> TMDBPersonDetails {
        guard id > 0 else { throw TMDBError.notFound }
        let response: PersonResponse = try await fetch("person/\(id)", query: [
            .init(name: "append_to_response", value: "combined_credits"),
        ])
        guard response.id == id, let name = nonempty(response.name),
              response.combined_credits.success != false else { throw TMDBError.invalidResponse }
        let details = TMDBPersonDetails(
            id: id, name: name, biography: nonempty(response.biography),
            portraitURL: imageURL(response.profile_path, size: "w500"),
            knownFor: nonempty(response.known_for_department), birthday: fullDate(response.birthday),
            placeOfBirth: nonempty(response.place_of_birth), titles: response.combined_credits.titles)
        try Task.checkCancellation()
        return details
    }

    public func imdbID(tmdbID: Int, type: String) async throws -> String? {
        guard tmdbID > 0, type == MediaType.movie || type == MediaType.series else { throw TMDBError.notFound }
        struct Response: Decodable {
            let id: Int
            let imdb_id: String?
            let success: Bool?
        }
        let resource = type == MediaType.movie ? "movie" : "tv"
        let response: Response = try await fetch("\(resource)/\(tmdbID)/external_ids")
        guard response.id == tmdbID, response.success != false else { throw TMDBError.invalidResponse }
        guard let id = response.imdb_id, !id.isEmpty else { return nil }
        guard id.wholeMatch(of: /tt[0-9]+/) != nil else { throw TMDBError.invalidResponse }
        return id
    }

    func fetch<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        try Task.checkCancellation()
        guard !readAccessToken.isEmpty,
              readAccessToken.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw TMDBError.unauthorized
        }
        var components = URLComponents(string: "https://api.themoviedb.org/3/\(path)")!
        components.queryItems = [.init(name: "language", value: "en-US")] + query
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("Bearer \(readAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            try Task.checkCancellation()
            throw TMDBError.unavailable
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw TMDBError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw TMDBError.unauthorized
        case 404: throw TMDBError.notFound
        case 429: throw TMDBError.rateLimited
        default: throw TMDBError.unavailable
        }
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TMDBError.invalidResponse
        }
        try Task.checkCancellation()
        return decoded
    }
}
