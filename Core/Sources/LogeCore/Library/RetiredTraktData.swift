import Foundation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "library")

/// Trakt support was removed in November 2026. Its app keys, sign-in token and unsent changes
/// would otherwise stay on the device with nothing left in the app to delete them.
public enum RetiredTraktData {
    static let removedKey = "retiredTraktDataRemoved"

    /// Marked done once everything is gone, so later launches skip the Keychain calls before
    /// the first frame.
    public static func remove(from defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: removedKey) else { return }
        for key in ["traktUsername", "traktPendingChanges", "traktListedProgress"] {
            defaults.removeObject(forKey: key)
        }
        var removedAll = true
        for account in ["credentials", "token"] {
            do {
                try Keychain.remove(service: "li.tjh.MediaApp.trakt", account: account)
            } catch {
                // Tried again at the next launch.
                log.error("Couldn't remove the saved Trakt \(account, privacy: .public): \(error)")
                removedAll = false
            }
        }
        if removedAll { defaults.set(true, forKey: removedKey) }
    }
}
