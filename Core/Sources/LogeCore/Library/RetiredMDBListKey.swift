import Foundation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "library")

/// MDBList, which supplied the Letterboxd and Rotten Tomatoes scores, was removed in November
/// 2026. Its API key would otherwise stay in the Keychain with nothing left in the app to delete it.
public enum RetiredMDBListKey {
    static let removedKey = "retiredMDBListKeyRemoved"

    public static func remove(from defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: removedKey) else { return }
        do {
            try Keychain.remove(service: "li.tjh.MediaApp.mdblist", account: "apiKey")
            defaults.set(true, forKey: removedKey)
        } catch {
            // Tried again at the next launch.
            log.error("Couldn't remove the saved MDBList key: \(error)")
        }
    }
}
