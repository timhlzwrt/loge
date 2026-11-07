import Foundation

/// "Recommended" on Home: TMDB's recommendations for what the viewer watched and saved,
/// ranked on the device. Nothing about the library is sent anywhere; TMDB only sees the
/// same title lookups that opening those titles' pages makes.
public enum Recommendations {
    public struct Seed: Sendable, Hashable {
        public var imdbID: String
        public var type: String
        public var weight: Double

        public init(imdbID: String, type: String, weight: Double) {
            self.imdbID = imdbID
            self.type = type
            self.weight = weight
        }
    }

    /// A title counts once more than half of it (or of one of its episodes) was watched;
    /// a few minutes of something abandoned says little about taste.
    static let watchedFraction = 0.5
    static let watchedSeeds = 8
    static let savedSeeds = 4
    /// Each seed counts for less than the one watched or saved before it.
    static let decay = 0.85
    /// Watch Later is intent rather than taste, so it counts for less than watching.
    static let savedWeight = 0.5

    /// The most recently watched titles, then the newest Watch Later titles not already among them.
    public static func seeds(history: [WatchProgress], saved: [MetaPreview]) -> [Seed] {
        var order: [WatchItem] = []
        var watched = Set<String>()
        var seen = Set<String>()
        for entry in history where isTitle(entry.item.metaID, type: entry.item.type) {
            if seen.insert(entry.item.metaID).inserted { order.append(entry.item) }
            if entry.fraction >= watchedFraction { watched.insert(entry.item.metaID) }
        }
        var seeds = order.filter { watched.contains($0.metaID) }.prefix(watchedSeeds).enumerated().map {
            Seed(imdbID: $1.metaID, type: $1.type, weight: pow(decay, Double($0)))
        }
        let chosen = Set(seeds.map(\.imdbID))
        let wanted = saved.filter { isTitle($0.id, type: $0.type) && !chosen.contains($0.id) }.prefix(savedSeeds)
        seeds += wanted.enumerated().map {
            Seed(imdbID: $1.id, type: $1.type, weight: savedWeight * pow(decay, Double($0)))
        }
        return seeds
    }

    /// Titles that several seeds recommend, or that sit near the top of one seed's list, come first.
    /// Ties keep the order the titles first appeared in, so the row doesn't reshuffle between loads.
    public static func rank(_ lists: [(seed: Seed, titles: [TMDBCreditTitle])], excluding excluded: Set<String>) -> [TMDBCreditTitle] {
        var scores: [String: Double] = [:]
        var titles: [TMDBCreditTitle] = []
        for (seed, recommended) in lists {
            for (position, title) in recommended.enumerated() where !excluded.contains(title.id) {
                if scores[title.id] == nil { titles.append(title) }
                scores[title.id, default: 0] += seed.weight / (1 + Double(position) / 5)
            }
        }
        let first = Dictionary(uniqueKeysWithValues: titles.enumerated().map { ($1.id, $0) })
        return titles.sorted {
            let (left, right) = (scores[$0.id]!, scores[$1.id]!)
            return left != right ? left > right : first[$0.id]! < first[$1.id]!
        }
    }

    private static func isTitle(_ id: String, type: String) -> Bool {
        (type == MediaType.movie || type == MediaType.series) && id.wholeMatch(of: /tt\d+/) != nil
    }
}

extension TMDBAccount {
    /// Ranked recommendations with IMDb IDs, leaving out the titles in `library`.
    /// Seeds TMDB can't look up are skipped; it throws only when none of them could be.
    public func recommendations(for seeds: [Recommendations.Seed], excluding library: Set<String>,
                                limit: Int = 20) async throws -> [MetaPreview] {
        // Started together rather than one after another; the shared cache keeps each
        // response for the details page, so a lookup outliving this screen isn't wasted.
        let lookups = seeds.map { seed in Task { try await details(imdbID: seed.imdbID, type: seed.type) } }
        var lists: [(seed: Recommendations.Seed, titles: [TMDBCreditTitle])] = []
        var excluded = Set<String>()
        var firstError: Error?
        for (seed, lookup) in zip(seeds, lookups) {
            do {
                let details = try await lookup.value
                lists.append((seed, details.recommendations))
                if let id = details.tmdbID { excluded.insert("\(seed.type):\(id)") }
            } catch {
                firstError = firstError ?? error
            }
            try Task.checkCancellation()
        }
        if lists.isEmpty, let firstError { throw firstError }

        // Recommendations carry TMDB IDs; only an IMDb ID opens in the addons and the library.
        // A few spare candidates cover the ones that turn out to be in the library already.
        let candidates = Recommendations.rank(lists, excluding: excluded).prefix(limit + 10)
        let identities = candidates.map { title in Task { try await imdbID(tmdbID: title.tmdbID, type: title.type) } }
        var previews: [MetaPreview] = []
        var shown = Set<String>()
        for (title, identity) in zip(candidates, identities) where previews.count < limit {
            // A title without an IMDb ID can't be played or saved, so it's left out.
            guard let id = try? await identity.value, !library.contains(id),
                  shown.insert(id).inserted else { continue }
            try Task.checkCancellation()
            // Cinemeta's title logo, as the catalogs have, for the tvOS Home header.
            previews.append(MetaPreview(
                id: id, type: title.type, name: title.name, poster: title.posterURL,
                releaseInfo: title.releaseDate.map { String($0.prefix(4)) },
                background: title.backgroundURL, logo: "https://images.metahub.space/logo/medium/\(id)/img",
                description: title.overview))
        }
        return previews
    }
}
