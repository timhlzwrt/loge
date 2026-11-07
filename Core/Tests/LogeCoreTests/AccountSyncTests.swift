import Foundation
import Synchronization
import Testing
@testable import LogeCore

@MainActor @Suite(.serialized)
struct AccountSyncTests {
    func fixture(session suppliedSession: URLSession? = nil, credentials: Data? = nil) -> (AccountSync, AddonStore, LibraryStore, UserDefaults, AccountMemoryStorage) {
        let defaults = UserDefaults(suiteName: "account-v2-\(UUID())")!
        let addons = AddonStore(defaults: defaults, loadManifest: { _ in throw URLError(.cannotConnectToHost) })
        let library = LibraryStore(defaults: defaults)
        let storage = AccountMemoryStorage()
        storage.data = credentials
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountGatewayProtocol.self]
        let session = suppliedSession ?? URLSession(configuration: configuration)
        return (AccountSync(addons: addons, library: library, defaults: defaults, storage: storage.storage, session: session), addons, library, defaults, storage)
    }
    func enrollment(_ user: String) throws -> String {
        let invite = UUID().uuidString
        AccountGatewayProtocol.state.withLock { $0.invites[invite] = .init(account: user, group: nil) }
        return try JSONSerialization.data(withJSONObject: ["version":2,"kind":"account","endpoint":"https://sync.example/v2","code":invite]).base64EncodedString()
    }
    func reset() { AccountGatewayProtocol.state.withLock { $0 = .init() } }

    func restored(storage: AccountMemoryStorage, addons: AddonStore, library: LibraryStore, defaults: UserDefaults) -> AccountSync {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountGatewayProtocol.self]
        return AccountSync(addons: addons, library: library, defaults: defaults, storage: storage.storage,
                           session: URLSession(configuration: configuration))
    }

    func movie(_ id: String = "movie") -> WatchItem { WatchItem(id: id, type: "movie", metaID: id, title: id) }

    @Test func relaunchBeforeInitialChoiceDoesNotImportOrUploadWithoutConsent() async throws {
        reset()
        let (first, _, _, _, _) = fixture()
        await first.connect(code: try enrollment("alice")); await first.resolve(useLocal: true)
        let code = try await first.makeDeviceCode()
        let (second, addons, library, defaults, storage) = fixture()
        library.record(movie("local-only"), position: 120, duration: 1000)
        defaults.set("coral", forKey: "accentColor")
        await second.connect(code: code)
        #expect(second.needsChoice)
        let before = AccountGatewayProtocol.state.withLock { $0.revision }
        let reopened = restored(storage: storage, addons: addons, library: LibraryStore(defaults: defaults), defaults: defaults)
        #expect(reopened.needsChoice)
        await reopened.sync()
        #expect(reopened.needsChoice)
        #expect(AccountGatewayProtocol.state.withLock { $0.revision } == before)
        await reopened.resolve(useLocal: true)
        #expect(!reopened.needsChoice && reopened.errorMessage == nil)
        #expect(defaults.string(forKey: "accentColor") == "coral")
        try reopened.disconnect(); try first.disconnect()
    }

    @Test func disconnectAndUnreadableCredentialsRestoreTheLocalAddonSetup() async throws {
        reset()
        let (account, addons, library, defaults, storage) = fixture()
        try addons.replaceManifestURLs(["https://local.example/manifest.json"])
        defaults.set("mint", forKey: "accentColor")
        await account.connect(code: try enrollment("alice")); await account.resolve(useLocal: false)
        try addons.replaceManifestURLs(["https://private.example/manifest.json"])
        defaults.set("coral", forKey: "accentColor")
        storage.failRemove = true
        #expect(throws: (any Error).self) { try account.disconnect() }
        #expect(account.isConnected && addons.addons.first?.host == "private.example")
        storage.failRemove = false
        let broken = AccountSync(addons: addons, library: library, defaults: defaults,
                                 storage: .init(load: { throw URLError(.cannotOpenFile) }, save: { _ in }, remove: {}),
                                 session: .shared)
        #expect(!broken.isConnected && library.activeProfileID == nil)
        #expect(addons.addons.first?.host == "local.example")
        #expect(defaults.string(forKey: "accentColor") == "mint")
        let reopened = restored(storage: storage, addons: addons, library: library, defaults: defaults)
        #expect(reopened.isConnected && addons.addons.first?.host == "private.example")
        #expect(defaults.string(forKey: "accentColor") == "coral")
        try reopened.disconnect()
        #expect(addons.addons.first?.host == "local.example")
    }

    @Test func missingRecoveryKeyDoesNotConsumeReturningAccountInvitation() async throws {
        reset()
        let (first, _, _, _, _) = fixture()
        await first.connect(code: try enrollment("alice")); await first.resolve(useLocal: true)
        let invitation = try enrollment("alice")
        let (second, _, _, _, _) = fixture()
        await second.connect(code: invitation)
        #expect(!second.isConnected)
        await second.connect(code: invitation, recoveryKey: first.recoveryKey)
        #expect(second.isConnected && second.needsChoice)
        await second.resolve(useLocal: false)
        #expect(second.errorMessage == nil)
        try first.disconnect(); try second.disconnect()
    }

    @Test func shareCredentialFailureRollsBackTheUnpublishedGroup() async throws {
        reset()
        let (account, _, _, _, storage) = fixture()
        await account.connect(code: try enrollment("alice")); await account.resolve(useLocal: true)
        storage.failSave = true
        await #expect(throws: (any Error).self) { try await account.makeShareCode(categories: [.addons]) }
        #expect(AccountGatewayProtocol.state.withLock { $0.groups.isEmpty })
        #expect(account.sharedGroups.isEmpty)
        storage.failSave = false
        _ = try await account.makeShareCode(categories: [.addons])
        #expect(account.sharedGroups.count == 1)
        try account.disconnect()
    }

    @Test func wrongSharedKeyDoesNotLeaveAnUnusableMembership() async throws {
        reset()
        let (alice, _, _, _, _) = fixture()
        await alice.connect(code: try enrollment("alice")); await alice.resolve(useLocal: true)
        let valid = try await alice.makeShareCode(categories: [.addons])
        var object = try #require(try JSONSerialization.jsonObject(with: Data(base64Encoded: valid)!) as? [String: Any])
        object["key"] = ConfigurationCipher.generateKey()
        let bad = try JSONSerialization.data(withJSONObject: object).base64EncodedString()
        let (bob, _, _, _, _) = fixture()
        await bob.connect(code: try enrollment("bob")); await bob.resolve(useLocal: false)
        await bob.joinShare(code: bad)
        #expect(bob.errorMessage != nil && bob.sharedGroups.isEmpty)
        #expect(AccountGatewayProtocol.state.withLock { $0.groups.values.allSatisfy { !$0.members.contains("bob") } })
        await bob.joinShare(code: try await alice.makeShareCode(categories: [.addons]))
        #expect(bob.errorMessage == nil && bob.sharedGroups.count == 1)
        try alice.disconnect(); try bob.disconnect()
    }

    @Test func disconnectDuringJoinRollsBackOnlyTheNewMembership() async throws {
        reset()
        let (alice, _, _, _, _) = fixture()
        await alice.connect(code: try enrollment("alice")); await alice.resolve(useLocal: true)
        let code = try await alice.makeShareCode(categories: [.addons])
        let (bob, _, library, _, _) = fixture()
        await bob.connect(code: try enrollment("bob")); await bob.resolve(useLocal: false)
        AccountGatewayProtocol.state.withLock { $0.hooks["POST join"] = {
            do { try bob.disconnect() } catch { Issue.record(error) }
        } }
        await bob.joinShare(code: code)
        #expect(!bob.isConnected && library.activeProfileID == nil)
        #expect(AccountGatewayProtocol.state.withLock { $0.groups.values.allSatisfy { !$0.members.contains("bob") } })
        #expect(alice.sharedGroups.count == 1)
        try alice.disconnect()
    }

    @Test func revokedSharedMembershipClearsItsPendingChoice() async throws {
        reset()
        let (alice, addonsA, _, _, _) = fixture()
        await alice.connect(code: try enrollment("alice")); await alice.resolve(useLocal: true)
        let code = try await alice.makeShareCode(categories: [.addons])
        let (bob, addonsB, _, _, _) = fixture()
        await bob.connect(code: try enrollment("bob")); await bob.resolve(useLocal: false)
        await bob.joinShare(code: code)
        try addonsA.replaceManifestURLs(["https://a.example/manifest.json"])
        try addonsB.replaceManifestURLs(["https://b.example/manifest.json"])
        await alice.sync(); await bob.sync()
        #expect(bob.needsChoice)
        let group = try #require(alice.sharedGroups.first)
        await alice.leaveGroup(id: group.id)
        await bob.sync()
        #expect(!bob.needsChoice && bob.sharedGroups.isEmpty)
        _ = try await bob.makeShareCode(categories: [.addons])
        try alice.disconnect(); try bob.disconnect()
    }

    @Test func simultaneousGroupConflictsAreReviewedWithoutReplacingTheFirstChoice() async throws {
        reset()
        let (alice, addonsA, _, defaultsA, _) = fixture()
        await alice.connect(code: try enrollment("alice")); await alice.resolve(useLocal: true)
        let addonsCode = try await alice.makeShareCode(categories: [.addons])
        let playbackCode = try await alice.makeShareCode(categories: [.playback])
        let (bob, addonsB, _, defaultsB, _) = fixture()
        await bob.connect(code: try enrollment("bob")); await bob.resolve(useLocal: false)
        await bob.joinShare(code: addonsCode); await bob.joinShare(code: playbackCode)
        try addonsA.replaceManifestURLs(["https://a.example/manifest.json"])
        try addonsB.replaceManifestURLs(["https://b.example/manifest.json"])
        defaultsA.set("de", forKey: "audioLanguage")
        defaultsB.set("fr", forKey: "audioLanguage")
        await alice.sync(); await bob.sync()
        #expect(bob.choiceSummary.contains("Addons"))
        await bob.sync()
        #expect(bob.choiceSummary.contains("Addons"))
        await bob.resolve(useLocal: false)
        #expect(bob.needsChoice && bob.choiceSummary.contains("Playback preferences"))
        await bob.resolve(useLocal: false)
        #expect(!bob.needsChoice && defaultsB.string(forKey: "audioLanguage") == "de")
        try alice.disconnect(); try bob.disconnect()
    }

    @Test func playbackConflictDoesNotBlockOtherTitlesOrSettingsAndSurvivesRelaunch() async throws {
        reset()
        let (alice, addonsA, libraryA, defaultsA, storageA) = fixture()
        await alice.connect(code: try enrollment("alice")); await alice.resolve(useLocal: true)
        libraryA.record(movie(), position: 100, duration: 1000)
        await alice.sync()
        let (second, _, libraryB, _, _) = fixture()
        await second.connect(code: try await alice.makeDeviceCode()); await second.resolve(useLocal: false)
        libraryA.record(movie(), position: 200, duration: 1000)
        libraryB.record(movie(), position: 300, duration: 1000)
        await second.sync(); await alice.sync()
        #expect(alice.conflictingProgressIDs == ["movie"])
        defaultsA.set("coral", forKey: "accentColor")
        libraryA.record(movie("independent"), position: 400, duration: 1000)
        await alice.sync(); await second.sync()
        #expect(alice.needsChoice)
        #expect(libraryB.progress["independent"]?.position == 400)
        let reopened = restored(storage: storageA, addons: addonsA, library: LibraryStore(defaults: defaultsA), defaults: defaultsA)
        await reopened.sync()
        #expect(reopened.conflictingProgressIDs == ["movie"])
        await reopened.resolve(useLocal: false)
        #expect(!reopened.needsChoice)
        #expect(defaultsA.string(forKey: "accentColor") == "coral")
        try reopened.disconnect(); try second.disconnect()
    }

    @Test func staleConflictChoiceCannotOverwriteANewerRemotePosition() async throws {
        reset()
        let (alice, _, libraryA, _, _) = fixture()
        await alice.connect(code: try enrollment("alice")); await alice.resolve(useLocal: true)
        libraryA.record(movie(), position: 100, duration: 1000)
        await alice.sync()
        let (second, _, libraryB, _, _) = fixture()
        await second.connect(code: try await alice.makeDeviceCode()); await second.resolve(useLocal: false)
        libraryA.record(movie(), position: 200, duration: 1000)
        libraryB.record(movie(), position: 300, duration: 1000)
        await second.sync(); await alice.sync()
        #expect(alice.needsChoice)
        libraryB.record(movie(), position: 400, duration: 1000)
        await second.sync()
        let before = AccountGatewayProtocol.state.withLock { $0.revision }
        await alice.resolve(useLocal: true)
        #expect(alice.needsChoice)
        #expect(AccountGatewayProtocol.state.withLock { $0.revision } == before)
        #expect(libraryB.progress["movie"]?.position == 400)
        await alice.resolve(useLocal: false)
        #expect(!alice.needsChoice && libraryA.progress["movie"]?.position == 400)
        try alice.disconnect(); try second.disconnect()
    }

    @Test func lateEditsKeepBothOriginalAndNewPlaybackConflicts() async throws {
        reset()
        let (alice, _, libraryA, _, _) = fixture()
        await alice.connect(code: try enrollment("alice")); await alice.resolve(useLocal: true)
        libraryA.record(movie("a"), position: 100, duration: 1000)
        libraryA.record(movie("b"), position: 100, duration: 1000)
        await alice.sync()
        let (second, _, libraryB, _, _) = fixture()
        await second.connect(code: try await alice.makeDeviceCode()); await second.resolve(useLocal: false)
        libraryA.record(movie("a"), position: 200, duration: 1000)
        libraryA.record(movie("c"), position: 100, duration: 1000)
        libraryB.record(movie("a"), position: 300, duration: 1000)
        libraryB.record(movie("b"), position: 300, duration: 1000)
        await second.sync()
        let b = movie("b")
        AccountGatewayProtocol.state.withLock { $0.hooks["PUT documents/progress"] = {
            libraryA.record(b, position: 400, duration: 1000)
        } }
        await alice.sync()
        #expect(Set(alice.conflictingProgressIDs) == ["a", "b"])
        #expect(libraryA.progress["b"]?.position == 400)
        await second.sync()
        #expect(libraryB.progress["c"]?.position == 100)
        try alice.disconnect(); try second.disconnect()
    }

    @Test func newAccountRequiresExplicitImportAndDisconnectRestoresLocalLibrary() async throws {
        reset()
        let (account, _, library, defaults, storage) = fixture()
        library.record(WatchItem(id: "local", type: "movie", metaID: "local", title: "Local"), position: 120, duration: 1000)
        await account.connect(code: try enrollment("alice"))
        #expect(account.isConnected && account.needsChoice)
        #expect(library.activeProfileID != nil && library.progress["local"] == nil)
        #expect(AccountGatewayProtocol.state.withLock { $0.documents.isEmpty })
        await account.resolve(useLocal: true)
        #expect(account.errorMessage == nil && library.progress["local"]?.position == 120)
        #expect(storage.data != nil)
        let baseline = try #require(defaults.dictionaryRepresentation().first { $0.key.hasPrefix("accountSyncBaseline.") }?.value as? Data)
        #expect(!String(decoding: baseline, as: UTF8.self).contains("audioLanguage"))
        try account.disconnect()
        #expect(library.activeProfileID == nil && library.progress["local"]?.position == 120)
        #expect(storage.data == nil)
    }

    @Test func ownDeviceGetsPrivateProgressAndOtherAccountDoesNot() async throws {
        reset()
        let (alice, _, libraryA, _, _) = fixture()
        await alice.connect(code: try enrollment("alice")); await alice.resolve(useLocal: true)
        libraryA.record(WatchItem(id: "movie", type: "movie", metaID: "movie", title: "Movie"), position: 140, duration: 1000)
        await alice.sync()
        let code = try await alice.makeDeviceCode()
        let (second, _, libraryB, _, _) = fixture()
        await second.connect(code: code); await second.resolve(useLocal: false)
        #expect(second.errorMessage == nil && libraryB.progress["movie"]?.position == 140)
        let (bob, _, libraryC, _, _) = fixture()
        await bob.connect(code: try enrollment("bob")); await bob.resolve(useLocal: false)
        #expect(libraryC.progress.isEmpty)
        #expect(alice.displayName == "alice" && bob.displayName == "bob")
        try alice.disconnect(); try second.disconnect(); try bob.disconnect()
    }

    @Test func sharedAddonsPropagateWithoutSharingPersonalSettingsOrProgress() async throws {
        reset()
        let (alice, addonsA, libraryA, defaultsA, _) = fixture()
        await alice.connect(code: try enrollment("alice")); await alice.resolve(useLocal: true)
        try addonsA.replaceManifestURLs(["https://first.example/manifest.json", "https://second.example/manifest.json"])
        defaultsA.set("coral", forKey: "accentColor")
        libraryA.record(WatchItem(id: "private", type: "movie", metaID: "private", title: "Private"), position: 180, duration: 1000)
        await alice.sync()
        let share = try await alice.makeShareCode(categories: [.addons])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(base64Encoded: share)!) as? [String:Any])
        #expect(object["kind"] as? String == "share" && object["groups"] == nil)
        #expect(object["key"] as? String != alice.recoveryKey)
        let (bob, addonsB, libraryB, defaultsB, _) = fixture()
        await bob.connect(code: try enrollment("bob")); await bob.resolve(useLocal: false)
        defaultsB.set("mint", forKey: "accentColor")
        await bob.joinShare(code: share)
        #expect(bob.errorMessage == nil)
        #expect(addonsB.addons.map(\.manifestURL) == addonsA.addons.map(\.manifestURL))
        #expect(defaultsB.string(forKey: "accentColor") == "mint" && libraryB.progress.isEmpty)
        try addonsA.replaceManifestURLs(["https://second.example/manifest.json"])
        await alice.sync(); await bob.sync()
        #expect(addonsB.addons.map(\.manifestURL) == ["https://second.example/manifest.json"] && libraryB.progress.isEmpty)
        let code = try await bob.makeDeviceCode()
        let (third, addonsC, libraryC, _, _) = fixture()
        await third.connect(code: code); await third.resolve(useLocal: false)
        #expect(third.errorMessage == nil)
        #expect(addonsC.addons.map(\.manifestURL) == ["https://second.example/manifest.json"] && libraryC.progress.isEmpty)
        try alice.disconnect(); try bob.disconnect(); try third.disconnect()
    }

    @Test func sharingCodeCannotBeUsedToSignIntoAnotherPerson() async throws {
        reset()
        let (alice, _, _, _, _) = fixture()
        await alice.connect(code: try enrollment("alice")); await alice.resolve(useLocal: true)
        let share = try await alice.makeShareCode(categories: [.addons])
        let (bob, _, library, _, _) = fixture()
        await bob.connect(code: share)
        #expect(!bob.isConnected && bob.errorMessage != nil && library.activeProfileID == nil)
        try alice.disconnect()
    }

    @Test func endpointAndCipherRejectWrongKeysAndWrongResources() throws {
        #expect(throws: ConfigurationSyncError.invalidEndpoint) { try AccountSyncClient(endpoint: "http://sync.example/v2") }
        #expect(throws: ConfigurationSyncError.invalidEndpoint) { try AccountSyncClient(endpoint: "https://u:p@sync.example/v2") }
        let key = ConfigurationCipher.generateKey()
        let document = try AccountSyncCipher(key: key, resource: "configuration").seal(SyncedConfiguration(accent: "coral"))
        #expect(throws: ConfigurationSyncError.decryptionFailed) { try AccountSyncCipher(key: key, resource: "progress").open(document, as: SyncedConfiguration.self) }
        #expect(throws: ConfigurationSyncError.decryptionFailed) { try AccountSyncCipher(key: ConfigurationCipher.generateKey(), resource: "configuration").open(document, as: SyncedConfiguration.self) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LOGE_V2_TEST_FIXTURE_FILE"] != nil))
    func liveAccountsShareOnlySelectedSetupAndOwnDevicesReceiveProgress() async throws {
        struct Fixture: Decodable {
            let endpoint: String
            let codeA: String
            let codeB: String
            let accountIDA: String
            let accountIDB: String
        }
        struct CachedCredentials: Codable {
            let accountIDA: String
            let accountIDB: String
            let a: Data
            let b: Data
        }
        let path = try #require(ProcessInfo.processInfo.environment["LOGE_V2_TEST_FIXTURE_FILE"])
        let fixtureURL = URL(fileURLWithPath: path)
        let live = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
        let cacheURL = fixtureURL.deletingLastPathComponent().appending(path: "loge-v2-swift-live-credentials.json")
        var cached: CachedCredentials?
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            let value = try JSONDecoder().decode(CachedCredentials.self, from: Data(contentsOf: cacheURL))
            if value.accountIDA == live.accountIDA, value.accountIDB == live.accountIDB { cached = value }
        }
        let (alice, addonsA, libraryA, defaultsA, storageA) = fixture(session: .shared, credentials: cached?.a)
        let (bob, addonsB, libraryB, defaultsB, storageB) = fixture(session: .shared, credentials: cached?.b)
        defer {
            for account in [alice, bob] {
                do { try account.disconnect() } catch { Issue.record(error) }
            }
        }
        if !alice.isConnected { await alice.connect(code: live.codeA, deviceName: "Core test A") }
        if !bob.isConnected { await bob.connect(code: live.codeB, deviceName: "Core test B") }
        try #require(alice.isConnected && bob.isConnected)
        let credentials = CachedCredentials(accountIDA: live.accountIDA, accountIDB: live.accountIDB,
                                            a: try #require(storageA.data), b: try #require(storageB.data))
        let cache = try JSONEncoder().encode(credentials)
        try #require(FileManager.default.createFile(atPath: cacheURL.path, contents: cache, attributes: [.posixPermissions: 0o600]))
        await alice.sync(); await bob.sync()
        await alice.resolve(useLocal: false); await bob.resolve(useLocal: false)
        try #require(alice.errorMessage == nil && bob.errorMessage == nil)
        // A previous failed run may have left only its disposable shared setup.
        for group in alice.sharedGroups { await alice.leaveGroup(id: group.id) }
        for group in bob.sharedGroups { await bob.leaveGroup(id: group.id) }
        await alice.sync(); await bob.sync()
        try addonsA.replaceManifestURLs(["https://first.example/manifest.json", "https://second.example/manifest.json"])
        defaultsA.set("coral", forKey: "accentColor")
        defaultsB.set("mint", forKey: "accentColor")
        libraryA.record(movie("private-a"), position: 140, duration: 1000)
        await alice.sync(); await bob.sync()
        let deviceCode = try await alice.makeDeviceCode()
        let (second, _, librarySecond, defaultsSecond, _) = fixture(session: .shared)
        defer { do { try second.disconnect() } catch { Issue.record(error) } }
        await second.connect(code: deviceCode, deviceName: "Core test second device")
        await second.resolve(useLocal: false)
        try #require(second.errorMessage == nil)
        #expect(librarySecond.progress["private-a"]?.position == 140)
        #expect(libraryB.progress["private-a"] == nil)
        let shared = try await alice.makeShareCode(categories: [.addons])
        await bob.joinShare(code: shared)
        try #require(bob.errorMessage == nil)
        #expect(addonsB.addons.map(\.manifestURL) == addonsA.addons.map(\.manifestURL))
        #expect(defaultsB.string(forKey: "accentColor") == "mint")
        #expect(libraryB.progress["private-a"] == nil)
        try addonsB.replaceManifestURLs(["https://second.example/manifest.json"])
        libraryB.record(movie("private-b"), position: 200, duration: 1000)
        await bob.sync(); await alice.sync(); await second.sync()
        #expect(addonsA.addons.map(\.manifestURL) == ["https://second.example/manifest.json"])
        #expect(libraryA.progress["private-b"] == nil)
        #expect(defaultsSecond.string(forKey: "accentColor") == "coral")
        librarySecond.record(movie("private-a"), position: 220, duration: 1000)
        await second.sync(); await alice.sync()
        #expect(libraryA.progress["private-a"]?.position == 220)
        try #require(alice.errorMessage == nil && second.errorMessage == nil)
        // Device revocation stops future access without affecting the other person.
        await alice.refreshDevices()
        let device = try #require(alice.devices.first { $0.name == "Core test second device" })
        await alice.revokeDevice(id: device.id)
        await second.sync()
        #expect(second.errorMessage != nil)
        await bob.sync()
        #expect(bob.errorMessage == nil)
    }
}

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

