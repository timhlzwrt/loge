import Foundation
import LogeCore

/// What the playback preferences, stored under `SyncedSettings.Key` so a sync account can
/// carry them, mean to the app. Languages are ISO 639-1 codes.
enum PlaybackPreferences {
    /// In Mbps; 0 for no limit.
    static var maximumBitrate: Int {
        UserDefaults.standard.object(forKey: SyncedSettings.Key.maximumBitrate) as? Int ?? SyncedSettings().maximumBitrate
    }

    static let subtitleScales: [(name: String, scale: Double)] = Array(
        zip(["Small", "Normal", "Large", "Extra Large"], SyncedSettings.subtitleScales))

    /// The offered languages, sorted by their name in the user's language.
    static var languages: [(code: String, name: String)] {
        LanguageCodes.common
            .map { ($0, Locale.current.localizedString(forLanguageCode: $0) ?? $0) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
}

/// How fast this device downloads, from what playback sustained; the sources list
/// recommends a source by it.
enum ConnectionSpeed {
    /// Bits per second; 0 until something has played long enough to tell.
    static let key = "connectionSpeed"

    static func record(_ speed: Double) {
        let defaults = UserDefaults.standard
        let previous = defaults.double(forKey: key)
        // Averaged with the last value only, so a move to another room or network shows
        // after a film or two.
        defaults.set(previous > 0 ? (previous + speed) / 2 : speed, forKey: key)
    }
}
