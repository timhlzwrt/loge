import Foundation
import Synchronization
@testable import LogeCore

@MainActor final class AccountMemoryStorage {
    var data: Data?
    var failSave = false
    var failRemove = false
    var storage: AccountSync.Storage { .init(load: { self.data }, save: {
        if self.failSave { throw URLError(.cannotWriteToFile) }
        self.data = $0
    }, remove: {
        if self.failRemove { throw URLError(.cannotRemoveFile) }
        self.data = nil
    }) }
}

final class AccountGatewayProtocol: StubURLProtocol, @unchecked Sendable {
    struct Invitation { let account: String }
    // The fixture's JSON dictionaries are read and mutated only inside `state`'s lock.
    struct State: @unchecked Sendable {
        var invites: [String: Invitation] = [:]
        var devices: [String: String] = [:]
        var documents: [String: [String: Any]] = [:]
        var revision = 0
        var hooks: [String: @MainActor @Sendable () -> Void] = [:]
        var isOffline = false
        /// Documents an older gateway doesn't know, refused as it refuses them.
        var unknownDocuments: Set<String> = []
        mutating func respond(method: String, path: String, token: String?, body: [String: Any]) -> (Int, [String: Any]) {
            if path == "redeem", method == "POST", let code = body["code"] as? String,
               let invite = invites[code] {
                let existing = documents.keys.contains { $0.hasPrefix(invite.account + "/documents/") }
                if existing, body["hasRecoveryKey"] as? Bool != true { return (428, [:]) }
                invites[code] = nil
                let token = UUID().uuidString; devices[token] = invite.account
                return (200, ["token": token, "accountID": invite.account, "displayName": invite.account, "deviceID": token])
            }
            guard let token, let account = devices[token] else { return (401, [:]) }
            if path == "me" {
                return (200, ["accountID": account, "displayName": account, "deviceID": token, "groups": []])
            }
            if path == "invitations", method == "POST", body["kind"] as? String == "device" {
                let code = UUID().uuidString
                invites[code] = Invitation(account: account)
                return (200, ["id": code, "code": code, "expiresAt": "2099-01-01T00:00:00Z"])
            }
            guard path.hasPrefix("documents/"), !unknownDocuments.contains(path) else { return (404, [:]) }
            let key = account + "/" + path
            if method == "GET" { return documents[key].map { (200, $0) } ?? (404, [:]) }
            if method == "PUT" {
                guard body["_rev"] as? String == documents[key]?["_rev"] as? String else { return (409, [:]) }
                revision += 1
                let rev = String(revision) + "-revision"
                var document = body; document["_rev"] = rev; documents[key] = document
                return (200, ["ok": true, "rev": rev])
            }
            return (404, [:])
        }
    }
    static let state = Mutex(State())
    override func startLoading() {
        guard let url = request.url else { return }
        if Self.state.withLock({ $0.isOffline }) {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let body = requestBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let path = String(url.path.dropFirst("/v2/".count))
        let token = request.value(forHTTPHeaderField: "Authorization").map { String($0.dropFirst("Bearer ".count)) }
        let method = request.httpMethod ?? "GET"
        let (status, output, hook) = Self.state.withLock { state in
            let (status, object) = state.respond(method: method, path: path, token: token, body: body)
            return (status, try! JSONSerialization.data(withJSONObject: object), state.hooks.removeValue(forKey: method + " " + path))
        }
        // Hooks touch main-actor test state, so they run there before the reply. This runs on
        // URLSession's loading thread, and the tests await rather than block the main thread.
        if let hook { DispatchQueue.main.sync { MainActor.assumeIsolated { hook() } } }
        respond(status, body: output)
    }
}