final class AccountGatewayProtocol: URLProtocol, @unchecked Sendable {
    struct Invitation { let account: String; let group: String? }
    struct Group { let owner: String; var members: Set<String>; let categories: [String] }
    // The fixture's JSON dictionaries are read and mutated only inside `state`'s lock.
    struct State: @unchecked Sendable {
        var invites: [String: Invitation] = [:]
        var devices: [String: String] = [:]
        var groups: [String: Group] = [:]
        var documents: [String: [String:Any]] = [:]
        var revision = 0
        var hooks: [String: @MainActor @Sendable () -> Void] = [:]
        mutating func respond(method: String, path: String, token: String?, body: [String:Any]) -> (Int, [String:Any]) {
            if path == "redeem", method == "POST", let code = body["code"] as? String,
               let invite = invites[code], invite.group == nil {
                let existing = documents.keys.contains { $0.hasPrefix(invite.account + "/documents/") }
                if existing, body["hasRecoveryKey"] as? Bool != true { return (428,[:]) }
                invites[code] = nil
                let token = UUID().uuidString; devices[token] = invite.account
                return (200,["token":token,"accountID":invite.account,"displayName":invite.account,"deviceID":token,"requiresRecoveryKey":existing])
            }
            guard let token, let account = devices[token] else { return (401,[:]) }
            if path == "me" {
                let metadata: [[String:Any]] = groups.compactMap { id, group in
                    group.members.contains(account) ? ["id":id,"name":"Shared setup","categories":group.categories] : nil
                }
                return (200,["accountID":account,"displayName":account,"deviceID":token,"groups":metadata])
            }
            if path == "invitations", method == "POST" {
                let code = UUID().uuidString
                if body["kind"] as? String == "share" {
                    let groupID = body["groupID"] as? String ?? UUID().uuidString
                    if groups[groupID] == nil { groups[groupID] = Group(owner: account, members: [account], categories: body["categories"] as? [String] ?? []) }
                    invites[code] = Invitation(account: account, group: groupID)
                    return (200,["id":code,"code":code,"expiresAt":"2099-01-01T00:00:00Z","groupID":groupID])
                }
                invites[code] = Invitation(account: account, group: nil)
                return (200,["id":code,"code":code,"expiresAt":"2099-01-01T00:00:00Z"])
            }
            if path == "join", let code = body["code"] as? String, let invite = invites.removeValue(forKey: code),
               let id = invite.group, var group = groups[id] {
                group.members.insert(account); groups[id] = group
                return (200,["id":id,"name":"Shared setup","categories":group.categories])
            }
            if path.hasPrefix("groups/"), path.hasSuffix("/membership"), method == "DELETE" {
                let id = String(path.split(separator: "/")[1])
                guard var group = groups[id], group.members.contains(account) else { return (404,[:]) }
                if group.owner == account { groups[id] = nil }
                else { group.members.remove(account); groups[id] = group }
                return (200,["ok":true])
            }
            let key: String
            if path.hasPrefix("documents/") { key = account + "/" + path }
            else if path.hasPrefix("groups/") {
                let id = String(path.split(separator: "/")[1])
                guard groups[id]?.members.contains(account) == true else { return (403,[:]) }
                key = path
            } else { return (404,[:]) }
            if method == "GET" { return documents[key].map { (200,$0) } ?? (404,[:]) }
            if method == "PUT" {
                guard body["_rev"] as? String == documents[key]?["_rev"] as? String else { return (409,[:]) }
                revision += 1
                let rev = String(revision) + "-revision"
                var document = body; document["_rev"] = rev; documents[key] = document
                return (200,["ok":true,"rev":rev])
            }
            return (404,[:])
        }
    }
    static let state = Mutex(State())
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        var data = request.httpBody
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                result.append(contentsOf: buffer.prefix(count))
            }
            data = result
        }
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String:Any] } ?? [:]
        let path = String(url.path.dropFirst("/v2/".count))
        let token = request.value(forHTTPHeaderField: "Authorization").map { String($0.dropFirst("Bearer ".count)) }
        let method = request.httpMethod ?? "GET"
        let (status, output, hook) = Self.state.withLock { state in
            let (status, object) = state.respond(method: method, path: path, token: token, body: body)
            return (status, try! JSONSerialization.data(withJSONObject: object), state.hooks.removeValue(forKey: method + " " + path))
        }
        Task { @MainActor in
            hook?()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Length":String(output.count)])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: output)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
