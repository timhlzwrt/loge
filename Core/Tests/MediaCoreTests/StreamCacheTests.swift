import Foundation
import Synchronization
import Testing
@testable import MediaCore

struct StreamCacheTests {
    let stream = StreamSource(url: "https://cdn.example/a.mkv")

    @Test func joinsARequestInFlight() async throws {
        let cache = StreamCache()
        let calls = Mutex(0)
        let fetch: @Sendable () async throws -> [StreamSource] = { [stream] in
            calls.withLock { $0 += 1 }
            try await Task.sleep(for: .milliseconds(50))
            return [stream]
        }
        async let first = cache.streams(manifestURL: "a", type: "movie", id: "tt1", fetch: fetch)
        async let second = cache.streams(manifestURL: "a", type: "movie", id: "tt1", fetch: fetch)
        let results = try await [first, second]
        #expect(results.allSatisfy { $0.count == 1 })
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func asksAgainAfterAFailure() async throws {
        struct Unreachable: Error {}
        let cache = StreamCache()
        await #expect(throws: Unreachable.self) {
            try await cache.streams(manifestURL: "a", type: "movie", id: "tt1") { throw Unreachable() }
        }
        let streams = try await cache.streams(manifestURL: "a", type: "movie", id: "tt1") { [stream] in [stream] }
        #expect(streams.count == 1)
    }

    @Test func asksAgainOnceExpired() async throws {
        let cache = StreamCache(lifetime: 0)
        _ = try await cache.streams(manifestURL: "a", type: "movie", id: "tt1") { [] }
        let streams = try await cache.streams(manifestURL: "a", type: "movie", id: "tt1") { [stream] in [stream] }
        #expect(streams.count == 1)
    }
}
