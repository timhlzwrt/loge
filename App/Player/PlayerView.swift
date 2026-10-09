import MediaCore
import SwiftUI

/// Everything needed to start playback. Codable so macOS can open it in its own window.
struct PlaybackRequest: Codable, Hashable, Identifiable {
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

    var id: URL { url }
}

struct PlayerView: View {
    // The request changes when the next episode starts, without leaving the player.
    @State private var current: PlaybackRequest

    // Created on appear rather than as a `@State` default, because SwiftUI evaluates
    // default values every time the view is re-initialised and each player
    // starts its own mpv instance.
    @State private var player: MPVPlayer?
    @State private var controlsVisible = true
    @State private var lastInteraction = Date.now
    @State private var lastRecordedPosition: Double = 0
    @State private var scrubPosition: Double?
    @State private var hasRememberedSource = false
    @State private var episodes: [Video] = []
    @State private var next: PlaybackRequest?
    @State private var seekFlash: SeekFlash?

    @Environment(LibraryStore.self) private var library
    @Environment(AddonStore.self) private var addons
    // Empty means "file default" for audio and "off" for subtitles.
    @AppStorage(PlaybackPreferences.audioKey) private var audioLanguage = ""
    @AppStorage(PlaybackPreferences.subtitleKey) private var subtitleLanguage = ""
    @AppStorage(PlaybackPreferences.subtitleScaleKey) private var subtitleScale = 1.0
    #if os(tvOS)
    @FocusState private var surfaceFocused: Bool
    @State private var scrubStart: Double?
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(request: PlaybackRequest) {
        _current = State(initialValue: request)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                MPVVideoView(player: player).ignoresSafeArea()
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
                if case .failed(let message) = player.status {
                    failure(message)
                } else {
                    if controlsVisible {
                        PlayerControls(
                            title: current.title,
                            player: player,
                            scrubPosition: $scrubPosition,
                            onClose: { dismiss() },
                            onInteract: showControls
                        )
                        .transition(.opacity)
                    }
                    if let next, showsNextEpisode(player) {
                        NextEpisodeOverlay(nextTitle: next.title, hasEnded: player.status == .ended) {
                            play(next)
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .task(id: current.item?.metaID) { await loadEpisodes() }
        .task(id: nextLookupKey) { await findNextEpisode() }
        .onChange(of: player?.position) {
            // Often enough that a crash or force-quit loses little, rarely enough not to churn storage.
            if let position = player?.position, abs(position - lastRecordedPosition) >= 10 {
                recordProgress()
            }
        }
        .onChange(of: player?.status) { _, status in
            switch status {
            case .playing: rememberSource()
            // A remembered source that no longer plays shouldn't be tried again.
            case .failed:
                if let item = current.item { library.forgetSource(metaID: item.metaID) }
            default: break
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                player?.pause()
                player?.setVideoEnabled(false)
            case .active:
                player?.setVideoEnabled(true)
            default:
                break
            }
        }
        .task(id: AutoHide(lastInteraction: lastInteraction, isPlaying: player?.status == .playing)) {
            // Restarts on each interaction and when playback starts, so controls shown
            // during a slow load still hide once the video is running. Cancellation
            // means one of those happened again.
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            if player?.status == .playing && scrubPosition == nil {
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
            default: break
            }
            showControls()
        }
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
    /// below the top bar, so pressing up still moves focus to the menus above it.
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
            if !visible { surfaceFocused = true }
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
            player.seek(to: target)
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
                dismiss()
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
                if controlsVisible { controlsVisible = false } else { showControls() }
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

    private func showControls() {
        controlsVisible = true
        lastInteraction = .now
    }

    // MARK: Lifecycle

    private func start() {
        let player = MPVPlayer()
        self.player = player
        load(current, into: player)
        #if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    private func load(_ request: PlaybackRequest, into player: MPVPlayer) {
        player.setSubtitleScale(subtitleScale)
        player.load(
            request.url,
            headers: request.headers,
            startAt: request.startAt,
            audioLanguage: audioLanguage.isEmpty ? nil : audioLanguage,
            subtitleLanguage: subtitleLanguage.isEmpty ? nil : subtitleLanguage
        )
    }

    private func stop() {
        recordProgress()
        player?.shutDown()
        player = nil
        #if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    private func recordProgress() {
        // Live streams have no duration, and nothing is known before the file has loaded.
        guard let item = current.item, let player, let duration = player.duration, player.position > 0 else { return }
        library.record(item, position: player.position, duration: duration)
        lastRecordedPosition = player.position
    }

    private func rememberSource() {
        guard !hasRememberedSource, let item = current.item, let providerURL = current.providerURL else { return }
        hasRememberedSource = true
        library.rememberSource(
            RememberedSource(itemID: item.id, providerURL: providerURL, url: current.url,
                             headers: current.headers, bingeGroup: current.bingeGroup),
            metaID: item.metaID
        )
    }

    // MARK: Next episode

    private func loadEpisodes() async {
        guard let item = current.item, item.type == "series", episodes.isEmpty,
              let client = addons.addons.metaClient(type: item.type, id: item.metaID)
        else { return }
        episodes = (try? await client.meta(type: item.type, id: item.metaID).videos) ?? []
    }

    /// Changes once the episode nears its end, which is when the lookup starts.
    private var nextLookupKey: String? {
        guard let item = current.item, !episodes.isEmpty, let duration = player?.duration,
              let position = player?.position,
              position >= NextEpisode.offerTime(duration: duration) - 60 || player?.status == .ended
        else { return nil }
        return item.id
    }

    private func findNextEpisode() async {
        guard nextLookupKey != nil, next == nil else { return }
        next = try? await NextEpisode.request(after: current, episodes: episodes)
    }

    private func showsNextEpisode(_ player: MPVPlayer) -> Bool {
        guard let duration = player.duration else { return false }
        return player.status == .ended || player.position >= NextEpisode.offerTime(duration: duration)
    }

    private func play(_ request: PlaybackRequest) {
        guard let player else { return }
        if let item = current.item {
            recordProgress()
            // Skipping the credits shouldn't leave the episode looking unfinished.
            library.markWatched([item])
        }
        current = request
        next = nil
        hasRememberedSource = false
        lastRecordedPosition = 0
        load(request, into: player)
        showControls()
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Couldn't play this source")
                .font(.headline)
            // mpv's messages are lower-case fragments such as "loading failed".
            Text(message.prefix(1).uppercased() + message.dropFirst() + ".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Choose another source") { dismiss() }
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
            .padding(18)
            .background(.black.opacity(0.4), in: .circle)
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
