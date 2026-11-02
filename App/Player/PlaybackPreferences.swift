import MediaCore
import SwiftUI

/// The user's preferred audio and subtitle languages, stored as ISO 639-1 codes.
enum PlaybackPreferences {
    static let audioKey = "audioLanguage"
    static let defaultAudioLanguage = "en"
    static let subtitleKey = "subtitleLanguage"
    static let subtitleScaleKey = "subtitleScale"
    static let maximumSourceSizeKey = "maximumAutomaticSourceGigabytes"
    static let defaultMaximumSourceGigabytes = 50

    static var maximumAutomaticFileSize: Int64 {
        let gigabytes = UserDefaults.standard.object(forKey: maximumSourceSizeKey) as? Int ?? defaultMaximumSourceGigabytes
        return Int64(max(0, min(gigabytes, 1_000))) * 1_000_000_000
    }

    static let subtitleScales: [(name: String, scale: Double)] = [
        ("Small", 0.8), ("Normal", 1), ("Large", 1.25), ("Extra Large", 1.6),
    ]

    /// The offered languages, sorted by their name in the user's language.
    static var languages: [(code: String, name: String)] {
        LanguageCodes.common
            .map { ($0, Locale.current.localizedString(forLanguageCode: $0) ?? $0) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
}

struct PlaybackSettingsSection: View {
    @AppStorage(PlaybackPreferences.audioKey) private var audioLanguage = PlaybackPreferences.defaultAudioLanguage
    @AppStorage(PlaybackPreferences.subtitleKey) private var subtitleLanguage = ""
    @AppStorage(PlaybackPreferences.maximumSourceSizeKey) private var maximumSourceGigabytes = PlaybackPreferences.defaultMaximumSourceGigabytes

    var body: some View {
        Section {
            Picker("Audio", selection: $audioLanguage) {
                Text("File default").tag("")
                ForEach(PlaybackPreferences.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
            Picker("Subtitles", selection: $subtitleLanguage) {
                Text("Off").tag("")
                ForEach(PlaybackPreferences.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
            Picker("Automatic series source limit", selection: $maximumSourceGigabytes) {
                Text("No limit").tag(0)
                ForEach([10, 25, 50, 100], id: \.self) { Text("\($0) GB per episode").tag($0) }
            }
        } header: {
            Text("Playback")
        } footer: {
            Text("Languages apply when a file has a matching track. The size limit applies only to series, including Up Next. Episodes above the limit or without a known video size require a manual choice. Movies are unrestricted. A season pack's total size is not an episode's file size.")
                .foregroundStyle(.secondary)
        }
    }
}
