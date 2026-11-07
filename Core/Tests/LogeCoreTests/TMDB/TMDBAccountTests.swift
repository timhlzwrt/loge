import Foundation
import Synchronization
import Testing
@testable import LogeCore

@MainActor
struct TMDBAccountTests {
    private func account(_ storage: AccountTokenStorage) -> TMDBAccount {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountTMDBProtocol.self]
        return TMDBAccount(session: URLSession(configuration: configuration), storage: storage.storage)
    }

    @Test func validationFailureDoesNotWriteOrReplaceSavedToken() async {
        let storage = AccountTokenStorage(token: "fixture-old")
        let account = account(storage)
        let revision = account.revision
        await #expect(throws: TMDBError.unauthorized) {
            try await account.connect(readAccessToken: "fixture-rejected")
        }
        #expect(storage.writes == 0)
        #expect(storage.token == "fixture-old")
        #expect(account.isConfigured)
        #expect(account.revision == revision)
    }

    @Test func savingFailureKeepsPreviousConnectionAndReportsStorageError() async throws {
        let storage = AccountTokenStorage(token: "fixture-old")
        let account = account(storage)
        storage.saveError = .storageSave(-50)
        let revision = account.revision
        await #expect(throws: TMDBAccountError.storageSave(-50)) {
            try await account.connect(readAccessToken: "fixture-new")
        }
        #expect(storage.token == "fixture-old")
        #expect(account.isConfigured)
        #expect(account.storageError == .storageSave(-50))
        #expect(account.revision == revision)
        // The in-memory client must also retain the saved credential after a failed replacement.
        let before = AccountTMDBProtocol.count("fixture-old")
        try await account.client?.validate()
        #expect(AccountTMDBProtocol.count("fixture-old") == before + 1)
    }

    @Test func removalFailureKeepsConnectionAndCanBeRetried() throws {
        let storage = AccountTokenStorage(token: "fixture-old")
        let account = account(storage)
        storage.removeError = .storageRemove(-50)
        let revision = account.revision
        #expect(throws: TMDBAccountError.storageRemove(-50)) { try account.disconnect() }
        #expect(account.isConfigured)
        #expect(account.storageError == .storageRemove(-50))
        #expect(storage.token == "fixture-old")
        #expect(account.revision == revision)
        storage.removeError = nil
        try account.disconnect()
        #expect(!account.isConfigured)
        #expect(storage.token == nil)
        #expect(account.storageError == nil)
        #expect(account.revision == revision + 1)
    }

    @Test func readFailureIsVisibleAndRetryRestoresSavedConnection() {
        let storage = AccountTokenStorage(token: "fixture-old")
        storage.readError = .storageRead(-50)
        let account = account(storage)
        #expect(!account.isConfigured)
        #expect(account.storageError == .storageRead(-50))
        storage.readError = nil
        account.retryStorageRead()
        #expect(account.isConfigured)
        #expect(account.storageError == nil)
        #expect(account.revision == 1)
    }

    @Test func successfulReplacementAndRemovalRefreshConsumers() async throws {
        let storage = AccountTokenStorage()
        let account = account(storage)
        try await account.connect(readAccessToken: " fixture-first \n")
        #expect(account.isConfigured)
        #expect(storage.token == "fixture-first")
        let revision = account.revision
        try await account.connect(readAccessToken: "fixture-second")
        #expect(account.isConfigured)
        #expect(storage.token == "fixture-second")
        #expect(account.revision == revision + 1)
        try account.disconnect()
        #expect(account.client == nil)
        #expect(storage.token == nil)
        #expect(account.revision == revision + 2)
    }

    @Test func cancelledValidationNeverSaves() async throws {
        let storage = AccountTokenStorage()
        let account = account(storage)
        let task = Task { try await account.connect(readAccessToken: "fixture-cancel-held") }
        defer { AccountTMDBProtocol.release("fixture-cancel-held") }
        try await waitForRequest("fixture-cancel-held")
        task.cancel()
        AccountTMDBProtocol.release("fixture-cancel-held")
        do {
            try await task.value
            Issue.record("Cancelled validation saved a token")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        #expect(storage.writes == 0)
        #expect(!account.isConfigured)
    }

    @Test func lateValidationCannotOverwriteNewerConnection() async throws {
        let storage = AccountTokenStorage()
        let account = account(storage)
        let earlier = Task { try await account.connect(readAccessToken: "fixture-stale-held") }
        defer { AccountTMDBProtocol.release("fixture-stale-held") }
        try await waitForRequest("fixture-stale-held")
        try await account.connect(readAccessToken: "fixture-current")
        AccountTMDBProtocol.release("fixture-stale-held")
        await #expect(throws: CancellationError.self) { try await earlier.value }
        #expect(storage.writes == 1)
        #expect(storage.token == "fixture-current")
        #expect(account.revision == 1)
    }

    @Test func disconnectInvalidatesValidationInFlight() async throws {
        let storage = AccountTokenStorage(token: "fixture-old")
        let account = account(storage)
        let connecting = Task { try await account.connect(readAccessToken: "fixture-disconnect-held") }
        defer { AccountTMDBProtocol.release("fixture-disconnect-held") }
        try await waitForRequest("fixture-disconnect-held")
        try account.disconnect()
        AccountTMDBProtocol.release("fixture-disconnect-held")
        await #expect(throws: CancellationError.self) { try await connecting.value }
        #expect(storage.writes == 0)
        #expect(storage.token == nil)
        #expect(!account.isConfigured)
    }

    @Test func metadataCachesAreScopedToTheSavedCredential() async throws {
        let storage = AccountTokenStorage(token: "fixture-cache-first")
        let account = account(storage)
        for _ in 0..<2 {
            _ = try await account.details(imdbID: "tt0000042", type: "movie")
            _ = try await account.personDetails(id: 7)
            #expect(try await account.imdbID(tmdbID: 42, type: "movie") == "tt0000042")
        }
        #expect(AccountTMDBProtocol.count("fixture-cache-first", path: "/3/find/tt0000042") == 1)
        #expect(AccountTMDBProtocol.count("fixture-cache-first", path: "/3/person/7") == 1)
        #expect(AccountTMDBProtocol.count("fixture-cache-first", path: "/3/movie/42/external_ids") == 1)

        try await account.connect(readAccessToken: "fixture-cache-second")
        _ = try await account.details(imdbID: "tt0000042", type: "movie")
        _ = try await account.personDetails(id: 7)
        _ = try await account.imdbID(tmdbID: 42, type: "movie")
        #expect(AccountTMDBProtocol.count("fixture-cache-second", path: "/3/find/tt0000042") == 1)
        #expect(AccountTMDBProtocol.count("fixture-cache-second", path: "/3/person/7") == 1)
        #expect(AccountTMDBProtocol.count("fixture-cache-second", path: "/3/movie/42/external_ids") == 1)

        try account.disconnect()
        await #expect(throws: TMDBError.unauthorized) {
            try await account.details(imdbID: "tt0000042", type: "movie")
        }
        storage.token = "fixture-cache-restored"
        account.retryStorageRead()
        _ = try await account.details(imdbID: "tt0000042", type: "movie")
        #expect(AccountTMDBProtocol.count("fixture-cache-restored", path: "/3/find/tt0000042") == 1)
    }

    @Test func supersededMetadataResponseCannotReachTheNewConnection() async throws {
        let storage = AccountTokenStorage(token: "fixture-obsolete-details-held")
        let account = account(storage)
        let earlier = Task { try await account.details(imdbID: "tt0000042", type: "movie") }
        defer { AccountTMDBProtocol.release("fixture-obsolete-details-held") }
        try await waitForRequest("fixture-obsolete-details-held")
        try await account.connect(readAccessToken: "fixture-current-details")
        AccountTMDBProtocol.release("fixture-obsolete-details-held")
        await #expect(throws: CancellationError.self) { try await earlier.value }
        _ = try await account.details(imdbID: "tt0000042", type: "movie")
        #expect(AccountTMDBProtocol.count("fixture-current-details", path: "/3/find/tt0000042") == 1)
    }

    #if DEBUG
    @Test func temporaryCredentialChangesStayInMemory() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountTMDBProtocol.self]
        let account = TMDBAccount(temporaryReadAccessToken: " fixture-temporary ",
                                  session: URLSession(configuration: configuration))
        #expect(account.isConfigured)
        try await account.connect(readAccessToken: "fixture-temporary-replacement")
        account.retryStorageRead()
        #expect(account.isConfigured)
        try account.disconnect()
        account.retryStorageRead()
        #expect(!account.isConfigured)
        #expect(account.client == nil)
    }
    #endif

    @Test func recommendationsSkipUnknownSeedsLibraryTitlesAndTitlesWithoutIMDb() async throws {
        let account = account(AccountTokenStorage(token: "fixture-recommendations"))
        let seeds = [Recommendations.Seed(imdbID: "tt0000099", type: "movie", weight: 1),
                     Recommendations.Seed(imdbID: "tt0000042", type: "movie", weight: 0.85)]
        let previews = try await account.recommendations(for: seeds, excluding: ["tt0000051"])
        #expect(previews.map(\.id) == ["tt0000053"])
        #expect(previews.first?.name == "New")
        #expect(previews.first?.releaseInfo == "2020")
        #expect(previews.first?.poster == "https://image.tmdb.org/t/p/w500/new.jpg")
        #expect(previews.first?.logo == "https://images.metahub.space/logo/medium/tt0000053/img")

        let unknown = [Recommendations.Seed(imdbID: "tt0000099", type: "movie", weight: 1)]
        await #expect(throws: TMDBError.notFound) { try await account.recommendations(for: unknown, excluding: []) }
    }

    private func waitForRequest(_ token: String) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while AccountTMDBProtocol.count(token) == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(AccountTMDBProtocol.count(token) > 0, "Mock validation request never started")
    }
}

