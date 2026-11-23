import LogeCore
import SwiftUI

struct PlaybackSettingsSection: View {
    @AppStorage(SyncedSettings.Key.audioLanguage) private var audioLanguage = SyncedSettings().audioLanguage
    @AppStorage(SyncedSettings.Key.subtitleLanguage) private var subtitleLanguage = SyncedSettings().subtitleLanguage
    @AppStorage(SyncedSettings.Key.maximumBitrate) private var maximumBitrate = SyncedSettings().maximumBitrate

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
                    Text(Self.bitrateOption($0)).tag($0)
                }
            }
            #if os(tvOS)
            .pickerStyle(.navigationLink)
            #endif
        } header: {
            SettingsHeader("Playback")
        }
    }

    /// "50 Mbps · 22.5 GB/h": what a limit means in data, shown where it's chosen.
    static func bitrateOption(_ megabits: Int) -> String {
        let gigabytesPerHour = Double(megabits) * 3600 / 8 / 1000
        return "\(megabits) Mbps · \(gigabytesPerHour.formatted(.number.precision(.fractionLength(0...1)).locale(.interface))) GB/h"
    }
}
