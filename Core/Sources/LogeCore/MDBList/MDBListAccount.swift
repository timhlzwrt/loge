import Foundation
import Observation

public enum MDBListAccountError: Error, LocalizedError, Equatable, Sendable {
    case emptyKey
    case invalidStoredKey
    case storageRead(Int32)
    case storageSave(Int32)
    case storageRemove(Int32)

    public var errorDescription: String? {
        switch self {
        case .emptyKey: "Enter the API key from your MDBList preferences."
        case .invalidStoredKey: "The saved MDBList key couldn't be read. Replace it or remove it and try again."
        case .storageRead(let status): "Couldn't read the MDBList key from Keychain (\(status)). Try again."
        case .storageSave(let status): "Couldn't save the MDBList key in Keychain (\(status)). Try again."
        case .storageRemove(let status): "Couldn't remove the MDBList key from Keychain (\(status)). Try again."
        }
    }
}

/// A device-local API key for MDBList, which supplies the Letterboxd and Rotten Tomatoes scores.
/// Built like `TMDBAccount`: checked before it's saved, kept in the Keychain, never synced.
@MainActor @Observable
public final class MDBListAccount {
    public private(set) var isConfigured = false
    public private(set) var storageError: MDBListAccountError?
    /// Changes even when one key is replaced with another.
    public private(set) var revision = 0

    @ObservationIgnored private var apiKey: String?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let storage: KeyStorage
    @ObservationIgnored private var connectionID = UUID()
    /// A free key allows 1,000 requests a day and scores move slowly, so a title is asked for
    /// once in a while rather than on every visit.
    @ObservationIgnored private var cache = TMDBResponseCache<String, TitleScores>(capacity: 256, lifetime: .seconds(21_600))

    public convenience init(session: URLSession = .shared) {
        self.init(session: session, storage: .keychain)
    }

    #if DEBUG
    /// UI automation can use a runtime-supplied key without touching the device's Keychain.
    public convenience init(temporaryAPIKey: String, session: URLSession = .shared) {
        var key: String? = temporaryAPIKey
        self.init(session: session, storage: KeyStorage(read: { key }, save: { key = $0 }, remove: { key = nil }))
    }
    #endif

    init(session: URLSession, storage: KeyStorage) {
        self.session = session
        self.storage = storage
        retryStorageRead()
    }

    @MainActor
    struct KeyStorage {
        var read: () throws(MDBListAccountError) -> String?
        var save: (String) throws(MDBListAccountError) -> Void
        var remove: () throws(MDBListAccountError) -> Void

        static var keychain: Self {
            Self(read: MDBListAccount.loadKey, save: MDBListAccount.saveKey, remove: MDBListAccount.removeKey)
        }
    }

    public func retryStorageRead() {
        do throws(MDBListAccountError) {
            let key = try storage.read()
            let changed = key != apiKey || storageError != nil
            apiKey = key
            isConfigured = key != nil
            storageError = nil
            if changed { reset() }
        } catch {
            storageError = error
        }
    }

    /// The key replaces a saved one only once MDBList has accepted it.
    public func connect(apiKey: String) async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MDBListAccountError.emptyKey }
        let connectionID = UUID()
        self.connectionID = connectionID
        try await MDBListClient(apiKey: key, session: session).validate()
        try Task.checkCancellation()
        guard self.connectionID == connectionID else { throw CancellationError() }
        do throws(MDBListAccountError) {
            try storage.save(key)
        } catch {
            storageError = error
            throw error
        }
        self.apiKey = key
        isConfigured = true
        storageError = nil
        reset()
    }

    public func disconnect() throws {
        connectionID = UUID()
        do throws(MDBListAccountError) {
            try storage.remove()
        } catch {
            storageError = error
            throw error
        }
        apiKey = nil
        isConfigured = false
        storageError = nil
        reset()
    }

    public func scores(imdbID: String, type: String) async throws -> TitleScores {
        guard let apiKey else { throw MDBListError.unauthorized }
        let client = MDBListClient(apiKey: apiKey, session: session)
        let revision = revision
        let scores = try await cache.value(for: "\(type)/\(imdbID)") { try await client.scores(imdbID: imdbID, type: type) }
        try Task.checkCancellation()
        guard self.revision == revision else { throw CancellationError() }
        return scores
    }

    private func reset() {
        // A new instance keeps answers still in flight for the old key out of the next one's cache.
        cache = TMDBResponseCache(capacity: 256, lifetime: .seconds(21_600))
        revision &+= 1
    }

    private static let service = "li.tjh.MediaApp.mdblist"
    private static let account = "apiKey"

    private static func loadKey() throws(MDBListAccountError) -> String? {
        let data: Data?
        do throws(KeychainError) { data = try Keychain.read(service: service, account: account) }
        catch { throw .storageRead(error.status) }
        guard let data else { return nil }
        guard let key = String(data: data, encoding: .utf8), !key.isEmpty else { throw .invalidStoredKey }
        return key
    }

    private static func saveKey(_ key: String) throws(MDBListAccountError) {
        do throws(KeychainError) { try Keychain.save(Data(key.utf8), service: service, account: account) }
        catch { throw .storageSave(error.status) }
    }

    private static func removeKey() throws(MDBListAccountError) {
        do throws(KeychainError) { try Keychain.remove(service: service, account: account) }
        catch { throw .storageRemove(error.status) }
    }
}
