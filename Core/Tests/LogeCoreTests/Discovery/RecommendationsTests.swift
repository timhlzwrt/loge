import Foundation
import Testing
@testable import LogeCore

struct RecommendationsTests {
    private func entry(_ metaID: String, type: String = "movie", episode: Int? = nil, fraction: Double) -> WatchProgress {
        let id = episode.map { "\(metaID):1:\($0)" } ?? metaID
        return WatchProgress(item: WatchItem(id: id, type: type, metaID: metaID, title: metaID, season: episode.map { _ in 1 },
                                             episode: episode),
                             position: fraction * 100, duration: 100, updatedAt: .now)
    }

    private func title(_ id: Int, type: String = "movie") -> TMDBCreditTitle {
        TMDBCreditTitle(tmdbID: id, type: type, name: "Title \(id)")
    }

    @Test func seedsAreWatchedTitlesNewestFirstThenWatchLater() {
        let history = [
            entry("tt3", fraction: 0.1),                          // abandoned early
            entry("tt2", type: "series", episode: 2, fraction: 0.05),
            entry("tt2", type: "series", episode: 1, fraction: 1), // an earlier episode was watched
            entry("tt1", fraction: 0.95),
            entry("not-imdb", fraction: 1),
            entry("tt1", fraction: 0.6),
        ]
        let saved = [MetaPreview(id: "tt1", type: "movie", name: "Already a seed"),
                     MetaPreview(id: "tt8", type: "movie", name: "Saved"),
                     MetaPreview(id: "tt9", type: "channel", name: "Not a title")]
        let seeds = Recommendations.seeds(history: history, saved: saved)
        #expect(seeds.map(\.imdbID) == ["tt2", "tt1", "tt8"])
        #expect(seeds.map(\.type) == ["series", "movie", "movie"])
        #expect(seeds[0].weight > seeds[1].weight)
        #expect(seeds[2].weight == Recommendations.savedWeight)
    }

    @Test func seedsAreCappedPerSource() {
        let history = (0..<20).map { entry("tt\($0)", fraction: 1) }
        let saved = (100..<120).map { MetaPreview(id: "tt\($0)", type: "movie", name: "") }
        let seeds = Recommendations.seeds(history: history, saved: saved)
        #expect(seeds.count == Recommendations.watchedSeeds + Recommendations.savedSeeds)
        #expect(seeds.first?.imdbID == "tt0")
        #expect(seeds.last?.imdbID == "tt103")
    }

    @Test func titlesSeveralSeedsShareRankFirstAndExclusionsDrop() {
        let first = Recommendations.Seed(imdbID: "tt1", type: "movie", weight: 1)
        let second = Recommendations.Seed(imdbID: "tt2", type: "movie", weight: 0.85)
        let ranked = Recommendations.rank([
            (first, [title(10), title(11), title(12), title(1)]),
            (second, [title(20), title(12), title(2)]),
        ], excluding: ["movie:1", "movie:2"])
        // 12 is recommended by both seeds, so it beats each seed's own first pick.
        #expect(ranked.map(\.tmdbID) == [12, 10, 20, 11])
    }

    @Test func movieAndSeriesWithTheSameNumberStayDistinctAndTiesKeepOrder() {
        let seed = Recommendations.Seed(imdbID: "tt1", type: "movie", weight: 1)
        let other = Recommendations.Seed(imdbID: "tt2", type: "series", weight: 1)
        let ranked = Recommendations.rank([(seed, [title(5)]), (other, [title(5, type: "series")])], excluding: [])
        #expect(ranked.map(\.id) == ["movie:5", "series:5"])
    }
}
