import LogeCore
import SwiftUI

struct PlaybackSettingsSection: View {
    @AppStorage(PlaybackPreferences.audioKey) private var audioLanguage = PlaybackPreferences.defaultAudioLanguage
    @AppStorage(PlaybackPreferences.subtitleKey) private var subtitleLanguage = ""
    @AppStorage(PlaybackPreferences.maximumSourceSizeKey)
    private var maximumSourceGigabytes = PlaybackPreferences.defaultMaximumSourceGigabytes

    var body: some View {
        Section {
            Picker("Audio", selection: $audioLanguage) {
                Text("File default").tag("")
                ForEach(PlaybackPreferences.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
            #if os(tvOS)
            // tvOS draws pickers as segmented strips, too narrow for 25 language names.
            .pickerStyle(.navigationLink)
            #endif
            Picker("Subtitles", selection: $subtitleLanguage) {
                Text("Off").tag("")
                ForEach(PlaybackPreferences.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
            #if os(tvOS)
            .pickerStyle(.navigationLink)
            #endif
            Picker("Automatic series source limit", selection: $maximumSourceGigabytes) {
                Text("No limit").tag(0)
                ForEach(SyncedSettings.maximumSourceGigabyteOptions.filter { $0 > 0 }, id: \.self) {
                    Text("\($0) GB per episode").tag($0)
                }
            }
            #if os(tvOS)
            .pickerStyle(.navigationLink)
            #endif
        } header: {
            Text("Playback")
        } footer: {
            Text("""
                Languages apply when a file has a matching track. The size limit applies to series episodes, \
                including Up Next; larger episodes, or ones of unknown size, are left for you to choose.
                """)
                .foregroundStyle(.secondary)
        }
    }
}
