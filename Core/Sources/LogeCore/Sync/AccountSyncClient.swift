import CryptoKit
import Foundation

/// The parts of `SyncedSettings`, appearance being Home's layout; once also what a shared
/// setup could cover.
enum SyncCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case addons, playback, appearance
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
}

struct AccountSyncRedemption: Decodable, Sendable {
    let token: String
    let accountID: String
    let displayName: String
    let deviceID: String
}

/// What a code lets its holder do: start an account, or add one of its devices. Codes for
/// the shared setups of earlier versions no longer decode.
enum AccountSyncCodeKind: String, Codable, Sendable {
    case account, device
}

/// What one device hands another, as base64 JSON: the server, a one-use invitation and,
/// for one's own devices, the key that decrypts the account.
struct AccountSyncCode: Codable {
    var version = 2
    let kind: AccountSyncCodeKind
    let endpoint: String
    let code: String
    var key: String?

    init(kind: AccountSyncCodeKind, endpoint: String, code: String, key: String? = nil) {
        self.kind = kind
        self.endpoint = endpoint
        self.code = code
        self.key = key
    }

    init(decoding string: String) throws {
        guard string.utf8.count <= 32_768,
              let data = Data(base64Encoded: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let code = try? JSONDecoder().decode(Self.self, from: data), code.version == 2,
              !code.code.isEmpty, code.code.utf8.count <= 512 else { throw SyncError.wrongCode }
        guard AccountSyncClient.endpointURL(code.endpoint) != nil else { throw SyncError.invalidEndpoint }
        self = code
    }

    func encoded() throws -> String { try JSONEncoder().encode(self).base64EncodedString() }
}

struct AccountSyncInvitation: Decodable, Sendable {
    let id: String
    let code: String
    let expiresAt: String
}

struct AccountSyncDocument: Codable, Sendable {
    let version: Int
    let ciphertext: String
    var revision: String?
    enum CodingKeys: String, CodingKey { case version, ciphertext; case revision = "_rev" }
}

/// Each resource authenticates its own name, so one document can't be replayed as another.
struct AccountSyncCipher: Sendable {
    let key: SymmetricKey
    let context: Data
    init(key: String, resource: String) throws {
        guard Self.isValidKey(key), let data = Data(base64Encoded: key) else { throw SyncError.invalidKey }
        self.key = SymmetricKey(data: data)
        context = Data("loge.sync.v2.\(resource)".utf8)
    }
    static func isValidKey(_ key: String) -> Bool { Data(base64Encoded: key)?.count == 32 }
    static func generateKey() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
    }
    func seal<T: Encodable>(_ value: T) throws -> AccountSyncDocument {
        let sealed = try AES.GCM.seal(JSONEncoder().encode(value), using: key, authenticating: context)
        guard let combined = sealed.combined else { throw SyncError.invalidResponse }
        let document = AccountSyncDocument(version: 2, ciphertext: combined.base64EncodedString())
        guard try JSONEncoder().encode(document).count <= AccountSyncClient.maximumBytes else {
            throw SyncError.tooLarge
        }
        return document
    }
    func open<T: Decodable>(_ document: AccountSyncDocument, as: T.Type = T.self) throws -> T {
        guard document.version == 2 else { throw SyncError.unsupportedVersion }
        guard let data = Data(base64Encoded: document.ciphertext), data.count >= 28 else {
            throw SyncError.decryptionFailed
        }
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: context)
        } catch { throw SyncError.decryptionFailed }
        guard let value = try? JSONDecoder().decode(T.self, from: plaintext) else {
            throw SyncError.invalidData
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

/// The gateway's HTTPS API. The bearer token never follows a redirect.
struct AccountSyncClient: Sendable {
    static let maximumBytes = 1_048_576
    let endpoint: URL
    let token: String?
    let session: URLSession

    init(endpoint: String, token: String? = nil, session: URLSession = .shared) throws {
        guard let url = Self.endpointURL(endpoint), token?.contains(where: \.isNewline) != true else {
            throw SyncError.invalidEndpoint
        }
        self.endpoint = url
        self.token = token
        self.session = session
    }

    /// An HTTPS gateway address ending in /v2, with nothing that could leak or redirect credentials.
    static func endpointURL(_ endpoint: String) -> URL? {
        guard let parts = URLComponents(string: endpoint), parts.scheme == "https", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.hasSuffix("/v2") else { return nil }
        return parts.url
    }

    /// Throws `SyncError.recoveryRequired` without using the code when the account
    /// already has data and this device brings no key to read it.
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
              document.revision?.isEmpty == false else { throw SyncError.invalidResponse }
        return document
    }
    func put(_ document: AccountSyncDocument, resource: String, revision: String?) async throws -> String {
        var document = document
        document.revision = revision
        struct Written: Decodable { let ok: Bool; let rev: String }
        let written: Written = try await send("PUT", resource, body: document)
        guard written.ok, !written.rev.isEmpty else { throw SyncError.invalidResponse }
        return written.rev
    }
    func inviteDevice() async throws -> AccountSyncInvitation {
        struct Request: Encodable { let kind: AccountSyncCodeKind }
        return try await send("POST", "invitations", body: Request(kind: .device))
    }
    func revokeInvitation(_ id: String) async throws {
        _ = try await request("DELETE", "invitations/\(try identifier(id))")
    }

    private func identifier(_ string: String) throws -> String {
        guard !string.isEmpty, string.utf8.count <= 128,
              string.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0) })
        else { throw SyncError.invalidResponse }
        return string
    }
    private func send<Response: Decodable>(_ method: String, _ path: String) async throws -> Response {
        let (data, _) = try await request(method, path)
        guard let value = try? JSONDecoder().decode(Response.self, from: data) else {
            throw SyncError.invalidResponse
        }
        return value
    }
    private func send<Response: Decodable>(_ method: String, _ path: String, body: some Encodable) async throws -> Response {
        let (data, _) = try await request(method, path, body: JSONEncoder().encode(body))
        guard let value = try? JSONDecoder().decode(Response.self, from: data) else {
            throw SyncError.invalidResponse
        }
        return value
    }
    private func request(_ method: String, _ path: String, body: Data? = nil, allowMissing: Bool = false) async throws -> (Data, Int) {
        guard body.map({ $0.count <= Self.maximumBytes }) ?? true else { throw SyncError.tooLarge }
        var request = URLRequest(url: endpoint.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: AccountSyncRedirectPolicy())
            guard let http = response as? HTTPURLResponse, http.url == request.url else { throw SyncError.invalidResponse }
            guard http.expectedContentLength <= Self.maximumBytes else { throw SyncError.tooLarge }
            switch http.statusCode {
            case 200...299: break
            case 404 where allowMissing: return (Data(), 404)
            case 401, 403: throw SyncError.unauthorized
            case 409: throw SyncError.conflict
            case 410: throw SyncError.expiredInvitation
            case 428: throw SyncError.recoveryRequired
            default: throw SyncError.httpStatus(http.statusCode)
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < Self.maximumBytes else { throw SyncError.tooLarge }
                data.append(byte)
            }
            return (data, http.statusCode)
        } catch let error as SyncError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw SyncError.unavailable }
    }
}
