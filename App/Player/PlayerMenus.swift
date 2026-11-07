import LogeCore
import SwiftUI

extension MPVPlayer {
    /// HLS streams repeat the same rendition once per quality level; listing identical
    /// entries helps nobody, so keep one of each, preferring the selected one.
    func distinctTracks(_ kind: Track.Kind) -> [Track] {
        var byName: [String: Track] = [:]
        var order: [String] = []
        for track in tracks where track.kind == kind {
            let name = track.displayName
            if let existing = byName[name] {
                if track.isSelected && !existing.isSelected { byName[name] = track }
            } else {
                byName[name] = track
                order.append(name)
            }
        }
        return order.compactMap { byName[$0] }
    }

    /// The selected track's ID, or nil when that kind is turned off.
    func selection(for kind: Track.Kind) -> Binding<Int?> {
        let tracks = distinctTracks(kind)
        return Binding(
            get: { tracks.first(where: \.isSelected)?.id },
            set: { id in self.select(tracks.first { $0.id == id }, kind: kind) }
        )
    }
}

#if !os(tvOS)
struct SubtitlesMenu: View {
    let player: MPVPlayer
    let onInteract: () -> Void
    @Binding var isOpen: Bool
    @Binding var adjustingTiming: MPVPlayer.Track.Kind?

    @AppStorage(PlaybackPreferences.subtitleScaleKey) private var subtitleScale = 1.0

    var body: some View {
        let subtitles = player.distinctTracks(.sub)
        Menu {
            Picker("Subtitles", selection: player.selection(for: .sub)) {
                Text("Off").tag(Int?.none)
                ForEach(subtitles) { Text($0.displayName).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
            Picker("Subtitle Size", selection: $subtitleScale) {
                ForEach(PlaybackPreferences.subtitleScales, id: \.scale) { Text($0.name).tag($0.scale) }
            }
            .pickerStyle(.menu)
            if subtitles.contains(where: \.isSelected) {
                Button("Subtitle Timing…", systemImage: "timer") { adjustingTiming = .sub }
            }
            Color.clear.frame(height: 0).modifier(MenuPresenceTracker(isOpen: $isOpen))
        } label: {
            Label("Subtitles", systemImage: "captions.bubble")
                #if os(iOS)
                .modifier(CapsuleIcon())
                #endif
        }
        .disabled(subtitles.isEmpty)
        .simultaneousGesture(TapGesture().onEnded(onInteract))
        .onChange(of: subtitleScale) { _, scale in player.setSubtitleScale(scale) }
    }
}

/// Audio tracks, speed and audio timing.
struct AudioMenu: View {
    let player: MPVPlayer
    let onInteract: () -> Void
    @Binding var isOpen: Bool
    @Binding var adjustingTiming: MPVPlayer.Track.Kind?
    @State private var showsPlaybackInfo = false

    var body: some View {
        let player = player
        let audio = player.distinctTracks(.audio)
        Menu {
            // A single audio track leaves nothing to choose.
            if audio.count > 1 {
                Picker("Audio", selection: player.selection(for: .audio)) {
                    ForEach(audio) { Text($0.displayName).tag(Optional($0.id)) }
                }
                .pickerStyle(.inline)
            }
            Picker("Speed", selection: Binding(get: { player.speed }, set: { player.setSpeed($0) })) {
                ForEach(PlaybackSpeed.all, id: \.self) { Text(PlaybackSpeed.name($0)).tag($0) }
            }
            .pickerStyle(.inline)
            Button("Audio Timing…", systemImage: "timer") { adjustingTiming = .audio }
            Button("Playback Info…", systemImage: "info.circle") { showsPlaybackInfo = true }
            Color.clear.frame(height: 0).modifier(MenuPresenceTracker(isOpen: $isOpen))
        } label: {
            Label("Audio", systemImage: "waveform")
                #if os(iOS)
                .modifier(CapsuleIcon())
                #endif
        }
        .simultaneousGesture(TapGesture().onEnded(onInteract))
        .sheet(isPresented: $showsPlaybackInfo) { PlaybackInfoView(player: player) }
        .onChange(of: showsPlaybackInfo) { _, shown in
            isOpen = shown
            onInteract()
        }
    }
}
#endif

/// Speeds offered in the player; none is remembered between videos.
enum PlaybackSpeed {
    static let all = [0.5, 0.75, 1, 1.25, 1.5, 2]

    static func name(_ speed: Double) -> String {
        speed == 1 ? "Normal" : "\(speed.formatted())×"
    }
}

/// Shifts subtitles or sound in tenth-of-a-second steps for files whose timing is off.
struct TimingPanel: View {
    let player: MPVPlayer
    let kind: MPVPlayer.Track.Kind
    let onInteract: () -> Void
    let onDone: () -> Void

    private var delay: Double { kind == .sub ? player.subtitleDelay : player.audioDelay }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(kind == .sub ? "Subtitle Timing" : "Audio Timing")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Done", action: onDone)
                    #if !os(tvOS)
                    // Escape closes it, as it closes the menus.
                    .keyboardShortcut(.cancelAction)
                    #endif
                    .frame(minWidth: 44, minHeight: 44)
            }
            HStack(spacing: 12) {
                Button("Earlier", systemImage: "minus") { shift(by: -0.1) }
                    .accessibilityLabel(kind == .sub ? "Show subtitles earlier" : "Play sound earlier")
                    .frame(minWidth: 44, minHeight: 44)
                Text(TimingFormat.delay(delay))
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 64)
                Button("Later", systemImage: "plus") { shift(by: 0.1) }
                    .accessibilityLabel(kind == .sub ? "Show subtitles later" : "Play sound later")
                    .frame(minWidth: 44, minHeight: 44)
                Spacer(minLength: 0)
                Button("Reset") { shift(by: -delay) }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(delay == 0)
            }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 460)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private func shift(by seconds: Double) {
        player.setDelay(TimingFormat.step(delay, by: seconds), for: kind)
        onInteract()
    }
}

