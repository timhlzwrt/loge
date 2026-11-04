import CryptoKit
import Foundation

public enum ConfigurationSyncError: Error, Equatable, LocalizedError {
    case invalidEndpoint, invalidConfiguration, invalidKey, decryptionFailed, unsupportedVersion
    case unauthorized, conflict, responseTooLarge, invalidResponse, unavailable
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter an HTTPS configuration URL without credentials, a query or a fragment."
        case .invalidConfiguration: "The configuration contains unsupported settings or addon URLs."
        case .invalidKey: "The recovery key must be a base64-encoded 256-bit key."
        case .decryptionFailed: "Couldn't decrypt the configuration. Check the recovery key."
        case .unsupportedVersion: "This configuration needs a newer version of loge."
        case .unauthorized: "The sync server didn't accept the username or password."
        case .conflict: "The server configuration changed. Sync again to review the changes."
        case .responseTooLarge: "The configuration exceeds the 1 MiB limit."
        case .invalidResponse: "The server didn't return a compatible configuration response."
        case .unavailable: "Couldn't reach the sync server. Your local setup is unchanged."
        case .httpStatus(let status): "The sync server responded with HTTP \(status)."
        }
    }
}

public struct SyncedConfiguration: Codable, Equatable, Sendable {
    public var addonURLs: [String]
    public var audioLanguage: String
    public var subtitleLanguage: String
    public var subtitleScale: Double
    public var maximumSourceGigabytes: Int
    public var accent: String

    public init(addonURLs: [String] = [], audioLanguage: String = "en", subtitleLanguage: String = "",
                subtitleScale: Double = 1, maximumSourceGigabytes: Int = 50, accent: String = "white") {
        self.addonURLs = addonURLs
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subtitleScale = subtitleScale
        self.maximumSourceGigabytes = maximumSourceGigabytes
        self.accent = accent
    }

    public func validated() throws -> Self {
        guard addonURLs.count <= 100,
              Set(addonURLs).count == addonURLs.count,
              ([""] + LanguageCodes.common).contains(audioLanguage),
              ([""] + LanguageCodes.common).contains(subtitleLanguage),
              [0.8, 1, 1.25, 1.6].contains(subtitleScale),
              [0, 10, 25, 50, 100].contains(maximumSourceGigabytes),
              ["white", "amber", "coral", "mint", "sky"].contains(accent)
        else { throw ConfigurationSyncError.invalidConfiguration }
        for url in addonURLs {
            guard url.utf8.count <= 32_768,
                  let client = try? AddonClient(manifestURL: url), client.manifestURL == url,
                  url != AddonStore.cinemetaURL
            else { throw ConfigurationSyncError.invalidConfiguration }
        }
        return self
    }

    /// The ordered addon list is one field: unioning lists would resurrect removals.
    public static func merged(base: Self, local: Self, remote: Self) -> ConfigurationMerge {
        var result = local
        var conflicts = Set<ConfigurationField>()
        func choose<T: Equatable>(_ key: WritableKeyPath<Self, T>, _ field: ConfigurationField) {
            if local[keyPath: key] == base[keyPath: key] {
                result[keyPath: key] = remote[keyPath: key]
            } else if remote[keyPath: key] != base[keyPath: key], local[keyPath: key] != remote[keyPath: key] {
                conflicts.insert(field)
            }
        }
        choose(\.addonURLs, .addonURLs)
        choose(\.audioLanguage, .audioLanguage)
        choose(\.subtitleLanguage, .subtitleLanguage)
        choose(\.subtitleScale, .subtitleScale)
        choose(\.maximumSourceGigabytes, .maximumSourceGigabytes)
        choose(\.accent, .accent)
        return ConfigurationMerge(configuration: result, conflicts: conflicts)
    }
}

public enum ConfigurationField: String, Codable, CaseIterable, Sendable {
    case addonURLs, audioLanguage, subtitleLanguage, subtitleScale, maximumSourceGigabytes, accent
}

public struct ConfigurationMerge: Sendable {
    public let configuration: SyncedConfiguration
    public let conflicts: Set<ConfigurationField>
}

public struct EncryptedConfiguration: Codable, Equatable, Sendable {
    public let version: Int
    public let ciphertext: String

    public init(version: Int = 1, ciphertext: String) {
        self.version = version
        self.ciphertext = ciphertext
    }
}

public struct ConfigurationCipher: Sendable {
    private let key: SymmetricKey
    private static let context = Data("loge.configuration.v1".utf8)

    public init(key: String) throws {
        guard let data = Data(base64Encoded: key), data.count == 32 else { throw ConfigurationSyncError.invalidKey }
        self.key = SymmetricKey(data: data)
    }

