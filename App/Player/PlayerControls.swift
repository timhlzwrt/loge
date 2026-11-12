import LogeCore
import SwiftUI
#if os(iOS)
import AVKit
#endif

/// The overlay shown over playing video: title, transport, timeline and the track menus.
struct PlayerControls: View {
    let title: String
    /// What's playing, to show a series apart from its episode.
    let item: WatchItem?
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
    /// Shown by the player screen, which outlives the menu it's chosen from.
    let onPlaybackInfo: () -> Void
    let onInteract: () -> Void
    /// In full screen the Mac's title bar, and the title in it, is gone.
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// Where playback was when the current drag on the timeline began.
    @State private var dragStart: Double?
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

    // MARK: tvOS

    #if os(tvOS)
    /// Scrims behind the bars keep white controls readable over bright frames.
    private var scrims: some View {
        // No spacing: the two scrims nearly fill the screen height, and any overflow would
        // centre the stack and lift the bottom scrim off the edge.
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
            Spacer(minLength: 0)
            // Taller and darker than the phone's even dim would be here: the title and times are
            // read from across the room over whatever the frame holds, while most of the
            // picture stays as it is.
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.5), location: 0.5),
                .init(color: .black.opacity(0.75), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: 440)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

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
    /// Laid out like the TV app's player: close and output at the top, transport in glass
    /// circles at the centre, and at the bottom what's playing, the menus and an inline timeline.
    private var phoneBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // The whole circle is the button: with the glass button style, taps near its
                // edge fell through to the picture and hid the controls instead of closing.
                Button("Close", systemImage: "xmark", action: onClose)
                    .modifier(CapsuleIcon())
                    .fontWeight(.semibold)
                    .glassEffect(.regular.interactive(), in: .circle)
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
                TimingPanel(player: player, kind: kind, onInteract: onInteract) {
                    adjustingTiming = nil
                    // Restarts the countdown, which skipped hiding while the panel was open.
                    onInteract()
                }
                    .frame(maxWidth: .infinity)
            } else {
                if isPortraitPhone {
                    // Too narrow for the title beside five buttons; height is what's spare here.
                    nowPlaying
                    menuButtons
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 12)
                } else {
                    HStack(alignment: .bottom, spacing: 16) {
                        nowPlaying
                        Spacer(minLength: 0)
                        menuButtons
                    }
                }
                timeline
                    .padding(.top, 10)
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
        .background {
            // An even dim, as in the TV app: the glass stays grey over bright frames, and
            // the title and times read anywhere on the picture.
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var isPortraitPhone: Bool { horizontalSizeClass == .compact && verticalSizeClass == .regular }

    /// The series over the episode's code and name, or just the title for a film.
    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item, let code = item.episodeCode {
                Text([code, item.episodeTitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(item?.title ?? title)
                .font(.title2.bold())
                // A landscape phone has no height for a second line under the transport buttons.
                .lineLimit(verticalSizeClass == .compact ? 1 : 2)
        }
    }

    private var menuButtons: some View {
        GlassCapsule {
            SubtitlesMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, adjustingTiming: $adjustingTiming)
                .equatable()
            AudioMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, adjustingTiming: $adjustingTiming)
                .equatable()
            MoreMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, onPlaybackInfo: onPlaybackInfo)
                .equatable()
            ZoomButton(player: player, onInteract: onInteract)
                .modifier(CapsuleIcon())
            if let onChooseSource {
                Button("Sources", systemImage: "list.bullet", action: onChooseSource)
                    .modifier(CapsuleIcon())
            }
        }
    }

    /// Each button sits on its own glass circle, the play button the largest.
    private var transport: some View {
        HStack(spacing: 32) {
            Button("Back 10 seconds", systemImage: "gobackward.10") {
                player.seek(by: -10)
                onInteract()
            }
            .frame(width: 60, height: 60)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
            Group {
                if player.isWaiting {
                    ProgressView().controlSize(.large)
                } else {
                    playPauseButton
                }
            }
            .font(.system(size: 36))
            .frame(width: 80, height: 80)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
            Button("Forward 10 seconds", systemImage: "goforward.10") {
                player.seek(by: 10)
                onInteract()
            }
            .frame(width: 60, height: 60)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 24, weight: .medium))
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
                TimingPanel(player: player, kind: kind, onInteract: onInteract) {
                    adjustingTiming = nil
                    // Restarts the countdown, which skipped hiding while the panel was open.
                    onInteract()
                }
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
                    .equatable()
                AudioMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, adjustingTiming: $adjustingTiming)
                    .equatable()
                MoreMenu(player: player, onInteract: onInteract, isOpen: $isMenuOpen, onPlaybackInfo: onPlaybackInfo,
                         onChooseSource: onChooseSource)
                    .equatable()
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
            player.togglePause()
            onInteract()
        }
        .labelStyle(.iconOnly)
    }
    #endif

    /// The position bar with elapsed time on the left and remaining time on the right; on
    /// tvOS the times sit below the bar.
    @ViewBuilder
    private var timeline: some View {
        if let duration = player.duration, duration > 0 {
            let position = scrubPosition ?? player.position
            let longForm = duration >= 3600
            #if os(tvOS)
            VStack(spacing: 8) {
                ProgressView(value: min(position, duration), total: duration)
                    .overlay { segmentGaps(duration: duration) }
                    .compositingGroup()
                    .overlay { scrubPreviewView(duration: duration, longForm: longForm) }
                    .accessibilityLabel("Playback position")
                    .accessibilityValue(spokenPosition(position, of: duration))
                HStack {
                    // tvOS has no on-screen play button, so this is the only sign playback is paused.
                    if player.status == .paused {
                        Image(systemName: "pause.fill")
                            .accessibilityLabel("Paused")
                    }
                    Text(format(position, longForm: longForm))
                        .accessibilityHidden(true)
                    Spacer()
                    endTime(remaining: duration - position)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 16)
                    Text("−" + format(duration - position, longForm: longForm))
                        .accessibilityHidden(true)
                }
                .font(timeFont)
            }
            #else
            HStack(spacing: 12) {
                // The slider carries both times for VoiceOver.
                Text(format(position, longForm: longForm))
                    #if os(macOS)
                    .foregroundStyle(.secondary)
                    #endif
                    .accessibilityHidden(true)
                slider(duration: duration, position: position, longForm: longForm)
                Text("−" + format(duration - position, longForm: longForm))
                    #if os(macOS)
                    .foregroundStyle(.secondary)
                    #endif
                    .accessibilityHidden(true)
                #if os(iOS)
                // A portrait phone's bar is already short.
                if !isPortraitPhone {
                    endTime(remaining: duration - position)
                        .foregroundStyle(.secondary)
                }
                #endif
            }
            #if os(macOS)
            .font(.caption.monospacedDigit())
            #else
            .font(timeFont)
            #endif
            #endif
        } else {
            // Live streams and files still loading have no duration to scrub through.
            Text(format(player.position, longForm: false))
                .font(timeFont)
        }
    }

    #if !os(macOS)
    /// When playback will finish at the current speed, as the TV app shows it: whether there's
    /// time to finish tonight, without the arithmetic.
    private func endTime(remaining: Double) -> some View {
        // The device locale, unlike other dates (`Locale.interface`): a clock follows its 12- or 24-hour setting.
        Text("Ends at \(Date.now.addingTimeInterval(remaining / player.speed), format: .dateTime.hour().minute())")
    }

    /// Thin cuts through the bar where an intro, recap or credits starts or ends: where the
    /// episode really ends and where a scrub will land, without adding colour.
    private func segmentGaps(duration: Double) -> some View {
        GeometryReader { proxy in
            ForEach(player.segmentBoundaries, id: \.self) { mark in
                Rectangle()
                    .frame(width: Self.gapWidth)
                    .offset(x: proxy.size.width * mark / duration - Self.gapWidth / 2)
            }
        }
        .blendMode(.destinationOut)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static var gapWidth: CGFloat {
        #if os(tvOS)
        4
        #else
        2
        #endif
    }
    #endif

    /// "12 minutes, 4 seconds of 1 hour, 40 minutes": read as a clock time, "12:04" sounds
    /// like the time of day.
    private func spokenPosition(_ position: Double, of duration: Double) -> String {
        func spoken(_ seconds: Double) -> String {
            Duration.seconds(Int(max(seconds, 0)))
                .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2).locale(.interface))
        }
        return "\(spoken(position)) of \(spoken(duration))"
    }

    /// Times are read at a glance over bright frames, on Apple TV from across the room.
    private var timeFont: Font {
        #if os(tvOS)
        .callout.monospacedDigit().weight(.medium)
        #else
        .caption.monospacedDigit().weight(.medium)
        #endif
    }

    #if os(iOS)
    /// A translucent bar that thickens under the finger, as in the TV app. Drags move the
    /// position by how far the finger travels rather than jumping to where it landed, so
    /// grabbing the bar never skips.
    private func slider(duration: Double, position: Double, longForm: Bool) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.white.opacity(0.3))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.white)
                        .frame(width: proxy.size.width * min(max(position / duration, 0), 1))
                }
                .overlay { segmentGaps(duration: duration) }
                .compositingGroup()
                .clipShape(.capsule)
                .frame(height: scrubPosition == nil && dragStart == nil ? 6 : 12)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStart ?? player.position
                        dragStart = start
                        // Until the finger moves, the touch only thickens the bar: a scrub position
                        // would start the preview, a second connection to the host, for nothing.
                        guard abs(value.translation.width) > 2 || scrubPosition != nil else { onInteract(); return }
                        scrubPosition = min(max(start + value.translation.width / proxy.size.width * duration, 0), duration)
                        onInteract()
                    }
                    .onEnded { value in
                        // A touch that didn't move only shows the bar thicken; seeking would
                        // jump to the nearest keyframe.
                        if abs(value.translation.width) > 2, let target = scrubPosition {
                            player.seek(toKeyframeNear: target)
                        }
                        scrubPosition = nil
                        dragStart = nil
                        onInteract()
                    })
        }
        .frame(height: 44)
        .animation(.easeOut(duration: 0.15), value: scrubPosition == nil && dragStart == nil)
        .overlay { scrubPreviewView(duration: duration, longForm: longForm) }
        // Presented as the slider it is: an element with only an adjustable action was reported
        // as a plain element, which UI automation couldn't adjust. Each step is 10 seconds.
        .accessibilityRepresentation {
            Slider(value: Binding(get: { position }, set: { player.seek(to: $0); onInteract() }),
                   in: 0...duration, step: 10)
                .accessibilityLabel("Playback position")
                .accessibilityValue(spokenPosition(position, of: duration))
        }
    }
    #elseif os(macOS)
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
        .accessibilityValue(spokenPosition(position, of: duration))
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

/// The system's route picker, for AirPlay to a TV or speakers.
private struct AirPlayButton: UIViewRepresentable {
    @AppStorage(Accent.storageKey) private var accent = Accent.white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        // The screen icon, and TVs listed first: this sends the picture, not just sound.
        picker.prioritizesVideoDevices = true
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
