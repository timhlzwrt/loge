import Foundation
import Synchronization
import Testing
@testable import MediaCore

final class CatalogCacheTests: Sendable {
    private final class TestClock: Sendable {
        let date = Mutex(Date(timeIntervalSince1970: 1_000_000))
    }

    let url = URL(string: "https://addon.example/catalog/movie/top.json")!
    let directory = FileManager.default.temporaryDirectory.appending(path: "CatalogCacheTests-\(UUID().uuidString)")
    private let clock = TestClock()

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func page(_ ids: String...) -> Data {
        let metas = ids.map { #"{"id":"\#($0)","type":"movie","name":"\#($0)"}"# }
        return Data(#"{"metas":[\#(metas.joined(separator: ","))]}"#.utf8)
    }

    private func cache(memoryOnly: Bool = false) -> CatalogCache {
        CatalogCache(directory: memoryOnly ? nil : directory, freshLifetime: 60, staleLimit: 600) { [clock] in
            clock.date.withLock { $0 }
        }
    }

    private func advance(_ seconds: TimeInterval) {
        clock.date.withLock { $0.addTimeInterval(seconds) }
    }

    private func ids(_ cache: CatalogCache, persist: Bool = true, load: @escaping CatalogCache.Load) async throws -> [String] {
        try await cache.metas(for: url, persist: persist, load: load, decode: AddonClient.decodeCatalog).map(\.id)
    }

    @Test func joinsARequestInFlight() async throws {
        let cache = cache(memoryOnly: true)
        let calls = Mutex(0)
        let load: CatalogCache.Load = { [page = page("a")] in
            calls.withLock { $0 += 1 }
            try await Task.sleep(for: .milliseconds(50))
            return page
        }
        async let first = ids(cache, load: load)
        async let second = ids(cache, load: load)
        let results = try await [first, second]
        #expect(results == [["a"], ["a"]])
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func nextLaunchUsesAFreshPageWithoutAsking() async throws {
        _ = try await ids(cache()) { [page = page("a")] in page }
        advance(30)
        let served = try await ids(cache()) { Issue.record("Asked the addon for a fresh page"); return Data() }
        #expect(served == ["a"])
    }

    @Test func stalePageShowsAtOnceAndRefreshesForNextTime() async throws {
        _ = try await ids(cache()) { [page = page("a")] in page }
        advance(120)
        let refreshed = Mutex(false)
        let stale = try await ids(cache()) { [page = page("b")] in
            refreshed.withLock { $0 = true }
            return page
        }
        #expect(stale == ["a"])
        // The refresh runs on its own; wait for it to land on disk.
        for _ in 0..<100 where !refreshed.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))
        let next = try await ids(cache()) { Issue.record("Asked again despite the refresh"); return Data() }
        #expect(next == ["b"])
    }

    @Test func waitsForTheAddonOnceThePageIsTooOld() async throws {
        _ = try await ids(cache()) { [page = page("a")] in page }
        advance(601)
        let fetched = try await ids(cache()) { [page = page("b")] in page }
        #expect(fetched == ["b"])
    }

    @Test func searchesAreNotKept() async throws {
        _ = try await ids(cache(), persist: false) { [page = page("a")] in page }
        let fetched = try await ids(cache(), persist: false) { [page = page("b")] in page }
        #expect(fetched == ["b"])
    }

    @Test func asksAgainAfterAFailure() async throws {
        struct Unreachable: Error {}
        let cache = cache()
        await #expect(throws: Unreachable.self) {
            try await ids(cache) { throw Unreachable() }
        }
        let fetched = try await ids(cache) { [page = page("a")] in page }
        #expect(fetched == ["a"])
    }

    @Test func undecodablePageIsNotKept() async throws {
        let cache = cache()
        await #expect(throws: DecodingError.self) {
            try await ids(cache) { Data("<html>".utf8) }
        }
        let fetched = try await ids(cache) { [page = page("a")] in page }
        #expect(fetched == ["a"])
    }
}
