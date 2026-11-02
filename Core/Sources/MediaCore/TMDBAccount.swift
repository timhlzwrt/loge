import Foundation
import Observation
import Security

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

/// A device-local API credential, separate from the user's movie library and Trakt login.
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
    @ObservationIgnored private var detailsCache = TMDBResponseCache<TMDBTitleKey, TMDBDetails>(capacity: 128, lifetime: .seconds(1_800))
    @ObservationIgnored private var peopleCache = TMDBResponseCache<Int, TMDBPersonDetails>(capacity: 32, lifetime: .seconds(3_600))
    @ObservationIgnored private var identityCache = TMDBResponseCache<TMDBIdentityKey, String?>(capacity: 256, lifetime: .seconds(3_600))

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
        detailsCache = TMDBResponseCache(capacity: 128, lifetime: .seconds(1_800))
        peopleCache = TMDBResponseCache(capacity: 32, lifetime: .seconds(3_600))
        identityCache = TMDBResponseCache(capacity: 256, lifetime: .seconds(3_600))
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "li.tjh.MediaApp.tmdb",
         kSecAttrAccount as String: "readAccessToken"]
    }

    private static func loadToken() throws(TMDBAccountError) -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TMDBAccountError.storageRead(status) }
        guard let data = value as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw TMDBAccountError.invalidStoredToken
        }
        return token
    }

    private static func removeToken() throws(TMDBAccountError) {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TMDBAccountError.storageRemove(status)
        }
    }

    private static func saveToken(_ token: String) throws(TMDBAccountError) {
        let values: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Updating in place keeps a working credential intact if replacing it fails.
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(values) { _, new in new }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw TMDBAccountError.storageSave(added) }
        } else if status != errSecSuccess {
            throw TMDBAccountError.storageSave(status)
        }
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

/// Bounded process memory only. A cancelled screen cannot cancel the shared
/// request or discard its result while another screen or prefetch still needs it.
actor TMDBResponseCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        var value: Value
        var expiresAt: ContinuousClock.Instant
    }
    private struct Flight {
        var id: UUID
        var task: Task<Value, Error>
    }
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Flight] = [:]
    private let capacity: Int
    private let lifetime: Duration

    init(capacity: Int, lifetime: Duration) {
        self.capacity = max(1, capacity)
        self.lifetime = lifetime
    }

    func value(for key: Key, fetch: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        if let entry = entries[key], entry.expiresAt > ContinuousClock.now { return entry.value }
        entries[key] = nil
        let flight: Flight
        if let pending = inFlight[key] {
            flight = pending
        } else {
            flight = Flight(id: UUID(), task: Task { try await fetch() })
            inFlight[key] = flight
        }
        do {
            let value = try await flight.task.value
            if inFlight[key]?.id == flight.id {
                inFlight[key] = nil
                let now = ContinuousClock.now
                entries = entries.filter { $0.value.expiresAt > now }
                entries[key] = Entry(value: value, expiresAt: now + lifetime)
                if entries.count > capacity, let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                    entries[oldest] = nil
                }
            }
            // Store a successful shared response even if this particular waiter left.
            try Task.checkCancellation()
            return value
        } catch {
            if inFlight[key]?.id == flight.id { inFlight[key] = nil }
            throw error
        }
    }
}
