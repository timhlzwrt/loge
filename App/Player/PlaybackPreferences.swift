import Foundation
import LogeCore

/// The user's preferred audio and subtitle languages, stored as ISO 639-1 codes.
/// The values are `SyncedSettings`', so a sync account can carry them.
enum PlaybackPreferences {
    static let audioKey = SyncedSettings.Key.audioLanguage
    static let defaultAudioLanguage = SyncedSettings().audioLanguage
    static let subtitleKey = SyncedSettings.Key.subtitleLanguage
    static let subtitleScaleKey = SyncedSettings.Key.subtitleScale
    static let maximumSourceSizeKey = SyncedSettings.Key.maximumSourceGigabytes
    static let defaultMaximumSourceGigabytes = SyncedSettings().maximumSourceGigabytes

    static var maximumAutomaticFileSize: Int64 {
        let gigabytes = UserDefaults.standard.object(forKey: maximumSourceSizeKey) as? Int ?? defaultMaximumSourceGigabytes
        return Int64(max(0, min(gigabytes, 1_000))) * 1_000_000_000
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
