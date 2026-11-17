import Foundation
import Observation

public enum TMDBAccountError: Error, LocalizedError, Equatable, Sendable {
    case emptyToken
    case invalidStoredToken
    case storageRead(Int32)
    case storageSave(Int32)
    case storageRemove(Int32)

    public var errorDescription: String? {
        switch self {
        case .emptyToken: "Enter the API Read Access Token from your TMDB API settings."
        case .invalidStoredToken: "The saved TMDB token couldn't be read. Replace it or remove it and try again."
        case .storageRead(let status): "Couldn't read the TMDB token from Keychain (\(status)). Try again."
        case .storageSave(let status): "Couldn't save the TMDB token in Keychain (\(status)). Try again."
        case .storageRemove(let status): "Couldn't remove the TMDB token from Keychain (\(status)). Try again."
        }
    }
}

/// A device-local API credential, separate from the user's movie library.
@MainActor @Observable
public final class TMDBAccount {
    public private(set) var isConfigured = false
    public private(set) var storageError: TMDBAccountError?
    /// Changes even when one configured token is replaced with another.
    public private(set) var revision = 0

    @ObservationIgnored private var readAccessToken: String?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let storage: TokenStorage
    @ObservationIgnored private var connectionID = UUID()
    @ObservationIgnored private var caches = MetadataCaches()

    private struct MetadataCaches {
        let details = ResponseCache<TMDBTitleKey, TMDBDetails>(capacity: 128, lifetime: .seconds(1_800))
        let people = ResponseCache<Int, TMDBPersonDetails>(capacity: 32, lifetime: .seconds(3_600))
        let identities = ResponseCache<TMDBIdentityKey, String?>(capacity: 256, lifetime: .seconds(3_600))
        let collections = ResponseCache<Int, TMDBCollection>(capacity: 32, lifetime: .seconds(3_600))
    }

    var client: TMDBClient? {
        _ = revision
        return readAccessToken.map { TMDBClient(readAccessToken: $0, session: session) }
    }

    public func details(imdbID: String, type: String) async throws -> TMDBDetails {
        try await cached(in: caches.details, TMDBTitleKey(imdbID: imdbID, type: type)) {
            try await $0.details(imdbID: imdbID, type: type)
        }
    }

    public func personDetails(id: Int) async throws -> TMDBPersonDetails {
        try await cached(in: caches.people, id) { try await $0.person(id: id) }
    }

    public func collection(id: Int) async throws -> TMDBCollection {
        try await cached(in: caches.collections, id) { try await $0.collection(id: id) }
    }

    public func imdbID(tmdbID: Int, type: String) async throws -> String? {
        try await cached(in: caches.identities, TMDBIdentityKey(tmdbID: tmdbID, type: type)) {
            try await $0.imdbID(tmdbID: tmdbID, type: type)
        }
    }

    /// A response that arrives after the token changed belongs to the old one, so it's dropped.
    private func cached<Key, Value>(in cache: ResponseCache<Key, Value>, _ key: Key,
                                    fetch: @escaping @Sendable (TMDBClient) async throws -> Value) async throws -> Value {
        guard let client else { throw TMDBError.unauthorized }
        let revision = revision
        let value = try await cache.value(for: key) { try await fetch(client) }
        try Task.checkCancellation()
        guard self.revision == revision else { throw CancellationError() }
        return value
    }

    public convenience init(session: URLSession = .shared) {
        self.init(session: session, storage: .keychain)
    }

    #if DEBUG
    /// UI automation can use runtime-supplied credentials without touching the device's Keychain.
    public convenience init(temporaryReadAccessToken: String, session: URLSession = .shared) {
        let supplied = temporaryReadAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        var token: String? = supplied.isEmpty ? nil : supplied
        self.init(session: session, storage: TokenStorage(
            read: { token }, save: { token = $0 }, remove: { token = nil }
        ))
    }
    #endif

    init(session: URLSession, storage: TokenStorage) {
        self.session = session
        self.storage = storage
        retryStorageRead()
    }

    @MainActor
    struct TokenStorage {
        var read: () throws(TMDBAccountError) -> String?
        var save: (String) throws(TMDBAccountError) -> Void
        var remove: () throws(TMDBAccountError) -> Void

        static var keychain: Self {
            Self(read: TMDBAccount.loadToken, save: TMDBAccount.saveToken, remove: TMDBAccount.removeToken)
        }
    }

    public func retryStorageRead() {
        do throws(TMDBAccountError) {
            let token = try storage.read()
            let changed = token != readAccessToken || storageError != nil
            readAccessToken = token
            isConfigured = token != nil
            storageError = nil
            if changed {
                resetMetadataCaches()
                revision &+= 1
            }
        } catch {
            storageError = error
        }
    }

    public func connect(readAccessToken: String) async throws {
        let token = readAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw TMDBAccountError.emptyToken }
        let connectionID = UUID()
        self.connectionID = connectionID
        try await TMDBClient(readAccessToken: token, session: session).validate()
        try Task.checkCancellation()
        guard self.connectionID == connectionID else { throw CancellationError() }
        do throws(TMDBAccountError) {
            try storage.save(token)
        } catch {
            storageError = error
            throw error
        }
        self.readAccessToken = token
        isConfigured = true
        storageError = nil
        resetMetadataCaches()
        revision &+= 1
    }

    public func disconnect() throws {
        connectionID = UUID()
        do throws(TMDBAccountError) {
            try storage.remove()
        } catch {
            storageError = error
            throw error
        }
        readAccessToken = nil
        isConfigured = false
        storageError = nil
        resetMetadataCaches()
        revision &+= 1
    }

    private func resetMetadataCaches() {
        // Swapping instances isolates in-flight responses from the next credential revision.
        caches = MetadataCaches()
    }

    private static let service = "li.tjh.MediaApp.tmdb"
    private static let account = "readAccessToken"

    private static func loadToken() throws(TMDBAccountError) -> String? {
        let data: Data?
        do throws(KeychainError) { data = try Keychain.read(service: service, account: account) }
        catch { throw .storageRead(error.status) }
        guard let data else { return nil }
        guard let token = String(data: data, encoding: .utf8), !token.isEmpty else { throw .invalidStoredToken }
        return token
    }

    private static func removeToken() throws(TMDBAccountError) {
        do throws(KeychainError) { try Keychain.remove(service: service, account: account) }
        catch { throw .storageRemove(error.status) }
    }

    private static func saveToken(_ token: String) throws(TMDBAccountError) {
        do throws(KeychainError) { try Keychain.save(Data(token.utf8), service: service, account: account) }
        catch { throw .storageSave(error.status) }
    }
}

private struct TMDBTitleKey: Hashable, Sendable {
    var imdbID: String
    var type: String
}

private struct TMDBIdentityKey: Hashable, Sendable {
    var tmdbID: Int
    var type: String
}
