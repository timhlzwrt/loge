import Foundation
import Synchronization
import Testing
@testable import LogeCore

/// The client against the examples `Tools/sync-gateway/test_gateway.py` checks the gateway
/// against, so a field renamed on either side fails one of the two suites.
@Suite(.serialized)
struct SyncGatewayContractTests {
    let contract: [String: [String: Any]]

    init() throws {
        let url = try #require(Bundle.module.url(forResource: "sync-gateway-contract", withExtension: "json", subdirectory: "Fixtures"))
        contract = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]])
    }

    func keys(_ name: String, _ part: String) throws -> Set<String> {
        let value = try #require(contract[name]?[part])
        return Set(try #require(((value as? [Any])?.first ?? value) as? [String: Any]).keys)
    }

    func respond(_ path: String, with name: String) throws {
        let body = try JSONSerialization.data(withJSONObject: try #require(contract[name]?["response"]))
        ContractProtocol.state.withLock { $0.responses[path] = body }
    }

    func sent(_ path: String) throws -> Set<String> {
        let body = try #require(ContractProtocol.state.withLock { $0.requests[path] })
        return Set(try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any]).keys)
    }

    @Test func clientSendsAndDecodesTheGatewayContract() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContractProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = try AccountSyncClient(endpoint: "https://sync.example/v2", token: "token", session: session)

        try respond("redeem", with: "redeem")
        let redemption = try await client.redeem(code: "code", deviceName: "iPhone", hasRecoveryKey: false)
        #expect(redemption.accountID == "0123456789abcdef0123456789abcdef")
        #expect(try sent("redeem") == keys("redeem", "request"))

        try respond("me", with: "me")
        #expect(try await client.me().groups.first?.categories == [.addons])

        try respond("invitations", with: "inviteDevice")
        _ = try await client.invite(kind: .device)
        #expect(try sent("invitations") == keys("inviteDevice", "request"))

        try respond("invitations", with: "inviteShare")
        #expect(try await client.invite(kind: .share, categories: [.addons]).groupID != nil)
        #expect(try sent("invitations") == keys("inviteShare", "request"))

        try respond("join", with: "join")
        #expect(try await client.join(code: "share-code").categories == [.addons])
        #expect(try sent("join") == keys("join", "request"))

        try respond("documents/progress", with: "getDocument")
        let document = try #require(try await client.fetch("documents/progress"))
        try respond("documents/progress", with: "putDocument")
        #expect(try await client.put(document, resource: "documents/progress", revision: nil) == "1")
        #expect(try sent("documents/progress") == keys("putDocument", "request"))

        try respond("devices", with: "devices")
        #expect(try await client.devices().first?.name == "iPhone")
    }
}

private final class ContractProtocol: StubURLProtocol, @unchecked Sendable {
    struct State { var responses: [String: Data] = [:]; var requests: [String: Data] = [:] }
    static let state = Mutex(State())
    override func startLoading() {
        guard let url = request.url else { return }
        let path = String(url.path.dropFirst("/v2/".count))
        let body = requestBody
        let response = Self.state.withLock { state in
            if let body { state.requests[path] = body }
            return state.responses[path]
        }
        respond(response == nil ? 404 : 200, body: response ?? Data())
    }
}