@MainActor
private final class AccountTokenStorage {
    var token: String?
    var writes = 0
    var readError: TMDBAccountError?
    var saveError: TMDBAccountError?
    var removeError: TMDBAccountError?

    init(token: String? = nil) { self.token = token }

    var storage: TMDBAccount.TokenStorage {
        .init(
            read: { () throws(TMDBAccountError) -> String? in
                if let error = self.readError { throw error }
                return self.token
            },
            save: { (token: String) throws(TMDBAccountError) in
                if let error = self.saveError { throw error }
                self.writes += 1
                self.token = token
            },
            remove: { () throws(TMDBAccountError) in
                if let error = self.removeError { throw error }
                self.token = nil
            }
        )
    }
}

private final class AccountTMDBProtocol: StubURLProtocol, @unchecked Sendable {
    private static let requests = Mutex<[String: Int]>([:])
    private static let heldResponses = Mutex<[String: @Sendable () -> Void]>([:])

    static func release(_ token: String) {
        let response = heldResponses.withLock { $0.removeValue(forKey: token) }
        response?()
    }

    static func count(_ token: String, path: String? = nil) -> Int {
        requests.withLock { $0[path.map { token + "|" + $0 } ?? token] ?? 0 }
    }

    override func startLoading() {
        let token = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst("Bearer ".count))
        let holdResponse = token.hasSuffix("-held") && (
            request.url?.path == "/3/authentication" || request.url?.path == "/3/find/tt0000042")
        if holdResponse {
            Self.heldResponses.withLock { responses in
                responses[token] = { @Sendable [weak self] in self?.respond(token: token) }
            }
        }
        Self.requests.withLock {
            $0[token, default: 0] += 1
            $0[token + "|" + (request.url?.path ?? ""), default: 0] += 1
        }
        if !holdResponse { respond(token: token) }
    }

    private func respond(token: String) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: token == "fixture-rejected" ? 401 : 200,
                                             httpVersion: nil, headerFields: nil) else { return }
        let body: String
        switch url.path {
        case "/3/find/tt0000042": body = #"{"movie_results":[{"id":42}]}"#
        case "/3/movie/42": body = #"""
            {"id":42,"title":"Fixture","overview":"Fixture overview","imdb_id":"tt0000042","credits":{"cast":[],"crew":[]},
             "recommendations":{"results":[{"id":51,"title":"Library"},{"id":52,"title":"No IMDb"},
              {"id":53,"title":"New","poster_path":"/new.jpg","release_date":"2020-01-01"},{"id":54,"title":"Same IMDb"}]}}
            """#
        case "/3/person/7": body = #"""
            {
              "id": 7,
              "name": "Fixture Person",
              "biography": "Fixture biography",
              "combined_credits": {
                "cast": [],
                "crew": []
              },
              "movie_credits": {
                "cast": [],
                "crew": []
              },
              "tv_credits": {
                "cast": [],
                "crew": []
              }
            }
            """#
        case "/3/movie/42/external_ids": body = #"{"id":42,"imdb_id":"tt0000042"}"#
        case "/3/movie/51/external_ids": body = #"{"id":51,"imdb_id":"tt0000051"}"#
        case "/3/movie/52/external_ids": body = #"{"id":52,"imdb_id":null}"#
        case "/3/movie/53/external_ids", "/3/movie/54/external_ids":
            body = #"{"id":\#(url.pathComponents[3]),"imdb_id":"tt0000053"}"#
        default: body = #"{"success":true}"#
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        let token = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst("Bearer ".count))
        _ = Self.heldResponses.withLock { $0.removeValue(forKey: token) }
    }
}

struct TMDBResponseCacheTests {
    @Test func concurrentLookupsShareOneFetchAndKeepTheSuccessfulResult() async throws {
        let cache = TMDBResponseCache<String, Int>(capacity: 2, lifetime: .seconds(60))
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
        let cache = TMDBResponseCache<String, Int>(capacity: 2, lifetime: .seconds(60))
        await #expect(throws: FixtureFailure.unavailable) {
            try await cache.value(for: "same") { throw FixtureFailure.unavailable }
        }
        #expect(try await cache.value(for: "same") { 7 } == 7)
    }

    @Test func cancelledWaiterLeavesSharedResultAvailable() async throws {
        let cache = TMDBResponseCache<String, Int>(capacity: 2, lifetime: .seconds(60))
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
        let expired = TMDBResponseCache<String, Int>(capacity: 2, lifetime: .zero)
        #expect(try await expired.value(for: "same") { 1 } == 1)
        #expect(try await expired.value(for: "same") { 2 } == 2)
        let bounded = TMDBResponseCache<String, Int>(capacity: 2, lifetime: .seconds(60))
        _ = try await bounded.value(for: "first") { 1 }
        _ = try await bounded.value(for: "second") { 2 }
        _ = try await bounded.value(for: "third") { 3 }
        #expect(try await bounded.value(for: "first") { 4 } == 4)
        #expect(try await bounded.value(for: "third") { 9 } == 3)
    }

    @Test func successfulMissingIdentityIsCached() async throws {
        let cache = TMDBResponseCache<Int, String?>(capacity: 2, lifetime: .seconds(60))
        #expect(try await cache.value(for: 42) { nil } == nil)
        #expect(try await cache.value(for: 42) { "tt0000042" } == nil)
    }
}
