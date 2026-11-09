import LogeCore
import SwiftUI

/// Everything needed to start playback.
struct PlaybackRequest: Hashable {
    var title: String
    var url: URL
    var headers: [String: String] = [:]
    /// What progress is recorded against; nil for playback that shouldn't be remembered.
    var item: WatchItem?
    var startAt: Double?
    /// The addon the stream came from, where the next episode is looked up.
    var providerURL: String?
    /// The addon's grouping of the stream's release and quality, to keep for the next episode.
    var bingeGroup: String?
    /// Subtitles the stream comes with, offered next to the file's own.
    var subtitles: [Subtitle] = []
    /// The file's name, which subtitle addons use to find matching timings.
    var filename: String?
}

/// The player screen: controls and gestures over the session's video.
struct PlayerView: View {
    #if os(macOS)
    static let windowID = "player"
    #endif

    @State private var controlsVisible = true
    @State private var lastInteraction = Date.now
    @State private var scrubPosition: Double?
    @State private var scrubPreview: ScrubPreview?
    @State private var isMenuOpen = false
    @State private var adjustingTiming: MPVPlayer.Track.Kind?
    @State private var seekFlash: SeekFlash?
    /// Only the Mac goes full screen from here; everywhere else the player already is.
    @State private var isFullScreen = false

    @Environment(PlaybackSession.self) private var session
    #if os(tvOS)
    @FocusState private var surfaceFocused: Bool
    @FocusState private var skipFocused: Bool
    @FocusState private var nextFocus: NextEpisodeOverlay.Focus?
    @State private var scrubStart: Double?
    /// Info, Subtitles and Audio, shown by swiping down.
    @State private var isPanelShown = false
    #endif
    #if os(macOS)
    @Environment(\.appearsActive) private var windowIsActive
    /// Where the pointer is over the player; nil while it's elsewhere.
    @State private var pointerLocation: CGPoint?
    @State private var window: NSWindow?
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @Environment(\.dismiss) private var dismiss

    private var player: MPVPlayer? { session.player }

