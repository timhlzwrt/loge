// TMDB v3 response shapes, mapped to the public models in `TMDBClient`.

import Foundation

struct FindResponse: Decodable {
    struct Match: Decodable { let id: Int }
    let movie_results: [Match]?
    let tv_results: [Match]?
}

struct DetailsResponse: Decodable {
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
    let recommendations: TitlePageResponse?
    let similar: TitlePageResponse?

    func details(isMovie: Bool) -> TMDBDetails {
        let date = fullDate(isMovie ? release_date : first_air_date)
        let year = date.map { String($0.prefix(4)) }
        let minutes = isMovie ? runtime : episode_run_time?.first(where: { $0 > 0 })
        let genres = genres?.compactMap { nonempty($0.name) }
        let countryNames = production_countries?.compactMap { country in
            nonempty(country.name) ?? nonempty(country.iso_3166_1).map {
                Locale.interface.localizedString(forRegionCode: $0) ?? $0
            }
        } ?? []
        let countries = countryNames.isEmpty ? origin_country?.compactMap { code in
            nonempty(code).map { Locale.interface.localizedString(forRegionCode: $0) ?? $0 }
        } : countryNames
        let companies = production_companies?.compactMap { nonempty($0.name) }
        let rating = vote_average.flatMap { value in
            value.isFinite && (0...10).contains(value) && (vote_count ?? 0) > 0 ? value : nil
        }
        let recommended = recommended(isMovie: isMovie)
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
            revenue: isMovie ? revenue.flatMap { $0 > 0 ? $0 : nil } : nil,
            tmdbID: id, recommendations: recommended.titles, recommendationsAreSimilar: recommended.areSimilar)
    }

    private func recommended(isMovie: Bool) -> (titles: [TMDBCreditTitle], areSimilar: Bool) {
        let recommended = recommendations?.titles(isMovie: isMovie, excluding: id) ?? []
        guard recommended.isEmpty else { return (recommended, false) }
        let similar = similar?.titles(isMovie: isMovie, excluding: id) ?? []
        return (similar, !similar.isEmpty)
    }
}

/// A page of `recommendations` or `similar`: always the same kind as the title they belong to.
struct TitlePageResponse: Decodable {
    struct Result: Decodable {
        let id: Int?
        let title: String?
        let name: String?
        let poster_path: String?
        let backdrop_path: String?
        let overview: String?
        let release_date: String?
        let first_air_date: String?
    }
    let results: [Result]?

    func titles(isMovie: Bool, excluding excludedID: Int) -> [TMDBCreditTitle] {
        var seen: Set<Int> = [excludedID]
        return (results ?? []).compactMap { result in
            guard let id = result.id, id > 0, seen.insert(id).inserted,
                  let name = nonempty(isMovie ? result.title : result.name) else { return nil }
            return TMDBCreditTitle(
                tmdbID: id, type: isMovie ? MediaType.movie : MediaType.series, name: name,
                posterURL: imageURL(result.poster_path, size: "w500"),
                backgroundURL: imageURL(result.backdrop_path, size: "w1280"),
                overview: nonempty(result.overview),
                releaseDate: fullDate(isMovie ? result.release_date : result.first_air_date))
        }
    }
}

struct CreditsResponse: Decodable {
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
        let writingJobs = ["Writer", "Screenplay", "Story", "Novel", "Teleplay", "Characters", "Original Story", "Author"]
        for credit in crew ?? [] {
            if credit.job == "Director" { add(credit, role: .director) }
            if credit.department == "Writing" || writingJobs.contains(credit.job ?? "") {
                add(credit, role: .writer)
            }
        }
        // TMDB's cast runs on to dozens of uncredited extras, mostly without photos, so the
        // director came last, after all of them. Directors lead, as a film's credits do.
        let directors = people.filter { $0.roles.contains(.director) }
        let cast = people.filter { !$0.roles.contains(.director) && $0.roles.contains(.actor) }.prefix(Self.castLimit)
        let shown = Set(cast.map(\.id))
        let writers = people.filter { !$0.roles.contains(.director) && $0.roles.contains(.writer) && !shown.contains($0.id) }
        return directors + cast + writers
    }

    /// The top-billed cast, as TMDB's own title pages show before "Full Cast & Crew".
    static let castLimit = 20
}

struct PersonResponse: Decodable {
    let id: Int
    let name: String?
    let biography: String?
    let profile_path: String?
    let known_for_department: String?
    let birthday: String?
    let place_of_birth: String?
    let combined_credits: CombinedCreditsResponse
}

struct CombinedCreditsResponse: Decodable {
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
            let type = isMovie ? MediaType.movie : MediaType.series
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

func fullDate(_ value: String?) -> String? {
    guard let value, value.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}/) != nil else { return nil }
    return value
}

func uniqueNonempty(_ values: [String]?) -> [String]? {
    var seen = Set<String>()
    let unique = values?.filter { seen.insert($0).inserted } ?? []
    return unique.isEmpty ? nil : unique
}

func nonempty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func imageURL(_ path: String?, size: String) -> String? {
    guard let path = nonempty(path), path.hasPrefix("/"), !path.hasPrefix("//"),
          !path.contains(".."), !path.contains("?"), !path.contains("#"), path.count > 1 else { return nil }
    return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")?.absoluteString
}
