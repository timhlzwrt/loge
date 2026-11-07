import CryptoKit
import Foundation

public enum SyncCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case addons, playback, appearance
    public var name: String {
        switch self {
        case .addons: "Addons"
        case .playback: "Playback preferences"
        case .appearance: "Appearance"
        }
    }
}

public struct SyncGroup: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let categories: Set<SyncCategory>
}

public struct SyncDevice: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let createdAt: String
}

public struct AccountSyncIdentity: Codable, Sendable {
    public let accountID: String
    public let displayName: String
    public let deviceID: String
    public let groups: [SyncGroup]
}

struct AccountSyncRedemption: Decodable, Sendable {
    let token: String
    let accountID: String
    let displayName: String
    let deviceID: String
    let requiresRecoveryKey: Bool?
}

struct AccountSyncInvitation: Decodable, Sendable {
    let id: String
    let code: String
    let expiresAt: String
    let groupID: String?
}

struct AccountSyncDocument: Codable, Sendable {
    let version: Int
    let ciphertext: String
    var revision: String?
    enum CodingKeys: String, CodingKey { case version, ciphertext; case revision = "_rev" }
}

struct AccountSyncCipher: Sendable {
    let key: SymmetricKey
    let context: Data
    init(key: String, resource: String) throws {
        guard let data = Data(base64Encoded: key), data.count == 32 else { throw ConfigurationSyncError.invalidKey }
        self.key = SymmetricKey(data: data)
        context = Data("loge.sync.v2.\(resource)".utf8)
    }
    func seal<T: Encodable>(_ value: T) throws -> AccountSyncDocument {
        let sealed = try AES.GCM.seal(JSONEncoder().encode(value), using: key, authenticating: context)
        guard let combined = sealed.combined else { throw ConfigurationSyncError.invalidResponse }
        let document = AccountSyncDocument(version: 2, ciphertext: combined.base64EncodedString())
        guard try JSONEncoder().encode(document).count <= ConfigurationSyncClient.maximumBytes else {
            throw ConfigurationSyncError.responseTooLarge
        }
        return document
    }
    func open<T: Decodable>(_ document: AccountSyncDocument, as: T.Type = T.self) throws -> T {
        guard document.version == 2 else { throw ConfigurationSyncError.unsupportedVersion }
        guard let data = Data(base64Encoded: document.ciphertext), data.count >= 28 else {
            throw ConfigurationSyncError.decryptionFailed
        }
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: context)
        } catch { throw ConfigurationSyncError.decryptionFailed }
        guard let value = try? JSONDecoder().decode(T.self, from: plaintext) else {
            throw ConfigurationSyncError.invalidConfiguration
        }
        return value
    }
}

private final class AccountSyncRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct AccountSyncClient: Sendable {
    let endpoint: URL
    let token: String?
    let session: URLSession

    init(endpoint: String, token: String? = nil, session: URLSession = .shared) throws {
        guard let parts = URLComponents(string: endpoint), parts.scheme == "https", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.hasSuffix("/v2"), let url = parts.url,
              token?.contains(where: \.isNewline) != true else { throw ConfigurationSyncError.invalidEndpoint }
        self.endpoint = url
        self.token = token
        self.session = session
    }

