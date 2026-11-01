import SwiftUI
#if os(iOS)
import AVKit
#endif

/// The overlay shown over playing video: title, transport, timeline and the track menus.
struct PlayerControls: View {
    let title: String
    let player: MPVPlayer
    let pictureInPicture: PictureInPicture?
    /// Where the timeline is being dragged or swiped to; nil while it follows playback.
    @Binding var scrubPosition: Double?
    /// The frame near `scrubPosition`, once one has been decoded.
    let scrubPreview: CGImage?
    /// True while one of the menus is open, so the controls don't hide out from under it.
    @Binding var isMenuOpen: Bool
    /// Which timing panel is showing, if any.
    @Binding var adjustingTiming: MPVPlayer.Track.Kind?
    let onClose: () -> Void
    /// Opens the list of sources for what's playing; nil when there's no list to go back to.
    let onChooseSource: (() -> Void)?
    let onInteract: () -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        #if os(tvOS)
        tvBody
        #elseif os(macOS)
        macBody
        #else
        phoneBody
        #endif
    }

    /// Scrims behind the bars keep white controls readable over bright frames.
    private var scrims: some View {
        // No spacing: in landscape the two scrims nearly fill the screen height, and
        // any overflow would centre the stack and lift the bottom scrim off the edge.
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: tvOS

    #if os(tvOS)
    private var tvBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(title)
                .font(.sectionTitle)
                .lineLimit(1)
            timeline
        }
        // Full width even before the timeline knows the duration, so the title doesn't start centred.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { scrims }
    }
    #endif

    // MARK: iPhone and iPad

    #if os(iOS)
    private var phoneBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Close", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    // A larger target than the glyph, since this is the main way out.
                    .frame(width: 44, height: 44)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                Spacer()
                GlassCapsule {
                    if let pictureInPicture, pictureInPicture.isPossible {
                        Button("Picture in Picture", systemImage: "pip.enter", action: pictureInPicture.start)
                            .modifier(CapsuleIcon())
                    }
                    AirPlayButton()
                        .frame(width: 44, height: 44)
                }
            }
            Spacer(minLength: 24)
            if let kind = adjustingTiming {
                TimingPanel(player: player, kind: kind, onInteract: onInteract) { adjustingTiming = nil }
                    .frame(maxWidth: .infinity)
            } else {
                timeline
                HStack {
                    Spacer()
                    GlassCapsule {
                        SubtitlesMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, adjustingTiming: $adjustingTiming)
                        AudioMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, adjustingTiming: $adjustingTiming)
                        if let onChooseSource {
                            Button("Sources", systemImage: "list.bullet", action: onChooseSource)
                                .modifier(CapsuleIcon())
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            // Transport stays at the picture's center, independent of bar and panel heights.
            if adjustingTiming == nil {
                transport
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .background { scrims }
    }

    /// Plain symbols, no circles: the picture is the background.
    private var transport: some View {
        HStack(spacing: 40) {
            Button("Back 10 seconds", systemImage: "gobackward.10") {
                player.seek(by: -10)
                onInteract()
            }
            .frame(width: 56, height: 56)
            Group {
                if player.isWaiting {
                    ProgressView().controlSize(.large)
                } else {
                    playPauseButton
                }
            }
            .font(.system(size: 44))
            .frame(width: 72, height: 72)
            Button("Forward 10 seconds", systemImage: "goforward.10") {
                player.seek(by: 10)
                onInteract()
            }
            .frame(width: 56, height: 56)
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 30, weight: .medium))
        .shadow(color: .black.opacity(0.4), radius: 8)
    }
    #endif

    // MARK: Mac

    #if os(macOS)
    /// One floating capsule at the bottom; the title is in the window's title bar.
    private var macBody: some View {
        VStack(spacing: 12) {
            Spacer()
            if let kind = adjustingTiming {
                TimingPanel(player: player, kind: kind, onInteract: onInteract) { adjustingTiming = nil }
            }
            HStack(spacing: 14) {
                Button("Back 10 seconds", systemImage: "gobackward.10") {
                    player.seek(by: -10)
                    onInteract()
                }
                Group {
                    if player.isWaiting {
                        ProgressView().controlSize(.small)
                    } else {
                        playPauseButton
                    }
                }
                .frame(width: 22)
                Button("Forward 10 seconds", systemImage: "goforward.10") {
                    player.seek(by: 10)
                    onInteract()
                }
                timeline
                    .padding(.horizontal, 6)
                SubtitlesMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, adjustingTiming: $adjustingTiming)
                AudioMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, adjustingTiming: $adjustingTiming)
                if let pictureInPicture, pictureInPicture.isPossible {
                    Button("Picture in Picture", systemImage: "pip.enter", action: pictureInPicture.start)
                }
                Button("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .medium))
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .menuStyle(.button)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .glassEffect(in: .capsule)
            .frame(maxWidth: 720)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }
    #endif

    // MARK: Shared

    #if !os(tvOS)
    private var playPauseButton: some View {
        Button(player.status == .playing ? "Pause" : "Play",
               systemImage: player.status == .playing ? "pause.fill" : "play.fill") {
            if player.status == .ended {
                player.seek(to: 0)
                player.play()
            } else {
                player.togglePause()
            }
            onInteract()
        }
        .labelStyle(.iconOnly)
    }
    #endif

    /// The position bar with elapsed time on the left and remaining time on the right; on
    /// the Mac the times sit either side of the bar inside the capsule.
    @ViewBuilder
    private var timeline: some View {
        if let duration = player.duration, duration > 0 {
            let position = scrubPosition ?? player.position
            let longForm = duration >= 3600
            #if os(macOS)
            HStack(spacing: 12) {
                Text(format(position, longForm: longForm))
                    .foregroundStyle(.secondary)
                slider(duration: duration, position: position, longForm: longForm)
                Text("−" + format(duration - position, longForm: longForm))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())
            #else
            VStack(spacing: 8) {
                #if os(tvOS)
                ProgressView(value: min(position, duration), total: duration)
                    .overlay { scrubPreviewView(duration: duration, longForm: longForm) }
                #else
                slider(duration: duration, position: position, longForm: longForm)
                #endif
                HStack {
                    #if os(tvOS)
                    // tvOS has no on-screen play button, so this is the only sign playback is paused.
                    if player.status == .paused {
                        Image(systemName: "pause.fill")
                            .accessibilityLabel("Paused")
                    }
                    #endif
                    Text(format(position, longForm: longForm))
                    Spacer()
                    Text("−" + format(duration - position, longForm: longForm))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            #endif
        } else {
            // Live streams and files still loading have no duration to scrub through.
            Text(format(player.position, longForm: false))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    #if !os(tvOS)
    private func slider(duration: Double, position: Double, longForm: Bool) -> some View {
        Slider(
            value: Binding(get: { scrubPosition ?? player.position }, set: { scrubPosition = $0 }),
            in: 0...duration,
            onEditingChanged: { isEditing in
                if !isEditing, let target = scrubPosition {
                    player.seek(toKeyframeNear: target)
                    scrubPosition = nil
                }
                onInteract()
            }
        )
        .controlSize(.small)
        .overlay { scrubPreviewView(duration: duration, longForm: longForm) }
        .accessibilityLabel("Playback position")
        .accessibilityValue(format(position, longForm: longForm))
    }
    #endif

    /// The frame and time being scrubbed to, above the timeline at that spot. The time shows
    /// alone until a frame has been decoded, and for files that can't give one.
    @ViewBuilder
    private func scrubPreviewView(duration: Double, longForm: Bool) -> some View {
        if let scrubPosition {
            GeometryReader { proxy in
                let width = previewWidth
                let x = proxy.size.width * scrubPosition / duration - width / 2
                VStack(spacing: 6) {
                    if let scrubPreview {
                        Image(decorative: scrubPreview, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 6))
                    }
                    Text(format(scrubPosition, longForm: longForm))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.4), radius: 8)
                .frame(width: width)
                // A zero-height frame anchored at its bottom lets the preview rise above the bar.
                .frame(width: width, height: 0, alignment: .bottom)
                .offset(x: min(max(x, 0), max(proxy.size.width - width, 0)), y: -12)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var previewWidth: CGFloat {
        #if os(tvOS)
        400
        #elseif os(macOS)
        220
        #else
        horizontalSizeClass == .regular ? 240 : 160
        #endif
    }

    private func format(_ seconds: Double, longForm: Bool) -> String {
        Duration.seconds(max(seconds, 0)).formatted(.time(pattern: longForm ? .hourMinuteSecond : .minuteSecond))
    }
}

#if os(iOS)
/// Icon-only buttons sharing one Liquid Glass capsule.
private struct GlassCapsule<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, 4)
            .glassEffect(in: .capsule)
    }
}

private struct CapsuleIcon: ViewModifier {
    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }
}

/// The system's route picker, for sending sound to AirPlay speakers.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .white
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

/// Reports whether a menu is showing. Menus have no presentation state of their own,
/// but their content appears and disappears with them.
private struct MenuPresenceTracker: ViewModifier {
    @Binding var isOpen: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { isOpen = true }
            .onDisappear { isOpen = false }
    }
}

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
private struct SubtitlesMenu: View {
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
private struct AudioMenu: View {
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
private struct TimingPanel: View {
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
            LabeledContent("Video bitrate", value: bitrate(player.playbackInfo.videoBitrate))
            LabeledContent("Audio bitrate", value: bitrate(player.playbackInfo.audioBitrate))
            LabeledContent("Decoder drops", value: player.playbackInfo.decoderDrops.map(String.init) ?? "Unavailable")
            LabeledContent("Output drops", value: player.playbackInfo.outputDrops.map(String.init) ?? "Unavailable")
            LabeledContent("Buffered", value: player.playbackInfo.bufferedSeconds.map {
                "\($0.formatted(.number.precision(.fractionLength(1)))) s"
            } ?? "Unavailable")
            Text("Bitrates estimate recent media packets, not download speed. Watch whether drop counts increase during a hitch. A low buffer can indicate a slow source. These counters cannot measure the TV's display cadence.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(32)
    }

    private func bitrate(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        let megabits = value >= 1_000_000
        let number = value / (megabits ? 1_000_000 : 1_000)
        return number.formatted(.number.precision(.fractionLength(0...1))) + (megabits ? " Mbps" : " kbps")
    }
}
