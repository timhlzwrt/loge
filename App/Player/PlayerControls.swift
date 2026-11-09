import LogeCore
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
    /// In full screen the Mac's title bar, and the title in it, is gone.
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
                .frame(height: bottomScrimHeight)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var bottomScrimHeight: CGFloat {
        #if os(iOS)
        isPhoneLandscape ? 130 : 220
        #else
        220
        #endif
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
    private var isPhoneLandscape: Bool { verticalSizeClass == .compact }

    private var phoneBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // The whole circle is the button: with the glass button style, taps near its
                // edge fell through to the picture and hid the controls instead of closing.
                Button("Close", systemImage: "xmark", action: onClose)
                    .modifier(CapsuleIcon())
                    .fontWeight(.semibold)
                    .glassEffect(.regular.interactive(), in: .circle)
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
            } else if isPhoneLandscape {
                // Height is what's short here, and every row taken from it covers the picture.
                HStack(spacing: 12) {
                    timeline
                    menuButtons
                }
            } else {
                timeline
                HStack {
                    Spacer()
                    menuButtons
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

    private var menuButtons: some View {
        GlassCapsule {
            SubtitlesMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, adjustingTiming: $adjustingTiming)
            AudioMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, adjustingTiming: $adjustingTiming)
            MoreMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen)
            ZoomButton(player: player, onInteract: onInteract)
                .modifier(CapsuleIcon())
            if let onChooseSource {
                Button("Sources", systemImage: "list.bullet", action: onChooseSource)
                    .modifier(CapsuleIcon())
            }
        }
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
    /// One floating capsule at the bottom; the title is in the window's title bar until full screen.
    private var macBody: some View {
        VStack(spacing: 12) {
            if isFullScreen {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.6), radius: 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top], 24)
            }
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
                MoreMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, onChooseSource: onChooseSource)
                ZoomButton(player: player, onInteract: onInteract)
                if let pictureInPicture, pictureInPicture.isPossible {
                    Button("Picture in Picture", systemImage: "pip.enter", action: pictureInPicture.start)
                }
                Button(isFullScreen ? "Exit Full Screen" : "Full Screen",
                       systemImage: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                       action: onToggleFullScreen)
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
                .font(timeFont)
            }
            #endif
        } else {
            // Live streams and files still loading have no duration to scrub through.
            Text(format(player.position, longForm: false))
                .font(timeFont)
        }
    }

    /// Times are read at a glance over bright frames, on Apple TV from across the room.
    private var timeFont: Font {
        #if os(tvOS)
        .callout.monospacedDigit().weight(.medium)
        #else
        .caption.monospacedDigit().weight(.medium)
        #endif
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
                            .resizable().scaledToFit()
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
struct GlassCapsule<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, 4)
            .glassEffect(in: .capsule)
    }
}

struct CapsuleIcon: ViewModifier {
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
    @AppStorage(Accent.storageKey) private var accent = Accent.white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.activeTintColor = UIColor(accent.color)
    }
}
#endif

/// Reports whether a menu is showing. Menus have no presentation state of their own,
/// but their content appears and disappears with them.
struct MenuPresenceTracker: ViewModifier {
    @Binding var isOpen: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { isOpen = true }
            .onDisappear { isOpen = false }
    }
}
