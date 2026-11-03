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

    public init(overview: String? = nil, posterURL: String? = nil, backgroundURL: String? = nil,
                releaseInfo: String? = nil, runtime: String? = nil, genres: [String]? = nil,
                people: [TMDBPerson] = []) {
        self.overview = overview
        self.posterURL = posterURL
        self.backgroundURL = backgroundURL
        self.releaseInfo = releaseInfo
        self.runtime = runtime
        self.genres = genres
        self.people = people
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
        guard imdbID.wholeMatch(of: /tt\d+/) != nil, type == "movie" || type == "series" else {
            throw TMDBError.notFound
        }
        let found: FindResponse = try await fetch("find/\(imdbID)", query: [
            .init(name: "external_source", value: "imdb_id"),
        ])
        let match = type == "movie" ? found.movie_results?.first : found.tv_results?.first
        guard let id = match?.id, id > 0 else { throw TMDBError.notFound }
        let resource = type == "movie" ? "movie" : "tv"
        let response: DetailsResponse = try await fetch("\(resource)/\(id)", query: [
            .init(name: "append_to_response", value: "credits"),
        ])
        guard response.id == id else { throw TMDBError.invalidResponse }
        return response.details(isMovie: type == "movie")
    }

    private func fetch<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
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

private struct FindResponse: Decodable {
    struct Match: Decodable { let id: Int }
    let movie_results: [Match]?
    let tv_results: [Match]?
}

private struct DetailsResponse: Decodable {
    struct Genre: Decodable { let name: String? }
    let id: Int
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let release_date: String?
    let first_air_date: String?
    let runtime: Int?
    let episode_run_time: [Int]?
    let genres: [Genre]?
    let credits: CreditsResponse?

    func details(isMovie: Bool) -> TMDBDetails {
        let date = isMovie ? release_date : first_air_date
        let year = date.flatMap { $0.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) == nil ? nil : String($0.prefix(4)) }
        let minutes = isMovie ? runtime : episode_run_time?.first(where: { $0 > 0 })
        let genres = genres?.compactMap { nonempty($0.name) }
        return TMDBDetails(
            overview: nonempty(overview),
            posterURL: imageURL(poster_path, size: "w500"),
            backgroundURL: imageURL(backdrop_path, size: "w1280"),
            releaseInfo: year,
            runtime: minutes.flatMap { $0 > 0 ? "\($0) min" : nil },
            genres: genres.flatMap { $0.isEmpty ? nil : $0 },
            people: credits?.people ?? [])
    }
}

private struct CreditsResponse: Decodable {
    struct Credit: Decodable {
        let id: Int?
        let name: String?
        let profile_path: String?
        let character: String?
        let department: String?
        let job: String?
    }
    let cast: [Credit]?
    let crew: [Credit]?

    var people: [TMDBPerson] {
        var people: [TMDBPerson] = []
        var indices: [Int: Int] = [:]
        func add(_ credit: Credit, role: Person.Role) {
            guard let id = credit.id, id > 0, let name = nonempty(credit.name) else { return }
            let profile = imageURL(credit.profile_path, size: "w185")
            let character = role == .actor ? nonempty(credit.character) : nil
            if let index = indices[id] {
                if !people[index].roles.contains(role) { people[index].roles.append(role) }
                if people[index].profileURL == nil { people[index].profileURL = profile }
                if people[index].character == nil { people[index].character = character }
            } else {
                indices[id] = people.count
                people.append(TMDBPerson(id: id, name: name, profileURL: profile, roles: [role], character: character))
            }
        }
        for credit in cast ?? [] { add(credit, role: .actor) }
        for credit in crew ?? [] {
            if credit.job == "Director" { add(credit, role: .director) }
            if credit.department == "Writing" || ["Writer", "Screenplay", "Story", "Novel", "Teleplay", "Characters", "Original Story", "Author"].contains(credit.job ?? "") {
                add(credit, role: .writer)
            }
        }
        return people
    }
}

private func nonempty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func imageURL(_ path: String?, size: String) -> String? {
    guard let path = nonempty(path), path.hasPrefix("/"), !path.hasPrefix("//"),
          !path.contains(".."), !path.contains("?"), !path.contains("#"), path.count > 1 else { return nil }
    return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")?.absoluteString
}
