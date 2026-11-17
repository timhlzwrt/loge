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
        /// Each request as "METHOD path", to count round trips.
        var log: [String] = []
        /// Bytes of every reply's body.
        var sent = 0
        /// How long each reply takes, without holding the loading thread, so concurrent
        /// requests overlap as they would over a network.
        var latency: Double = 0
        /// Longer replies for single requests, by "METHOD path".
        var delays: [String: Double] = [:]
        /// An older gateway has no `changes` route.
        var supportsChanges = true
        /// How long a changes request waits before answering that nothing changed.
        var changesTimeout: Double = 2
        var notModified = 0
        static let documentNames = ["configuration", "progress", "watchLater"]
        /// The gateway's changes position: the account's revisions.
        func position(of account: String) -> [String] {
            Self.documentNames.map { documents[account + "/documents/" + $0]?["_rev"] as? String ?? "" }
        }
        mutating func respond(method: String, path: String, token: String?, body: [String: Any],
                              ifNoneMatch: String? = nil) -> (Int, [String: Any]) {
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
            if method == "GET", let document = documents[key], let rev = document["_rev"] as? String,
               ifNoneMatch == "\"\(rev)\"" {
                notModified += 1
                return (304, [:])
            }
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
        let body = requestBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let path = String(url.path.dropFirst("/v2/".count))
        let token = request.value(forHTTPHeaderField: "Authorization").map { String($0.dropFirst("Bearer ".count)) }
        let method = request.httpMethod ?? "GET"
        let (isOffline, latency) = Self.state.withLock { state in
            state.log.append(method + " " + path)
            return (state.isOffline, state.delays[method + " " + path] ?? state.latency)
        }
        if isOffline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if path == "changes" {
            let since = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "since" }?.value
            let timeout = Self.state.withLock { $0.changesTimeout }
            return answerChanges(token: token, since: since, until: .now + timeout)
        }
        let ifNoneMatch = request.value(forHTTPHeaderField: "If-None-Match")
        let (status, output, hook) = Self.state.withLock { state in
            let (status, object) = state.respond(method: method, path: path, token: token, body: body, ifNoneMatch: ifNoneMatch)
            let output = status == 304 ? Data() : try! JSONSerialization.data(withJSONObject: object)
            state.sent += output.count
            return (status, output, state.hooks.removeValue(forKey: method + " " + path))
        }
        // Hooks touch main-actor test state, so they run there before the reply. This runs on
        // URLSession's loading thread, and the tests await rather than block the main thread.
        if let hook { DispatchQueue.main.sync { MainActor.assumeIsolated { hook() } } }
        guard latency > 0 else { return respond(status, body: output) }
        later(after: latency) { $0.respond(status, body: output) }
    }

    /// Held until one of the account's documents differs from `since`, as the gateway's long poll.
    private func answerChanges(token: String?, since: String?, until deadline: Date) {
        let answer: (Int, [String: Any])? = Self.state.withLock { state in
            guard state.supportsChanges else { return (404, [:]) }
            guard let token, let account = state.devices[token] else { return (401, [:]) }
            let current = state.position(of: account)
            let known = since?.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let changed = zip(State.documentNames, current.indices).filter { name, index in
                known.map { index >= $0.count || $0[index] != current[index] } ?? !current[index].isEmpty
            }.map(\.0)
            guard since == nil || !changed.isEmpty || Date.now >= deadline else { return nil }
            return (200, ["changes": changed, "since": current.joined(separator: ",")])
        }
        guard let (status, object) = answer else {
            return later(after: 0.02) { $0.answerChanges(token: token, since: since, until: deadline) }
        }
        respond(status, body: try! JSONSerialization.data(withJSONObject: object))
    }

    override func stopLoading() { isStopped.withLock { $0 = true } }
    let isStopped = Mutex(false)

    /// Answers on the loading thread's run loop, where URLSession expects its protocol's calls.
    private func later(after seconds: Double, _ work: @escaping @Sendable (AccountGatewayProtocol) -> Void) {
        nonisolated(unsafe) let runLoop = CFRunLoopGetCurrent()
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                if !self.isStopped.withLock({ $0 }) { work(self) }
            }
            CFRunLoopWakeUp(runLoop)
        }
    }
}
