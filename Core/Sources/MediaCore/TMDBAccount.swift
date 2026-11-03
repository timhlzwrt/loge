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

    public var client: TMDBClient? {
        _ = revision
        return readAccessToken.map { TMDBClient(readAccessToken: $0, session: session) }
    }

    public convenience init(session: URLSession = .shared) {
        self.init(session: session, storage: .keychain)
    }

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
            if changed { revision &+= 1 }
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
        revision &+= 1
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
