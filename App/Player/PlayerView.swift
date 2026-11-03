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
    /// The sources for what's playing, to switch to another file.
    @State private var choosingSource: SourcesRoute?

    @Environment(PlaybackSession.self) private var session
    #if os(tvOS)
    @FocusState private var surfaceFocused: Bool
    @FocusState private var skipFocused: Bool
    @State private var scrubStart: Double?
    /// Info, Subtitles and Audio, shown by swiping down.
    @State private var isPanelShown = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    private var player: MPVPlayer? { session.player }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player, let current = session.current {
                MPVVideoView(player: player).ignoresSafeArea()
                    .id(ObjectIdentifier(player))
                #if os(tvOS)
                remoteSurface(player)
                #else
                touchSurface(player)
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
                            player: player,
                            pictureInPicture: session.pictureInPicture,
                            scrubPosition: $scrubPosition,
                            scrubPreview: scrubPreview?.image,
                            isMenuOpen: $isMenuOpen,
                            adjustingTiming: $adjustingTiming,
                            onClose: closePlayback,
                            onChooseSource: chooseSource(for: current),
                            onInteract: showControls
                        )
                        .transition(.opacity)
                    }
                    if let skip = player.availableSkip, player.status != .ended {
                        skipOffer(skip, player: player)
                    }
                    #if os(tvOS)
                    if isPanelShown {
                        PlayerPanel(title: current.title, player: player, onInteract: showControls)
                            .transition(.opacity)
                    }
                    #endif
                    if let next = session.next, showsNextEpisode(player) {
                        NextEpisodeOverlay(next: next, hasEnded: player.status == .ended) {
                            session.playNext()
                            showControls()
                        }
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
            scrubPreview = nil
            session.screenDidDisappear()
        }
        .onChange(of: session.current) { _, _ in
            scrubPosition = nil
            scrubPreview = nil
            adjustingTiming = nil
            #if os(tvOS)
            scrubStart = nil
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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: session.sceneDidEnterBackground()
            case .active: session.sceneDidBecomeActive()
            default: break
            }
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
        #if os(iOS)
        .sheet(item: $choosingSource) { SourcesView(route: $0, isChoosing: true) }
        .onChange(of: choosingSource == nil) { _, closed in isMenuOpen = !closed }
        #endif
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
            case .left where surfaceFocused: player?.seek(by: -10)
            case .right where surfaceFocused: player?.seek(by: 10)
            case .down where surfaceFocused && !isPanelShown: isPanelShown = true
            default: break
            }
            showControls()
        }
        // Menu closes the panel first; without it, Menu leaves the player as usual.
        .onExitCommand {
            if isPanelShown { isPanelShown = false } else { closePlayback() }
        }
        .onChange(of: isPanelShown) { _, shown in
            isMenuOpen = shown
            if !shown { surfaceFocused = true }
        }
        .animation(.easeInOut(duration: 0.2), value: isPanelShown)
        #elseif os(macOS)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { player?.togglePause(); showControls(); return .handled }
        .onKeyPress(.leftArrow) { player?.seek(by: -10); showControls(); return .handled }
        .onKeyPress(.rightArrow) { player?.seek(by: 10); showControls(); return .handled }
        #else
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(.hidden)
        #endif
    }

    // MARK: Input

    #if os(tvOS)
    /// tvOS only delivers remote presses to focused views, and with the controls hidden
    /// nothing else on screen is focusable. This invisible button covers the picture
    /// below the panel's tabs, so pressing up from it moves focus back into the panel.
    private func remoteSurface(_ player: MPVPlayer) -> some View {
        Button {
            player.togglePause()
            showControls()
        } label: {
            Color.clear
        }
        .buttonStyle(InvisibleButtonStyle())
        .focused($surfaceFocused)
        .padding(.top, 200)
        .ignoresSafeArea(edges: .bottom)
        .onAppear { surfaceFocused = true }
        // Hiding the controls removes the menus; if one had focus, nothing would be
        // left to receive remote presses.
        .onChange(of: controlsVisible) { _, visible in
            if !visible && !skipFocused { surfaceFocused = true }
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
        guard surfaceFocused, let duration = player.duration, abs(fraction) > 0.03 else { return }
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

    /// Whether the on-screen play button is showing; it takes the spinner's place while loading.
    private var transportVisible: Bool {
        #if os(tvOS)
        false
        #else
        controlsVisible
        #endif
    }

    /// Lists the sources for what's playing; not for playback that has no title behind it.
    private func chooseSource(for current: PlaybackRequest) -> (() -> Void)? {
        #if os(iOS)
        guard let item = current.item else { return nil }
        return { choosingSource = SourcesRoute(item: item, title: current.title) }
        #else
        nil
        #endif
    }

    private func skipOffer(_ skip: PlaybackChapter.Skip, player: MPVPlayer) -> some View {
        Button(skip.kind.rawValue) {
            player.seek(to: skip.end)
            showControls()
        }
        .font(.subheadline.weight(.semibold))
        .frame(minHeight: 44)
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        #if os(tvOS)
        .focused($skipFocused)
        .onChange(of: skipFocused) { _, focused in if focused { showControls() } }
        .onDisappear { if !isPanelShown { surfaceFocused = true } }
        #endif
        // Keep the offer visible while transport controls hide, clear of their bars and Up Next.
        .padding(.horizontal, 24)
        .padding(.bottom, skipBottomPadding(player))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func skipBottomPadding(_ player: MPVPlayer) -> CGFloat {
        let hasNextOffer = session.next != nil && showsNextEpisode(player)
        #if os(tvOS)
        return hasNextOffer ? 320 : (controlsVisible ? 200 : 48)
        #elseif os(macOS)
        return hasNextOffer || adjustingTiming != nil ? 240 : (controlsVisible ? 100 : 32)
        #else
        return hasNextOffer ? 240 : (controlsVisible ? 160 : 32)
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

    // MARK: Next episode

    private func showsNextEpisode(_ player: MPVPlayer) -> Bool {
        guard let duration = player.duration else { return false }
        return player.status == .ended || player.position >= NextEpisode.offerTime(duration: duration)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Couldn't play this source")
                .font(.headline)
            // mpv's messages are lower-case fragments such as "loading failed".
            Text(message.prefix(1).uppercased() + message.dropFirst() + ".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let current = session.current, let choose = chooseSource(for: current) {
                Button("Choose another source", action: choose)
                    .padding(.top, 8)
            }
            Button("Close", action: closePlayback)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}

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
