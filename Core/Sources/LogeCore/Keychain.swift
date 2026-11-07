import Foundation
import Security

public struct KeychainError: Error, Equatable, Sendable {
    public enum Operation: Sendable { case read, save, remove }
    public let operation: Operation
    public let status: OSStatus
}

/// Small values that shouldn't sit in `UserDefaults`, such as sign-in tokens. The keychain
/// also survives tvOS purging the app's files. Items stay on this device: other devices
/// sign in themselves or receive what they need through a connection code.
enum Keychain {
    static func read(service: String, account: String) throws(KeychainError) -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else {
            throw KeychainError(operation: .read, status: status)
        }
        return data
    }

    static func save(_ data: Data, service: String, account: String) throws(KeychainError) {
        let query = baseQuery(service: service, account: account)
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Updating in place keeps a working credential intact if replacing it fails.
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(operation: .save, status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(operation: .save, status: status)
        }
    }

    static func remove(service: String, account: String) throws(KeychainError) {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: .remove, status: status)
        }
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