    func redeem(code: String, deviceName: String, hasRecoveryKey: Bool) async throws -> AccountSyncRedemption {
        struct Request: Encodable { let code: String; let deviceName: String; let hasRecoveryKey: Bool }
        return try await send("POST", "redeem", body: Request(code: code, deviceName: deviceName, hasRecoveryKey: hasRecoveryKey))
    }
    func me() async throws -> AccountSyncIdentity { try await send("GET", "me") }
    func devices() async throws -> [SyncDevice] { try await send("GET", "devices") }
    func revokeDevice(_ id: String) async throws {
        _ = try await request("DELETE", "devices/\(try identifier(id))")
    }
    func fetch(_ resource: String) async throws -> AccountSyncDocument? {
        let (data, status) = try await request("GET", resource, allowMissing: true)
        if status == 404 { return nil }
        guard let document = try? JSONDecoder().decode(AccountSyncDocument.self, from: data),
              document.revision?.isEmpty == false else { throw ConfigurationSyncError.invalidResponse }
        return document
    }
    func put(_ document: AccountSyncDocument, resource: String, revision: String?) async throws -> String {
        var document = document
        document.revision = revision
        struct Written: Decodable { let ok: Bool; let rev: String }
        let written: Written = try await send("PUT", resource, body: document)
        guard written.ok, !written.rev.isEmpty else { throw ConfigurationSyncError.invalidResponse }
        return written.rev
    }
    func invite(kind: String, categories: Set<SyncCategory> = [], groupID: String? = nil) async throws -> AccountSyncInvitation {
        struct Request: Encodable { let kind: String; let name: String; let categories: [SyncCategory]; let groupID: String? }
        return try await send("POST", "invitations", body: Request(kind: kind, name: "Shared setup", categories: categories.sorted { $0.rawValue < $1.rawValue }, groupID: groupID))
    }
    func revokeInvitation(_ id: String) async throws {
        _ = try await request("DELETE", "invitations/\(try identifier(id))")
    }
    func join(code: String) async throws -> SyncGroup {
        struct Request: Encodable { let code: String }
        return try await send("POST", "join", body: Request(code: code))
    }
    func leaveGroup(_ id: String) async throws {
        _ = try await request("DELETE", "groups/\(try identifier(id))/membership")
    }
    func groupResource(_ id: String) throws -> String { "groups/\(try identifier(id))/document" }

    private func identifier(_ string: String) throws -> String {
        guard !string.isEmpty, string.utf8.count <= 128,
              string.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0) })
        else { throw ConfigurationSyncError.invalidResponse }
        return string
    }
    private func send<Response: Decodable>(_ method: String, _ path: String) async throws -> Response {
        let (data, _) = try await request(method, path)
        guard let value = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ConfigurationSyncError.invalidResponse
        }
        return value
    }
    private func send<Response: Decodable>(_ method: String, _ path: String, body: some Encodable) async throws -> Response {
        let (data, _) = try await request(method, path, body: JSONEncoder().encode(body))
        guard let value = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ConfigurationSyncError.invalidResponse
        }
        return value
    }
    private func request(_ method: String, _ path: String, body: Data? = nil, allowMissing: Bool = false) async throws -> (Data, Int) {
        guard body.map({ $0.count <= ConfigurationSyncClient.maximumBytes }) ?? true else {
            throw ConfigurationSyncError.responseTooLarge
        }
        var request = URLRequest(url: endpoint.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: AccountSyncRedirectPolicy())
            guard let http = response as? HTTPURLResponse, http.url == request.url else { throw ConfigurationSyncError.invalidResponse }
            guard http.expectedContentLength <= ConfigurationSyncClient.maximumBytes else { throw ConfigurationSyncError.responseTooLarge }
            switch http.statusCode {
            case 200...299: break
            case 404 where allowMissing: return (Data(), 404)
            case 401, 403: throw ConfigurationSyncError.unauthorized
            case 409: throw ConfigurationSyncError.conflict
            case 410: throw AccountSyncClientError.expiredInvitation
            case 428: throw AccountSyncClientError.recoveryRequired
            default: throw ConfigurationSyncError.httpStatus(http.statusCode)
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < ConfigurationSyncClient.maximumBytes else { throw ConfigurationSyncError.responseTooLarge }
                data.append(byte)
            }
            return (data, http.statusCode)
        } catch let error as ConfigurationSyncError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw ConfigurationSyncError.unavailable }
    }
}

enum AccountSyncClientError: Error, LocalizedError {
    case recoveryRequired, expiredInvitation
    var errorDescription: String? {
        switch self {
        case .recoveryRequired: "This account already has encrypted data. Enter its recovery key, then retry the same code."
        case .expiredInvitation: "This code expired or was already used. Create a new code on a connected device or ask the administrator."
        }
    }
}
