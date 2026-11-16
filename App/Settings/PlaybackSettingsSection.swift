import LogeCore
import SwiftUI

struct PlaybackSettingsSection: View {
    @AppStorage(PlaybackPreferences.audioKey) private var audioLanguage = PlaybackPreferences.defaultAudioLanguage
    @AppStorage(PlaybackPreferences.subtitleKey) private var subtitleLanguage = ""
    @AppStorage(PlaybackPreferences.maximumBitrateKey) private var maximumBitrate = PlaybackPreferences.defaultMaximumBitrate

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
            Picker("Maximum bitrate", selection: $maximumBitrate) {
                Text("No limit").tag(0)
                ForEach(SyncedSettings.maximumBitrateOptions.filter { $0 > 0 }, id: \.self) {
                    Text("\($0) Mbps").tag($0)
                }
            }
            #if os(tvOS)
            .pickerStyle(.navigationLink)
            #endif
        } header: {
            SettingsHeader("Playback")
        } footer: {
            Text("""
                Languages apply when a file has a matching track. The bitrate limit applies to the sources \
                Play and Up Next pick for you, films too, and to the source list. 50 Mbps is about 22 GB \
                per hour; sources of unknown bitrate are only picked when no other fits.
                """)
                .foregroundStyle(.secondary)
        }
    }
}
