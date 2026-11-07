import Foundation

public struct TMDBPopularDirector: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let portraitURL: String?
    public let popularity: Double
}

public struct TMDBReview: Sendable, Equatable, Identifiable {
    public let id: String
    public let author: String
    public let content: String
    public let rating: Double?
    public let createdAt: String?
    public let url: URL?

    /// Provider reviews mix Markdown with HTML formatting; keep the text and never execute HTML.
    public var plainText: String {
        content
            .replacingOccurrences(of: #"(?i)<br\s*/?>|</p\s*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"</?[A-Za-z][^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

public struct TMDBReviewPage: Sendable, Equatable {
    public let page: Int
    public let totalPages: Int
    public let reviews: [TMDBReview]
}

extension TMDBClient {
    /// Rank a bounded candidate pool by TMDB popularity, including known directors that
    /// an actor-heavy popular-people feed can otherwise omit entirely.
    public func popularDirectors() async throws -> [TMDBPopularDirector] {
        struct Person: Decodable {
            let id: Int
            let name: String
            let known_for_department: String?
            let popularity: Double?
            let profile_path: String?
            let adult: Bool?

            var director: TMDBPopularDirector? {
                guard id > 0, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      adult != true, let popularity, popularity.isFinite, popularity >= 0 else { return nil }
                return TMDBPopularDirector(id: id, name: name,
                    portraitURL: imageURL(profile_path, size: "w185"), popularity: popularity)
            }
        }
        struct Response: Decodable {
            let page: Int
            let total_pages: Int
            let results: [Person]
        }
        var directors: [TMDBPopularDirector] = []
        var seen = Set<Int>()
        for page in 1...10 {
            let response: Response = try await fetch("person/popular", query: [.init(name: "page", value: String(page))])
            guard response.page == page, response.total_pages >= 0 else { throw TMDBError.invalidResponse }
            for person in response.results where person.known_for_department == "Directing" {
                guard let director = person.director, seen.insert(director.id).inserted else { continue }
                directors.append(director)
            }
            if directors.count >= 12 || page >= response.total_pages { break }
        }
        // These existing editorial identities establish directorship; fetch only their
        // current popularity/portrait, never their entire filmographies for a Home row.
        for id in FilmCollection.directors.compactMap(\.tmdbPersonID) where !seen.contains(id) {
            do {
                let person: Person = try await fetch("person/\(id)")
                guard person.id == id else { throw TMDBError.invalidResponse }
                if let director = person.director {
                    seen.insert(id)
                    directors.append(director)
                }
            } catch TMDBError.notFound {
                // A removed provider identity needn't hide the other available directors.
                continue
            }
        }
        return Array(directors.sorted {
            $0.popularity == $1.popularity ? $0.id < $1.id : $0.popularity > $1.popularity
        }.prefix(12))
    }

    public func reviews(imdbID: String, type: String, page: Int = 1) async throws -> TMDBReviewPage {
        guard imdbID.wholeMatch(of: /tt\d+/) != nil, [MediaType.movie, MediaType.series].contains(type), (1...500).contains(page) else {
            throw TMDBError.notFound
        }
        struct Find: Decodable {
            struct Match: Decodable { let id: Int }
            let movie_results: [Match]?
            let tv_results: [Match]?
        }
        let found: Find = try await fetch("find/\(imdbID)", query: [.init(name: "external_source", value: "imdb_id")])
        guard let id = (type == MediaType.movie ? found.movie_results : found.tv_results)?.first?.id, id > 0 else {
            throw TMDBError.notFound
        }
        struct Response: Decodable {
            struct Entry: Decodable {
                struct Author: Decodable { let rating: Double? }
                let id: String
                let author: String
                let content: String
                let author_details: Author?
                let created_at: String?
                let url: String?
            }
            let id: Int
            let page: Int
            let total_pages: Int
            let results: [Entry]
        }
        let response: Response = try await fetch("\(type == MediaType.movie ? "movie" : "tv")/\(id)/reviews", query: [
            .init(name: "page", value: String(page)),
        ])
        guard response.id == id, response.page == page, response.total_pages >= 0 else { throw TMDBError.invalidResponse }
        var seen = Set<String>()
        let reviews = response.results.compactMap { entry -> TMDBReview? in
            let content = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.id.isEmpty, !content.isEmpty, seen.insert(entry.id).inserted else { return nil }
            let rating = entry.author_details?.rating.flatMap { $0.isFinite && (0...10).contains($0) ? $0 : nil }
            let url = entry.url.flatMap(URL.init(string:)).flatMap {
                $0.scheme == "https" && $0.host() == "www.themoviedb.org" && $0.user == nil && $0.password == nil
                    && $0.pathComponents == ["/", "review", entry.id] ? $0 : nil
            }
            return TMDBReview(id: entry.id, author: entry.author.isEmpty ? "TMDB member" : entry.author,
                              content: content, rating: rating, createdAt: entry.created_at, url: url)
        }
        return TMDBReviewPage(page: response.page, totalPages: min(500, response.total_pages), reviews: reviews)
    }
}
