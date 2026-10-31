import Foundation

@main
struct ResumeLookupBenchmark {
    @MainActor
    static func main() {
        let suite = "LogePerformance-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(defaults: defaults)
        for index in 0..<500 {
            let item = WatchItem(id: "fixture-\(index)", type: "movie", metaID: "fixture-\(index)", title: "Fixture")
            store.record(item, position: 100, duration: 1000, at: Date(timeIntervalSince1970: Double(index)))
        }
        let iterations = 10_000
        let clock = ContinuousClock()
        var oldMatches = 0
        let oldTime = clock.measure {
            for index in 0..<iterations {
                let metaID = "fixture-\(index % 500)"
                if store.continueWatching.contains(where: { $0.item.metaID == metaID }) {
                    oldMatches += 1
                }
            }
        }
        var newMatches = 0
        let newTime = clock.measure {
            for index in 0..<iterations {
                let metaID = "fixture-\(index % 500)"
                if store.isInProgress(metaID: metaID) { newMatches += 1 }
            }
        }
        print("500 synthetic entries; \(iterations) lookups; optimized Swift build")
        print("Previous sorted-history lookup: \(oldTime); matches: \(oldMatches)")
        print("Single-title scan: \(newTime); matches: \(newMatches)")
    }
}