    var body: some View {
        @Bindable var session = session
        ZStack {
            Color.black.ignoresSafeArea()
            if let player, let current = session.current {
                MPVVideoView(player: player).ignoresSafeArea()
                    .id(ObjectIdentifier(player))
                #if os(tvOS)
                // It would take the focus the failure's buttons need, with nothing to control.
                if !player.status.isFailed {
                    remoteSurface(player)
                }
                #else
                touchSurface(player)
                #endif
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--playback-ui-test") {
                    PlaybackFixtureDiagnostics(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                #endif
                if let seekFlash {
                    SeekFlashView(flash: seekFlash)
                }
                if player.isWaiting && !transportVisible {
                    ProgressView().controlSize(.large)
                }
                if session.isTryingAnotherSource && player.isWaiting {
                    Text("Trying another source…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .offset(y: 56)
                } else if player.status == .buffering, let speed = player.playbackInfo.downloadSpeed {
                    // Tells a slow connection apart from a stalled source.
                    Text("Downloading at \(PlaybackInfoView.bitrate(speed))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .offset(y: 56)
                }
                if case .failed(let message) = player.status {
                    failure(message)
                } else {
                    if controlsVisible {
                        PlayerControls(
                            title: current.title,
                            item: current.item,
                            player: player,
                            pictureInPicture: session.pictureInPicture,
                            scrubPosition: $scrubPosition,
                            scrubPreview: scrubPreview?.image,
                            isMenuOpen: $isMenuOpen,
                            adjustingTiming: $adjustingTiming,
                            onClose: closePlayback,
                            onChooseSource: chooseSource,
                            onInteract: showControls,
                            isFullScreen: isFullScreen,
                            onToggleFullScreen: toggleFullScreen
                        )
                        .transition(.opacity)
                    }
                    if let skip = player.availableSkip, player.status != .ended {
                        skipOffer(skip, player: player)
                    }
                    #if os(tvOS)
                    if isPanelShown {
                        PlayerPanel(title: current.title, player: player, onInteract: showControls,
                                    onChooseSource: chooseSource)
                            .transition(.opacity)
                    }
                    #endif
                    if let next = session.next, showsNextEpisode(player) {
                        #if os(tvOS)
                        NextEpisodeOverlay(next: next, hasEnded: player.status == .ended, play: playNext,
                                           focus: $nextFocus, onCancel: focusSurface)
                        #else
                        NextEpisodeOverlay(next: next, hasEnded: player.status == .ended, play: playNext)
                        #endif
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .onAppear {
            #if os(iOS)
            AppDelegate.setAllowsLandscape(true)
            #endif
            session.screenDidAppear()
        }
        .onDisappear {
            #if os(iOS)
            AppDelegate.setAllowsLandscape(false)
            #endif
            #if os(macOS)
            NSCursor.setHiddenUntilMouseMoves(false)
            #endif
            scrubPreview = nil
            session.screenDidDisappear()
        }
        .onChange(of: session.current) { _, _ in
            scrubPosition = nil
            scrubPreview = nil
            adjustingTiming = nil
            #if os(tvOS)
            scrubStart = nil
            // A source chosen from the panel has done what the panel was opened for.
            isPanelShown = false
            #endif
            showControls()
        }
        .onChange(of: scrubPosition) { _, position in
            guard let position, let current = session.current else { return }
            // Started on the first scrub, and again when the source or episode has changed.
            if scrubPreview?.url != current.url {
                scrubPreview = ScrubPreview(url: current.url, headers: current.headers)
            }
            scrubPreview?.show(position)
        }
        .task(id: scrubPosition == nil) {
            // Kept for a while after a scrub, since reopening the file takes a moment and
            // scrubs tend to come in a row; then its connection and decoder are let go.
            guard scrubPosition == nil, let scrubPreview else { return }
            scrubPreview.clear()
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            self.scrubPreview = nil
        }
        // Closing a menu counts as an interaction, so the countdown starts over.
        .onChange(of: isMenuOpen) { _, open in if !open { showControls() } }
        .alert(player?.trackError != nil ? "Couldn't change track" : "Couldn't start Picture in Picture", isPresented: Binding(
            get: { player?.trackError != nil || session.pictureInPicture?.failureMessage != nil },
            set: { if !$0 { player?.dismissTrackError(); session.pictureInPicture?.dismissFailure() } }
        )) {
            Button("OK") { player?.dismissTrackError(); session.pictureInPicture?.dismissFailure() }
        } message: {
            Text(player?.trackError ?? session.pictureInPicture?.failureMessage ?? "")
        }
        .sheet(item: $session.choosingSource) { SourcesView(route: $0, isChoosing: true) }
        .onChange(of: session.choosingSource == nil) { _, closed in isMenuOpen = !closed || panelIsShown }
        .task(id: AutoHide(lastInteraction: lastInteraction, isPlaying: player?.status == .playing)) {
            // Restarts on each interaction and when playback starts, so controls shown
            // during a slow load still hide once the video is running. Cancellation
            // means one of those happened again.
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            if player?.status == .playing && scrubPosition == nil && !isMenuOpen && adjustingTiming == nil {
                controlsVisible = false
            }
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            player?.togglePause()
            showControls()
        }
        .onMoveCommand { direction in
            // A swipe that scrubs shouldn't also jump 10 seconds.
            guard scrubStart == nil else { return }
            switch direction {
            // An offer holds focus for as long as it shows, which shouldn't stop these working.
            case .left where surfaceFocused || skipFocused: player?.seek(by: -10)
            case .right where surfaceFocused || skipFocused: player?.seek(by: 10)
            case .down where (surfaceFocused || skipFocused) && !isPanelShown: isPanelShown = true
            // The offers sit on top of the surface, so the focus engine can't move to them by itself.
            case .up where surfaceFocused && !isPanelShown:
                if player?.availableSkip != nil {
                    skipFocused = true
                } else if let player, session.next != nil, showsNextEpisode(player) {
                    nextFocus = .play
                }
            case .down where nextFocus != nil: focusSurface()
            default: break
            }
            showControls()
        }
        // Menu closes the panel first; without it, Menu leaves the player as usual.
        .onExitCommand {
            if isPanelShown {
                isPanelShown = false
            } else if nextFocus != nil && player?.status != .ended {
                focusSurface()
            } else {
                closePlayback()
            }
        }
        .onChange(of: isPanelShown) { _, shown in
            isMenuOpen = shown
            if !shown { surfaceFocused = true }
        }
        // The countdown leaves ten seconds to act in, and Select has nothing else to do at the end.
        .onChange(of: player?.status == .ended && session.next != nil) { _, waiting in
            if waiting && !isPanelShown { nextFocus = .play }
        }
        .animation(.easeInOut(duration: 0.2), value: isPanelShown)
        #elseif os(macOS)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { player?.togglePause(); showControls(); return .handled }
        .onKeyPress(.leftArrow) { player?.seek(by: -10); showControls(); return .handled }
        .onKeyPress(.rightArrow) { player?.seek(by: 10); showControls(); return .handled }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                // Layout changes report a pointer that hasn't moved; counting those would
                // keep the controls from ever hiding.
                guard location != pointerLocation else { return }
                pointerLocation = location
                showControls()
            case .ended:
                pointerLocation = nil
            }
        }
        // Not hide() and unhide(): those must balance, and this can't leave the cursor hidden,
        // since the system brings it back on the next movement.
        .onChange(of: controlsVisible) { _, visible in
            if !visible && pointerLocation != nil && windowIsActive {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
        .onChange(of: windowIsActive) { _, active in
            if !active { NSCursor.setHiddenUntilMouseMoves(false) }
        }
        .background {
            WindowReader { window in
                self.window = window
                isFullScreen = window?.styleMask.contains(.fullScreen) == true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) {
            if $0.object as? NSWindow === window { isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) {
            if $0.object as? NSWindow === window { isFullScreen = false }
        }
        #else
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(.hidden)
        #endif
    }

    // MARK: Input

    #if os(tvOS)
    /// tvOS only delivers remote presses to focused views, and with the controls hidden
    /// nothing else on screen is focusable. This invisible button covers the picture.
    /// It stands aside while the panel or Up Next has focus: lying under their buttons, it
    /// would be what the focus engine picks instead of the button beside the focused one.
    private func remoteSurface(_ player: MPVPlayer) -> some View {
        Button {
            player.togglePause()
            showControls()
        } label: {
            Color.clear
        }
        .buttonStyle(InvisibleButtonStyle())
        .disabled(isPanelShown || nextFocus != nil)
        .focused($surfaceFocused)
        .padding(.top, 200)
        .ignoresSafeArea(edges: .bottom)
        .onAppear { surfaceFocused = true }
        // Hiding the controls removes the menus; if one had focus, nothing would be
        // left to receive remote presses.
        .onChange(of: controlsVisible) { _, visible in
            if !visible && !skipFocused && nextFocus == nil { surfaceFocused = true }
        }
        .background {
            RemoteSwipeReader(
                onChanged: { fraction in scrub(by: fraction, player: player) },
                onEnded: { finishScrub(player) }
            )
        }
    }

    /// A full swipe across the touch surface moves five minutes, or a tenth of a long film.
    private func scrub(by fraction: Double, player: MPVPlayer) {
        guard surfaceFocused || skipFocused, let duration = player.duration, abs(fraction) > 0.03 else { return }
        let start = scrubStart ?? player.position
        scrubStart = start
        let span = max(300, duration * 0.1)
        scrubPosition = min(max(start + fraction * span, 0), duration)
        showControls()
    }

    private func finishScrub(_ player: MPVPlayer) {
        if let target = scrubPosition {
            player.seek(toKeyframeNear: target)
        }
        scrubStart = nil
        scrubPosition = nil
    }

    private func focusSurface() {
        nextFocus = nil
        surfaceFocused = true
    }

    private struct InvisibleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.contentShape(.rect)
        }
    }
    #else
    /// Tap to show or hide the controls. On iPhone also: double-tap either side to
    /// skip 10 seconds, pinch to zoom, and swipe down to close.
    private func touchSurface(_ player: MPVPlayer) -> some View {
        HStack(spacing: 0) {
            tapZone(player, seconds: -10)
            tapZone(player, seconds: 10)
        }
        #if os(iOS)
        .gesture(MagnifyGesture().onEnded { value in
            if value.magnification > 1.15 { player.setZoomToFill(true) }
            if value.magnification < 0.87 { player.setZoomToFill(false) }
        })
        .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
            if value.translation.height > 120 && abs(value.translation.width) < 80 {
                closePlayback()
            }
        })
        #endif
    }

    private func tapZone(_ player: MPVPlayer, seconds: Double) -> some View {
        Color.clear
            .contentShape(.rect)
            #if os(iOS)
            .onTapGesture(count: 2) {
                player.seek(by: seconds)
                seekFlash = SeekFlash(seconds: Int(seconds))
            }
            #endif
            #if os(macOS)
            .onTapGesture(count: 2, perform: toggleFullScreen)
            #endif
            .onTapGesture {
                // Like a menu, the timing panel closes when the picture is tapped; hiding it
                // with the controls would bring it back with them and keep them from hiding.
                if adjustingTiming != nil {
                    adjustingTiming = nil
                    showControls()
                } else if controlsVisible {
                    controlsVisible = false
                } else {
                    showControls()
                }
            }
    }
    #endif

    private struct AutoHide: Equatable {
        let lastInteraction: Date
        let isPlaying: Bool
    }

    private var chooseSource: (() -> Void)? {
        session.canChooseSource ? { session.chooseSource() } : nil
    }

    private var panelIsShown: Bool {
        #if os(tvOS)
        isPanelShown
        #else
        false
        #endif
    }

    private func toggleFullScreen() {
        #if os(macOS)
        window?.toggleFullScreen(nil)
        #endif
    }

    /// Whether the on-screen play button is showing; it takes the spinner's place while loading.
    private var transportVisible: Bool {
        #if os(tvOS)
        false
        #else
        controlsVisible
        #endif
    }

    private func skipOffer(_ skip: PlaybackChapter.Skip, player: MPVPlayer) -> some View {
        Button(skip.kind.rawValue) {
            if let duration = player.duration, skip.end >= duration {
                // Credits run to the end of the file. Seeking right to the end while paused leaves
                // mpv on the last frame without reaching the end, so Up Next never counts down;
                // stopping just short and playing out the rest always ends it.
                player.seek(to: max(duration - 0.2, 0))
                player.play()
            } else {
                player.seek(to: skip.end)
            }
            showControls()
        }
        .font(.subheadline.weight(.semibold))
        .frame(minHeight: 44)
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        #if os(tvOS)
        .focused($skipFocused)
        .onChange(of: skipFocused) { _, focused in if focused { showControls() } }
        // Select skips rather than pauses while an offer shows, which is the point of offering it.
        .onAppear { if !isPanelShown { skipFocused = true } }
        .onDisappear { if !isPanelShown { surfaceFocused = true } }
        #endif
        // Keep the offer visible while transport controls hide, clear of their bars and Up Next.
        #if os(iOS)
        // Above the menus, in line with their trailing edge; the title holds the leading corner.
        .padding(.horizontal, 20)
        .padding(.bottom, skipBottomPadding(player))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        #else
        .padding(.horizontal, 24)
        .padding(.bottom, skipBottomPadding(player))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        #endif
    }

    private func skipBottomPadding(_ player: MPVPlayer) -> CGFloat {
        #if !os(iOS)
        let hasNextOffer = session.next != nil && showsNextEpisode(player)
        #endif
        #if os(tvOS)
        return hasNextOffer ? 320 : (controlsVisible ? 200 : 48)
        #elseif os(macOS)
        return hasNextOffer || adjustingTiming != nil ? 240 : (controlsVisible ? 100 : 32)
        #else
        // 12 above the menus: their top is the padding (12), the timeline (44), the gap (10)
        // and the menus (44) up from the bottom. A portrait phone has the title on a row of
        // its own above them, up to two lines. The timing panel replaces them and is taller.
        // Up Next is in the top corner on iOS.
        if adjustingTiming != nil { return 140 }
        let isPortraitPhone = horizontalSizeClass == .compact && verticalSizeClass == .regular
        return controlsVisible ? (isPortraitPhone ? 200 : 122) : 32
        #endif
    }

    private func closePlayback() {
        session.end()
        // Dismiss the presenting cover/window as well as clearing the session. This
        // also works when its presentation binding is already false during teardown.
        dismiss()
    }

    private func showControls() {
        controlsVisible = true
        lastInteraction = .now
    }

    private func playNext() {
        session.playNext()
        showControls()
    }

    // MARK: Next episode

    private func showsNextEpisode(_ player: MPVPlayer) -> Bool {
        guard let duration = player.duration else { return false }
        return player.status == .ended || player.position >= NextEpisode.offerTime(duration: duration)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Couldn't play this source")
                .font(.headline)
            Text(Self.explanation(ofFailure: message))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                session.retry()
                showControls()
            }
            .padding(.top, 8)
            if let chooseSource {
                Button("Choose another source", action: chooseSource)
                    .padding(.top, 8)
            }
            Button("Close", action: closePlayback)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    /// mpv's messages are lower-case fragments that say little to a viewer.
    private static func explanation(ofFailure message: String) -> String {
        switch message {
        case "loading failed":
            "The server didn't send the video. The link may have expired, or the server may be busy."
        case "unrecognized file format":
            "This file is in a format the player can't read."
        case "no audio or video data played":
            "The file opened, but there was nothing in it to play."
        default:
            message.prefix(1).uppercased() + message.dropFirst() + "."
        }
    }
}

#if os(macOS)
/// Reports the window this view is in, which isn't always the key window.
private struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> Reader {
        let view = Reader()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: Reader, context: Context) {}

    final class Reader: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange?(window)
        }
    }
}
#endif

/// Feedback for a double-tap skip: "+10" or "−10" on the side that was tapped.
private struct SeekFlash: Equatable {
    let seconds: Int
    let id = UUID()
}

private struct SeekFlashView: View {
    let flash: SeekFlash
    @State private var visible = true

    var body: some View {
        Label(flash.seconds > 0 ? "\(flash.seconds)" : "\(-flash.seconds)",
              systemImage: flash.seconds > 0 ? "goforward" : "gobackward")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.black.opacity(0.45), in: .capsule)
            .opacity(visible ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: flash.seconds > 0 ? .trailing : .leading)
            .padding(.horizontal, 48)
            .allowsHitTesting(false)
            .task(id: flash.id) {
                visible = true
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeOut(duration: 0.3)) { visible = false }
            }
    }
}
