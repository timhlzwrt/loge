import Foundation

public enum SyncError: Error, Equatable, LocalizedError, Sendable {
    case invalidEndpoint, invalidData, invalidKey, decryptionFailed, unsupportedVersion
    case unauthorized, conflict, tooLarge, invalidResponse, unavailable
    case httpStatus(Int)
    case wrongCode, notReady, overlappingGroup, recoveryRequired, expiredInvitation
    case keychain(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "The code's server address must use HTTPS and end in /v2."
        case .invalidData: "The synced data contains unsupported settings, addon URLs or playback entries."
        case .invalidKey: "The recovery key must be a base64-encoded 256-bit key."
        case .decryptionFailed: "Couldn't decrypt the account data. Check the recovery key."
        case .unsupportedVersion: "This account's data needs a newer version of loge."
        case .unauthorized: "The sync server no longer accepts this device. Connect it again with a new code."
        case .conflict: "Another device saved changes at the same time. Sync again to review them."
        case .tooLarge: "The synced data exceeds the 1 MiB limit."
        case .invalidResponse: "The sync server didn't return a compatible response."
        case .unavailable: "Couldn't reach the sync server. Your local setup is unchanged."
        case .httpStatus(let status): "The sync server responded with HTTP \(status)."
        case .wrongCode: "Paste the complete account, device or sharing code for this server."
        case .notReady: "Finish connecting and resolve pending changes first."
        case .overlappingGroup: "A category can belong to one shared setup. Leave its current shared setup first."
        case .recoveryRequired:
            """
                This account already has encrypted data. Enter its recovery key and retry the same code, or \
                use Add my device on a connected device.
                """
        case .expiredInvitation:
            "This code expired or was already used. Create a new code on a connected device or ask the administrator."
        case .keychain(let status): "Couldn't access the account credentials in Keychain (\(status)). Try again."
        }
    }
}
