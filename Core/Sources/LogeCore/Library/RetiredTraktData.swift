import Foundation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "library")

/// Trakt support was removed in November 2026. Its app keys, sign-in token and unsent changes
/// would otherwise stay on the device with nothing left in the app to delete them.
public enum RetiredTraktData {
    public static func remove(from defaults: UserDefaults = .standard) {
        for key in ["traktUsername", "traktPendingChanges", "traktListedProgress"] {
            defaults.removeObject(forKey: key)
        }
        for account in ["credentials", "token"] {
            do {
                try Keychain.remove(service: "li.tjh.MediaApp.trakt", account: account)
            } catch {
                // Tried again at the next launch.
                log.error("Couldn't remove the saved Trakt \(account, privacy: .public): \(error)")
            }
        }
    }
}