    public static func generateKey() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
    }

    public func seal(_ configuration: SyncedConfiguration) throws -> EncryptedConfiguration {
        let data = try JSONEncoder().encode(configuration.validated())
        let sealed = try AES.GCM.seal(data, using: key, authenticating: Self.context)
        guard let combined = sealed.combined else { throw ConfigurationSyncError.invalidResponse }
        let envelope = EncryptedConfiguration(ciphertext: combined.base64EncodedString())
        guard try JSONEncoder().encode(envelope).count <= ConfigurationSyncClient.maximumBytes else {
            throw ConfigurationSyncError.responseTooLarge
        }
        return envelope
    }

    public func open(_ envelope: EncryptedConfiguration) throws -> SyncedConfiguration {
        guard envelope.version == 1 else { throw ConfigurationSyncError.unsupportedVersion }
        guard envelope.ciphertext.utf8.count <= ConfigurationSyncClient.maximumBytes,
              let data = Data(base64Encoded: envelope.ciphertext), data.count >= 28
        else { throw ConfigurationSyncError.decryptionFailed }
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: Self.context)
        } catch { throw ConfigurationSyncError.decryptionFailed }
        guard let config = try? JSONDecoder().decode(SyncedConfiguration.self, from: plaintext) else {
            throw ConfigurationSyncError.invalidConfiguration
        }
        return try config.validated()
    }
}

public struct RemoteConfiguration: Sendable {
    public let revision: String
    public let envelope: EncryptedConfiguration
}

private final class ConfigurationRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// A single encrypted CouchDB document. Credentials never follow redirects.
public struct ConfigurationSyncClient: Sendable {
    public static let maximumBytes = 1_048_576
    public let endpoint: URL
    private let authorization: String
    private let session: URLSession

    public init(endpoint: String, username: String, password: String, session: URLSession = .shared) throws {
        guard let components = URLComponents(string: endpoint), components.scheme == "https",
              components.host?.isEmpty == false, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil, components.path != "", components.path != "/",
              let url = components.url, !username.isEmpty, !username.contains(":"),
              !username.contains(where: \.isNewline), !password.isEmpty
        else { throw ConfigurationSyncError.invalidEndpoint }
        self.endpoint = url
        authorization = "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
        self.session = session
    }

    public func fetch() async throws -> RemoteConfiguration? {
        let (data, response) = try await request(method: "GET")
        if response.statusCode == 404 { return nil }
        try check(response, expected: [200])
        guard let document = try? JSONDecoder().decode(Document.self, from: data),
              let revision = document.revision, !revision.isEmpty
        else { throw ConfigurationSyncError.invalidResponse }
        return RemoteConfiguration(revision: revision,
                                   envelope: EncryptedConfiguration(version: document.version, ciphertext: document.ciphertext))
    }

    public func put(_ envelope: EncryptedConfiguration, revision: String?) async throws -> String {
        let body = try JSONEncoder().encode(Document(revision: revision, version: envelope.version, ciphertext: envelope.ciphertext))
        guard body.count <= Self.maximumBytes else { throw ConfigurationSyncError.responseTooLarge }
        let (data, response) = try await request(method: "PUT", body: body)
        try check(response, expected: [201, 202])
        guard let written = try? JSONDecoder().decode(Written.self, from: data), written.ok,
              !written.rev.isEmpty else { throw ConfigurationSyncError.invalidResponse }
        return written.rev
    }

    private func request(method: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: ConfigurationRedirectPolicy())
            guard let http = response as? HTTPURLResponse, http.url == endpoint else {
                throw ConfigurationSyncError.invalidResponse
            }
            guard response.expectedContentLength <= Self.maximumBytes else { throw ConfigurationSyncError.responseTooLarge }
            var data = Data()
            for try await byte in bytes {
                guard data.count < Self.maximumBytes else { throw ConfigurationSyncError.responseTooLarge }
                data.append(byte)
            }
            return (data, http)
        } catch let error as ConfigurationSyncError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw ConfigurationSyncError.unavailable }
    }

    private func check(_ response: HTTPURLResponse, expected: Set<Int>) throws {
        switch response.statusCode {
        case 401, 403: throw ConfigurationSyncError.unauthorized
        case 409: throw ConfigurationSyncError.conflict
        case let status where expected.contains(status): return
        default: throw ConfigurationSyncError.httpStatus(response.statusCode)
        }
    }

    private struct Document: Codable {
        let revision: String?
        let version: Int
        let ciphertext: String
        enum CodingKeys: String, CodingKey { case revision = "_rev", version, ciphertext }
    }
    private struct Written: Decodable { let ok: Bool; let rev: String }
}
