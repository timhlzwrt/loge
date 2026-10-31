import Foundation
import Security
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "keychain")

/// Small values that shouldn't sit in `UserDefaults`, such as sign-in tokens. The keychain
/// also survives tvOS purging the app's files.
enum Keychain {
    static func data(for account: String, service: String) -> Data? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func set(_ data: Data?, for account: String, service: String) {
        let query = baseQuery(account: account, service: service)
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("Couldn't save \(account, privacy: .public) to the keychain: \(status)")
        }
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
