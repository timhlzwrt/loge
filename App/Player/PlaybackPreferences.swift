import MediaCore
import SwiftUI

/// The user's preferred audio and subtitle languages, stored as ISO 639-1 codes.
enum PlaybackPreferences {
    static let audioKey = "audioLanguage"
    static let subtitleKey = "subtitleLanguage"
    static let subtitleScaleKey = "subtitleScale"

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
    @AppStorage(PlaybackPreferences.audioKey) private var audioLanguage = ""
    @AppStorage(PlaybackPreferences.subtitleKey) private var subtitleLanguage = ""

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
        } header: {
            Text("Playback")
        } footer: {
            Text("Used when a file has a matching track. You can still switch tracks while watching.")
                .foregroundStyle(.secondary)
        }
    }
}
