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
    @ObservationIgnored private var detailsCache = ResponseCache<TMDBTitleKey, TMDBDetails>(capacity: 128, lifetime: .seconds(1_800))
    @ObservationIgnored private var peopleCache = ResponseCache<Int, TMDBPersonDetails>(capacity: 32, lifetime: .seconds(3_600))
    @ObservationIgnored private var identityCache = ResponseCache<TMDBIdentityKey, String?>(capacity: 256, lifetime: .seconds(3_600))
    @ObservationIgnored private var collectionCache = ResponseCache<Int, TMDBCollection>(capacity: 32, lifetime: .seconds(3_600))

    public var client: TMDBClient? {
        _ = revision
        return readAccessToken.map { TMDBClient(readAccessToken: $0, session: session) }
    }

    public func details(imdbID: String, type: String) async throws -> TMDBDetails {
        guard let client else { throw TMDBError.unauthorized }
        let revision = revision
        let details = try await detailsCache.value(for: TMDBTitleKey(imdbID: imdbID, type: type)) {
            try await client.details(imdbID: imdbID, type: type)
        }
        try Task.checkCancellation()
        guard self.revision == revision else { throw CancellationError() }
        return details
    }

    public func personDetails(id: Int) async throws -> TMDBPersonDetails {
        guard let client else { throw TMDBError.unauthorized }
        let revision = revision
        let person = try await peopleCache.value(for: id) { try await client.person(id: id) }
        try Task.checkCancellation()
        guard self.revision == revision else { throw CancellationError() }
        return person
    }

    public func collection(id: Int) async throws -> TMDBCollection {
        guard let client else { throw TMDBError.unauthorized }
        let revision = revision
        let collection = try await collectionCache.value(for: id) { try await client.collection(id: id) }
        try Task.checkCancellation()
        guard self.revision == revision else { throw CancellationError() }
        return collection
    }

    public func imdbID(tmdbID: Int, type: String) async throws -> String? {
        guard let client else { throw TMDBError.unauthorized }
        let revision = revision
        let imdbID = try await identityCache.value(for: TMDBIdentityKey(tmdbID: tmdbID, type: type)) {
            try await client.imdbID(tmdbID: tmdbID, type: type)
        }
        try Task.checkCancellation()
        guard self.revision == revision else { throw CancellationError() }
        return imdbID
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
        detailsCache = ResponseCache(capacity: 128, lifetime: .seconds(1_800))
        peopleCache = ResponseCache(capacity: 32, lifetime: .seconds(3_600))
        identityCache = ResponseCache(capacity: 256, lifetime: .seconds(3_600))
        collectionCache = ResponseCache(capacity: 32, lifetime: .seconds(3_600))
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
