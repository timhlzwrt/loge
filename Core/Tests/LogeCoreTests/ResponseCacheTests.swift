import Synchronization
import Testing
@testable import LogeCore

struct ResponseCacheTests {
    @Test func concurrentLookupsShareOneFetchAndKeepTheSuccessfulResult() async throws {
        let cache = ResponseCache<String, Int>(capacity: 2, lifetime: .seconds(60))
        let calls = Mutex(0)
        let fetch: @Sendable () async throws -> Int = {
            calls.withLock { $0 += 1 }
            try await Task.sleep(for: .milliseconds(50))
            return 7
        }
        async let first = cache.value(for: "same", fetch: fetch)
        async let second = cache.value(for: "same", fetch: fetch)
        let results = try await [first, second]
        #expect(results == [7, 7])
        #expect(try await cache.value(for: "same") { 9 } == 7)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func failureDoesNotPoisonTheNextLookup() async throws {
        enum FixtureFailure: Error, Equatable { case unavailable }
        let cache = ResponseCache<String, Int>(capacity: 2, lifetime: .seconds(60))
        await #expect(throws: FixtureFailure.unavailable) {
            try await cache.value(for: "same") { throw FixtureFailure.unavailable }
        }
        #expect(try await cache.value(for: "same") { 7 } == 7)
    }

    @Test func cancelledWaiterLeavesSharedResultAvailable() async throws {
        let cache = ResponseCache<String, Int>(capacity: 2, lifetime: .seconds(60))
        let calls = Mutex(0)
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
        let first = Task {
            try await cache.value(for: "same") {
                calls.withLock { $0 += 1 }
                continuation.yield(())
                continuation.finish()
                for await _ in release { break }
                return 7
            }
        }
        for await _ in started { break }
        let second = Task { try await cache.value(for: "same") { 9 } }
        first.cancel()
        releaseContinuation.yield(())
        releaseContinuation.finish()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await second.value == 7)
        #expect(try await cache.value(for: "same") { 9 } == 7)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func expiredValuesAndCapacityEvictionsAreFetchedAgain() async throws {
        let expired = ResponseCache<String, Int>(capacity: 2, lifetime: .zero)
        #expect(try await expired.value(for: "same") { 1 } == 1)
        #expect(try await expired.value(for: "same") { 2 } == 2)
        let bounded = ResponseCache<String, Int>(capacity: 2, lifetime: .seconds(60))
        _ = try await bounded.value(for: "first") { 1 }
        _ = try await bounded.value(for: "second") { 2 }
        _ = try await bounded.value(for: "third") { 3 }
        #expect(try await bounded.value(for: "first") { 4 } == 4)
        #expect(try await bounded.value(for: "third") { 9 } == 3)
    }

    @Test func successfulMissingIdentityIsCached() async throws {
        let cache = ResponseCache<Int, String?>(capacity: 2, lifetime: .seconds(60))
        #expect(try await cache.value(for: 42) { nil } == nil)
        #expect(try await cache.value(for: 42) { "tt0000042" } == nil)
    }

    @Test func valuesItDoesNotKeepAreFetchedAgain() async throws {
        let cache = ResponseCache<String, [Int]>(capacity: 2, lifetime: .seconds(60)) { !$0.isEmpty }
        #expect(try await cache.value(for: "same") { [] } == [])
        #expect(try await cache.value(for: "same") { [7] } == [7])
        #expect(try await cache.value(for: "same") { [9] } == [7])
    }
}
