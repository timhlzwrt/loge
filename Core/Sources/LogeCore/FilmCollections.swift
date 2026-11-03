import Foundation

/// A small editorial selection; directors are not a measured popularity ranking.
public enum FilmCollection: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case cannes, berlin, venice, sundance, toronto, locarno, sanSebastian
    case nolan, spielberg, scorsese, tarantino, miyazaki

    public var id: String { rawValue }
    public static let festivals: [Self] = [.cannes, .berlin, .venice, .sundance, .toronto, .locarno, .sanSebastian]
    public static let directors: [Self] = [.nolan, .spielberg, .scorsese, .tarantino, .miyazaki]

    public var name: String {
        switch self {
        case .cannes: "Cannes"
        case .berlin: "Berlinale"
        case .venice: "Venice"
        case .sundance: "Sundance"
        case .toronto: "Toronto"
        case .locarno: "Locarno"
        case .sanSebastian: "San Sebastián"
        case .nolan: "Christopher Nolan"
        case .spielberg: "Steven Spielberg"
        case .scorsese: "Martin Scorsese"
        case .tarantino: "Quentin Tarantino"
        case .miyazaki: "Hayao Miyazaki"
        }
    }

    public var subtitle: String {
        switch self {
        case .cannes: "Palme d’Or"
        case .berlin: "Golden Bear"
        case .venice: "Golden Lion"
        case .sundance: "U.S. Grand Jury Prize · Dramatic"
        case .toronto: "People’s Choice Award"
        case .locarno: "Golden Leopard awards"
        case .sanSebastian: "Golden Shell"
        default: "Director"
        }
    }

    public var isFestival: Bool { Self.festivals.contains(self) }

    public var tmdbPersonID: Int? {
        switch self {
        case .nolan: 525
        case .spielberg: 488
        case .scorsese: 1032
        case .tarantino: 138
        case .miyazaki: 608
        default: nil
        }
    }

    public var awardScopeNote: String? {
        self == .locarno
            ? "Includes Golden Leopard prizes across competitions."
            : nil
    }

    public var officialResultsURL: URL? {
        switch self {
        case .cannes: URL(string: "https://www.festival-cannes.com/en/awards/")
        case .berlin: URL(string: "https://www.berlinale.de/en/festival/awards-and-juries/all-prizes-and-juries.html")
        case .venice: URL(string: "https://www.labiennale.org/en/news/official-awards-83rd-venice-international-film-festival")
        case .sundance: URL(string: "https://www.sundance.org/blogs/the-complete-list-of-2026-sundance-film-festival-award-winners/")
        case .toronto: URL(string: "https://tiff.net/")
        case .locarno: URL(string: "https://www.locarnofestival.ch/")
        case .sanSebastian: URL(string: "https://www.sansebastianfestival.com/2026/awards_and_jury_members/1/23725/in")
        default: nil
        }
    }

    public var officialResultsLabel: String {
        switch self {
        case .venice, .sundance, .sanSebastian: "Official 2026 results"
        case .locarno, .toronto: "Official festival website"
        case .berlin: "Official awards & juries"
        default: "Official festival results"
        }
    }

    /// Festival marks are bundled; director portraits retain their source attribution.
    public var logoAssetName: String? { isFestival ? "festival-" + rawValue : nil }
    public var artworkURL: String? { artwork.url }
    public var artworkCreditURL: URL { URL(string: artwork.source)! }
    public var artworkCredit: String { artwork.credit }

    private var artwork: (url: String?, source: String, credit: String) {
        switch self {
        case .cannes:
            (nil, "https://commons.wikimedia.org/wiki/File:Palme_d%27Or_gold_silhouette.svg",
             "Festival de Cannes · Public domain")
        case .berlin:
            (nil, "https://www.berlinale.de/en/home.html", "Berlinale")
        case .venice:
            (nil, "https://commons.wikimedia.org/wiki/File:Internationale_Filmfestspiele_von_Venedig_2012_Logo.svg",
             "Venice Film Festival · Public domain")
        case .sundance:
            (nil, "https://festival.sundance.org/", "Sundance Institute")
        case .toronto:
            (nil, "https://commons.wikimedia.org/wiki/File:Toronto_International_Film_Festival_logo.svg",
             "Toronto International Film Festival · Public domain")
        case .locarno:
            (nil, "https://www.fiafnet.org/pages/Community/Supporter-LOCARNO.html", "Locarno Film Festival")
        case .sanSebastian:
            (nil, "https://www.sansebastianfestival.com/in/", "San Sebastián International Film Festival")
        case .nolan:
            ("https://thumb.wikimedia.org/wikipedia/commons/thumb/0/05/Christopher_Nolan.jpg/960px-Christopher_Nolan.jpg",
             "https://commons.wikimedia.org/wiki/File:Christopher_Nolan.jpg", "Republic of Korea · CC BY-SA 4.0")
        case .spielberg:
            ("https://thumb.wikimedia.org/wikipedia/commons/thumb/3/3e/Steven_Spielberg_2025.jpg/960px-Steven_Spielberg_2025.jpg",
             "https://commons.wikimedia.org/wiki/File:Steven_Spielberg_2025.jpg", "Raph_PH · CC BY 4.0")
        case .scorsese:
            ("https://thumb.wikimedia.org/wikipedia/commons/thumb/c/ce/Martin_Scorsese_MFF_2023.jpg/960px-Martin_Scorsese_MFF_2023.jpg",
             "https://commons.wikimedia.org/wiki/File:Martin_Scorsese_MFF_2023.jpg", "Montclair Film · CC BY 2.0")
        case .tarantino:
            ("https://thumb.wikimedia.org/wikipedia/commons/thumb/0/0b/Quentin_Tarantino_by_Gage_Skidmore.jpg/960px-Quentin_Tarantino_by_Gage_Skidmore.jpg",
             "https://commons.wikimedia.org/wiki/File:Quentin_Tarantino_by_Gage_Skidmore.jpg", "Gage Skidmore · CC BY-SA 3.0")
        case .miyazaki:
            ("https://upload.wikimedia.org/wikipedia/commons/f/ff/HayaoMiyazakiCCJuly09.jpg",
             "https://commons.wikimedia.org/wiki/File:HayaoMiyazakiCCJuly09.jpg", "Natasha Baucas · CC BY 2.0")
        }
    }

    private var entity: String {
        switch self {
        case .cannes: "Q179808"
        case .berlin: "Q154590"
        case .venice: "Q209459"
        case .sundance: "Q3774974"
        case .toronto: "Q39087364"
        case .locarno: "Q1700510"
        case .sanSebastian: "Q775086"
        case .nolan: "Q25191"
        case .spielberg: "Q8877"
        case .scorsese: "Q41148"
        case .tarantino: "Q3772"
        case .miyazaki: "Q55400"
        }
    }

    var query: String {
        let relation: String
        if isFestival {
            // Awards may be recorded on the film, its director, or the award's winner statement.
            // Each pattern starts from the award, and the optimizer is off below so Wikidata keeps
            // that order: left to choose, it joined every IMDb ID first and ran past 60 seconds.
            let award = self == .locarno ? "?award" : "wd:\(entity)"
            let selection = self == .locarno ? "VALUES ?award { wd:\(entity) wd:Q30894009 }" : ""
            relation = """
            \(selection)
            { ?statement ps:P166 \(award); pq:P585 ?when. ?film p:P166 ?statement. }
            UNION
            { ?statement ps:P166 \(award); pq:P1686 ?film; pq:P585 ?when. }
            UNION
            { \(award) p:P1346 ?statement.
              ?statement ps:P1346 ?winner; pq:P585 ?when.
              OPTIONAL { ?statement pq:P1686 ?work. }
              BIND(COALESCE(?work, ?winner) AS ?film)
            }
            """
        } else {
            relation = """
            ?film wdt:P57 wd:\(entity).
            ?film wdt:P31/wdt:P279* wd:Q11424.
            OPTIONAL { ?film wdt:P577 ?when. }
            """
        }
        return """
        SELECT ?imdb ?filmLabel (\(isFestival ? "MAX" : "MIN")(?when) AS ?date) WHERE {
            \(isFestival ? "hint:Query hint:optimizer \"None\"." : "")
            { \(relation) }
            ?film wdt:P345 ?imdb.
            FILTER(STRSTARTS(?imdb, "tt"))
            SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        GROUP BY ?imdb ?filmLabel
        ORDER BY DESC(?date) ?imdb
        LIMIT 40
        """
    }
}

