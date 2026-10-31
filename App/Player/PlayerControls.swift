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
    /// True while one of the menus is open, so the controls don't hide out from under it.
    @Binding var isMenuOpen: Bool
    /// Which timing panel is showing, if any.
    @Binding var adjustingTiming: MPVPlayer.Track.Kind?
    let onClose: () -> Void
    /// Opens the list of sources for what's playing; nil when there's no list to go back to.
    let onChooseSource: (() -> Void)?
    let onInteract: () -> Void

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
            Spacer()
            transport
                .frame(maxWidth: .infinity)
            Spacer()
            if let kind = adjustingTiming {
                TimingPanel(player: player, kind: kind, onInteract: onInteract) { adjustingTiming = nil }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
            }
            HStack(alignment: .center) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
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
            .padding(.bottom, 8)
            timeline
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .background { scrims }
    }

    /// Plain symbols, no circles: the picture is the background.
    private var transport: some View {
        HStack(spacing: 64) {
            Button("Back 10 seconds", systemImage: "gobackward.10") {
                player.seek(by: -10)
                onInteract()
            }
            Group {
                if player.isWaiting {
                    ProgressView().controlSize(.large)
                } else {
                    playPauseButton
                }
            }
            .font(.system(size: 44))
            .frame(width: 56, height: 56)
            Button("Forward 10 seconds", systemImage: "goforward.10") {
                player.seek(by: 10)
                onInteract()
            }
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
                    player.seek(to: target)
                    scrubPosition = nil
                }
                onInteract()
            }
        )
        .controlSize(.small)
        .accessibilityLabel("Playback position")
        .accessibilityValue(format(position, longForm: longForm))
    }
    #endif

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
            if let existing = byName[track.displayName] {
                if track.isSelected && !existing.isSelected { byName[track.displayName] = track }
            } else {
                byName[track.displayName] = track
                order.append(track.displayName)
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
            Color.clear.frame(height: 0).modifier(MenuPresenceTracker(isOpen: $isOpen))
        } label: {
            Label("Audio", systemImage: "waveform")
                #if os(iOS)
                .modifier(CapsuleIcon())
                #endif
        }
        .simultaneousGesture(TapGesture().onEnded(onInteract))
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
        HStack(spacing: 20) {
            Text(kind == .sub ? "Subtitle Timing" : "Audio Timing")
                .font(.subheadline.weight(.semibold))
            Button("Earlier", systemImage: "minus") { shift(by: -0.1) }
                .accessibilityLabel(kind == .sub ? "Show subtitles earlier" : "Play sound earlier")
            Text(TimingFormat.delay(delay))
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 64)
            Button("Later", systemImage: "plus") { shift(by: 0.1) }
                .accessibilityLabel(kind == .sub ? "Show subtitles later" : "Play sound later")
            Button("Reset") { shift(by: -delay) }
                .disabled(delay == 0)
            Button("Done", action: onDone)
                .font(.subheadline.weight(.semibold))
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(in: .capsule)
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
