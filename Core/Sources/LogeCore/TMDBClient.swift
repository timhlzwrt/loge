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
        guard tmdbID > 0, type == "movie" || type == "series" else { throw TMDBError.notFound }
        struct Response: Decodable {
            let id: Int
            let imdb_id: String?
            let success: Bool?
        }
        let resource = type == "movie" ? "movie" : "tv"
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

private struct FindResponse: Decodable {
    struct Match: Decodable { let id: Int }
    let movie_results: [Match]?
    let tv_results: [Match]?
}

private struct DetailsResponse: Decodable {
    struct Genre: Decodable { let name: String? }
    struct Country: Decodable { let name: String?; let iso_3166_1: String? }
    struct Company: Decodable { let name: String? }
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
    let tagline: String?
    let original_title: String?
    let original_name: String?
    let status: String?
    let original_language: String?
    let production_countries: [Country]?
    let origin_country: [String]?
    let production_companies: [Company]?
    let last_air_date: String?
    let number_of_seasons: Int?
    let number_of_episodes: Int?
    let vote_average: Double?
    let vote_count: Int?
    let budget: Int?
    let revenue: Int?

    func details(isMovie: Bool) -> TMDBDetails {
        let date = fullDate(isMovie ? release_date : first_air_date)
        let year = date.map { String($0.prefix(4)) }
        let minutes = isMovie ? runtime : episode_run_time?.first(where: { $0 > 0 })
        let genres = genres?.compactMap { nonempty($0.name) }
        let countryNames = production_countries?.compactMap { country in
            nonempty(country.name) ?? nonempty(country.iso_3166_1).map {
                Locale(identifier: "en_US").localizedString(forRegionCode: $0) ?? $0
            }
        } ?? []
        let countries = countryNames.isEmpty ? origin_country?.compactMap { code in
            nonempty(code).map { Locale(identifier: "en_US").localizedString(forRegionCode: $0) ?? $0 }
        } : countryNames
        let companies = production_companies?.compactMap { nonempty($0.name) }
        let rating = vote_average.flatMap { value in
            value.isFinite && (0...10).contains(value) && (vote_count ?? 0) > 0 ? value : nil
        }
        return TMDBDetails(
            overview: nonempty(overview),
            posterURL: imageURL(poster_path, size: "w500"),
            backgroundURL: imageURL(backdrop_path, size: "w1280"),
            releaseInfo: year,
            runtime: minutes.flatMap { $0 > 0 ? "\($0) min" : nil },
            genres: genres.flatMap { $0.isEmpty ? nil : $0 },
            people: credits?.people ?? [],
            tagline: nonempty(tagline), originalTitle: nonempty(isMovie ? original_title : original_name),
            status: nonempty(status), originalLanguage: nonempty(original_language),
            countries: uniqueNonempty(countries), studios: uniqueNonempty(companies),
            releaseDate: date, lastAirDate: isMovie ? nil : fullDate(last_air_date),
            seasonCount: isMovie ? nil : number_of_seasons.flatMap { $0 >= 0 ? $0 : nil },
            episodeCount: isMovie ? nil : number_of_episodes.flatMap { $0 >= 0 ? $0 : nil },
            rating: rating, voteCount: vote_count.flatMap { $0 >= 0 ? $0 : nil },
            budget: isMovie ? budget.flatMap { $0 > 0 ? $0 : nil } : nil,
            revenue: isMovie ? revenue.flatMap { $0 > 0 ? $0 : nil } : nil)
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

private struct PersonResponse: Decodable {
    let id: Int
    let name: String?
    let biography: String?
    let profile_path: String?
    let known_for_department: String?
    let birthday: String?
    let place_of_birth: String?
    let combined_credits: CombinedCreditsResponse
}

private struct CombinedCreditsResponse: Decodable {
    struct Credit: Decodable {
        let id: Int?
        let media_type: String?
        let title: String?
        let name: String?
        let original_title: String?
        let original_name: String?
        let poster_path: String?
        let backdrop_path: String?
        let overview: String?
        let release_date: String?
        let first_air_date: String?
        let character: String?
        let job: String?
        let department: String?
    }
    let cast: [Credit]
    let crew: [Credit]
    let success: Bool?

    var titles: [TMDBCreditTitle] {
        var titles: [TMDBCreditTitle] = []
        var indices: [String: Int] = [:]
        func add(_ credit: Credit, isCast: Bool) {
            guard let tmdbID = credit.id, tmdbID > 0,
                  credit.media_type == "movie" || credit.media_type == "tv" else { return }
            let isMovie = credit.media_type == "movie"
            let type = isMovie ? "movie" : "series"
            guard let name = nonempty(isMovie ? credit.title : credit.name)
                    ?? nonempty(isMovie ? credit.original_title : credit.original_name) else { return }
            let role: String
            if isCast {
                role = nonempty(credit.character).map { "Actor · \($0)" } ?? "Actor"
            } else {
                role = nonempty(credit.job) ?? nonempty(credit.department) ?? "Crew"
            }
            // Only the Director job counts as directing, not camera or assistant-director credits.
            let creditRole: TMDBCreditRole = isCast ? .acting
                : (nonempty(credit.job) == "Director" ? .directing : .otherCrew)
            let title = TMDBCreditTitle(
                tmdbID: tmdbID, type: type, name: name,
                posterURL: imageURL(credit.poster_path, size: "w500"),
                backgroundURL: imageURL(credit.backdrop_path, size: "w1280"),
                overview: nonempty(credit.overview),
                releaseDate: fullDate(isMovie ? credit.release_date : credit.first_air_date),
                roles: [role], creditRoles: [creditRole])
            if let index = indices[title.id] {
                titles[index].creditRoles.insert(creditRole)
                if !titles[index].roles.contains(role) { titles[index].roles.append(role) }
                if titles[index].posterURL == nil { titles[index].posterURL = title.posterURL }
                if titles[index].backgroundURL == nil { titles[index].backgroundURL = title.backgroundURL }
                if titles[index].overview == nil { titles[index].overview = title.overview }
                if titles[index].releaseDate == nil { titles[index].releaseDate = title.releaseDate }
            } else {
                indices[title.id] = titles.count
                titles.append(title)
            }
        }
        for credit in cast { add(credit, isCast: true) }
        for credit in crew { add(credit, isCast: false) }
        return titles.sorted {
            if $0.releaseDate != $1.releaseDate { return ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id < $1.id
        }
    }
}

private func fullDate(_ value: String?) -> String? {
    guard let value, value.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}/) != nil else { return nil }
    return value
}

private func uniqueNonempty(_ values: [String]?) -> [String]? {
    var seen = Set<String>()
    let unique = values?.filter { seen.insert($0).inserted } ?? []
    return unique.isEmpty ? nil : unique
}

private func nonempty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func imageURL(_ path: String?, size: String) -> String? {
    guard let path = nonempty(path), path.hasPrefix("/"), !path.hasPrefix("//"),
          !path.contains(".."), !path.contains("?"), !path.contains("#"), path.count > 1 else { return nil }
    return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")?.absoluteString
}