public struct CollectionFilm: Sendable, Identifiable, Equatable {
    public let title: MetaPreview
    /// Award year for festivals, first release year for directors.
    public let year: Int?
    public var id: String { title.id }
}

/// Public, CC0 film/award relationships. Artwork and playback metadata still use Cinemeta.
public actor FilmCollectionClient {
    public static let shared = FilmCollectionClient()
    public enum Failure: Error, Equatable { case rateLimited, unavailable }

    private let session: URLSession
    private var cache: [FilmCollection: (loadedAt: Date, films: [CollectionFilm])] = [:]
    private struct FilmKey: Hashable, Sendable {
        let name: String
        let festivalYear: Int
    }
    private var filmCache: [FilmKey: (loadedAt: Date, film: MetaPreview?)] = [:]
    private var filmRequests: [FilmKey: Task<MetaPreview?, Error>] = [:]

    public init(session: URLSession = .shared) { self.session = session }

    public func films(in collection: FilmCollection) async throws -> [CollectionFilm] {
        if let cached = cache[collection], Date.now.timeIntervalSince(cached.loadedAt) < 6 * 60 * 60 {
            return cached.films
        }
        let request = Self.request(for: collection)
        let (data, response) = try await session.data(for: request)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw response.statusCode == 429 ? Failure.rateLimited : Failure.unavailable
        }
        let films = try Self.decode(data)
        cache[collection] = (.now, films)
        return films
    }

    /// A festival title only opens directly when the catalog has one plausible, exact match.
    public func film(named name: String, festivalYear: Int) async throws -> MetaPreview? {
        try Task.checkCancellation()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, (1900...9998).contains(festivalYear) else { return nil }
        let key = FilmKey(name: Self.normalizedTitle(name), festivalYear: festivalYear)
        if let cached = filmCache[key], Date.now.timeIntervalSince(cached.loadedAt) < 6 * 60 * 60 {
            return cached.film
        }
        if let request = filmRequests[key] {
            let match = try await request.value
            try Task.checkCancellation()
            return match
        }
        // Leaving the grid must not cancel a lookup its detail destination is also awaiting.
        let request = Task {
            guard let source = DiscoveryCatalogs.search.first(where: { $0.catalog.type == "movie" }) else {
                throw Failure.unavailable
            }
            let client = try AddonClient(manifestURL: source.manifestURL, session: session)
            let candidates = try await client.catalog(type: source.catalog.type, id: source.catalog.id,
                                                      extra: [(name: "search", value: name)])
            var matches: [String: MetaPreview] = [:]
            for candidate in candidates {
                guard candidate.type == "movie", candidate.id.wholeMatch(of: /tt\d+/) != nil,
                      Self.normalizedTitle(candidate.name) == key.name,
                      let release = candidate.releaseInfo, release.prefix(4).wholeMatch(of: /\d{4}/) != nil,
                      let year = Int(release.prefix(4)), (festivalYear - 1...festivalYear + 1).contains(year),
                      release.dropFirst(4).first?.isNumber != true else { continue }
                matches[candidate.id] = candidate
            }
            return matches.count == 1 ? matches.values.first : nil
        }
        filmRequests[key] = request
        do {
            let match = try await request.value
            filmRequests.removeValue(forKey: key)
            if filmCache.count >= 256,
               let oldest = filmCache.min(by: { $0.value.loadedAt < $1.value.loadedAt })?.key {
                filmCache.removeValue(forKey: oldest)
            }
            filmCache[key] = (.now, match)
            try Task.checkCancellation()
            return match
        } catch {
            filmRequests.removeValue(forKey: key)
            throw error
        }
    }

    private static func normalizedTitle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func request(for collection: FilmCollection) -> URLRequest {
        var components = URLComponents(string: "https://query.wikidata.org/sparql")!
        components.queryItems = [.init(name: "query", value: collection.query), .init(name: "format", value: "json")]
        var request = URLRequest(url: components.url!, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        request.setValue("loge/0.1 (private film discovery client)", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func decode(_ data: Data) throws -> [CollectionFilm] {
        struct Response: Decodable {
            struct Results: Decodable {
                struct Binding: Decodable {
                    struct Value: Decodable { let value: String }
                    let imdb: Value
                    let filmLabel: Value
                    let date: Value?
                }
                let bindings: [Binding]
            }
            let results: Results
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        var seen = Set<String>()
        return response.results.bindings.compactMap { binding in
            let id = binding.imdb.value
            guard id.wholeMatch(of: /tt\d+/) != nil, seen.insert(id).inserted else { return nil }
            let year = binding.date.flatMap { Int($0.value.prefix(4)) }
            return CollectionFilm(
                title: MetaPreview(id: id, type: "movie", name: binding.filmLabel.value,
                                   poster: "https://images.metahub.space/poster/small/\(id)/img"),
                year: year)
        }
    }
}
