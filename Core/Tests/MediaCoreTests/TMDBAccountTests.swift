import Foundation
import Synchronization
import Testing
@testable import MediaCore

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
        let task = Task { try await account.connect(readAccessToken: "fixture-cancel-slow") }
        try await waitForRequest("fixture-cancel-slow")
        task.cancel()
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
        let earlier = Task { try await account.connect(readAccessToken: "fixture-stale-slow") }
        try await waitForRequest("fixture-stale-slow")
        try await account.connect(readAccessToken: "fixture-current")
        await #expect(throws: CancellationError.self) { try await earlier.value }
        #expect(storage.writes == 1)
        #expect(storage.token == "fixture-current")
        #expect(account.revision == 1)
    }

    @Test func disconnectInvalidatesValidationInFlight() async throws {
        let storage = AccountTokenStorage(token: "fixture-old")
        let account = account(storage)
        let connecting = Task { try await account.connect(readAccessToken: "fixture-disconnect-slow") }
        try await waitForRequest("fixture-disconnect-slow")
        try account.disconnect()
        await #expect(throws: CancellationError.self) { try await connecting.value }
        #expect(storage.writes == 0)
        #expect(storage.token == nil)
        #expect(!account.isConfigured)
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

private final class AccountTMDBProtocol: URLProtocol, @unchecked Sendable {
    private static let requests = Mutex<[String: Int]>([:])
    private let pending = Mutex<Task<Void, Never>?>(nil)

    static func count(_ token: String) -> Int { requests.withLock { $0[token] ?? 0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst("Bearer ".count))
        Self.requests.withLock { $0[token, default: 0] += 1 }
        if token.hasSuffix("slow") {
            let task = Task.detached { @Sendable [weak self] in
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.respond(token: token)
            }
            pending.withLock { $0 = task }
        } else {
            respond(token: token)
        }
    }

    private func respond(token: String) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: token == "fixture-rejected" ? 401 : 200,
                                             httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"success":true}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { pending.withLock { $0?.cancel(); $0 = nil } }
}