enum TimingFormat {
    /// "+0.3 s".
    static func delay(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))) + " s"
    }

    /// Rounded so repeated steps don't drift to values like 0.30000000000000004.
    static func step(_ delay: Double, by seconds: Double) -> Double {
        ((delay + seconds) * 10).rounded() / 10
    }
}

struct PlaybackInfoView: View {
    let player: MPVPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxWidth: 620)
        .task {
            while !Task.isCancelled {
                player.refreshPlaybackInfo()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Playback Info").font(.title2.weight(.semibold))
            if let format = player.videoFormat {
                LabeledContent("Video", value: "\(format.width) × \(format.height)")
                if let rate = format.frameRate {
                    LabeledContent("Source frame rate", value: "\(rate.formatted(.number.precision(.fractionLength(2)))) fps")
                }
            }
            LabeledContent("Hardware decoder", value: player.playbackInfo.hardwareDecoder ?? "Unavailable")
            LabeledContent("Video bitrate", value: Self.bitrate(player.playbackInfo.videoBitrate))
            LabeledContent("Audio bitrate", value: Self.bitrate(player.playbackInfo.audioBitrate))
            LabeledContent("Decoder drops", value: player.playbackInfo.decoderDrops.map(String.init) ?? "Unavailable")
            LabeledContent("Output drops", value: player.playbackInfo.outputDrops.map(String.init) ?? "Unavailable")
            LabeledContent("Buffered", value: player.playbackInfo.bufferedSeconds.map {
                "\($0.formatted(.number.precision(.fractionLength(1)))) s"
            } ?? "Unavailable")
            LabeledContent("Download speed", value: Self.bitrate(player.playbackInfo.downloadSpeed))
            Text("""
                Bitrates are estimated from recent video and audio. A download speed that stays below them \
                means the source is too large for this connection; drop counts that rise during a hitch point \
                to decoding instead.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(32)
    }

    static func bitrate(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        let megabits = value >= 1_000_000
        let number = value / (megabits ? 1_000_000 : 1_000)
        return number.formatted(.number.precision(.fractionLength(0...1))) + (megabits ? " Mbps" : " kbps")
    }
}
