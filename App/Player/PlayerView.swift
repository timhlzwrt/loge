import SwiftUI

/// Everything needed to start playback. Codable so macOS can open it in its own window.
struct PlaybackRequest: Codable, Hashable, Identifiable {
    let title: String
    let url: URL
    var headers: [String: String] = [:]

    var id: URL { url }
}

struct PlayerView: View {
    let request: PlaybackRequest

    // Created on appear rather than as a `@State` default, because SwiftUI evaluates
    // default values every time the view is re-initialised and each player
    // starts its own mpv instance.
    @State private var player: MPVPlayer?
    @State private var controlsVisible = true
    @State private var lastInteraction = Date.now
    #if os(tvOS)
    @FocusState private var surfaceFocused: Bool
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                MPVVideoView(player: player).ignoresSafeArea()
                #if os(tvOS)
                remoteSurface(player)
                #endif
                if player.isWaiting && !transportVisible {
                    ProgressView().controlSize(.large)
                }
                if case .failed(let message) = player.status {
                    failure(message)
                } else if controlsVisible {
                    PlayerControls(title: request.title, player: player, onClose: { dismiss() }, onInteract: showControls)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        #if !os(tvOS)
        .contentShape(.rect)
        .onTapGesture {
            if controlsVisible { controlsVisible = false } else { showControls() }
        }
        #endif
        .onAppear(perform: start)
        .onDisappear(perform: stop)
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
            if player?.status == .playing {
                controlsVisible = false
            }
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            player?.togglePause()
            showControls()
        }
        .onMoveCommand { direction in
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

    #if os(tvOS)
    /// tvOS only delivers remote presses to focused views, and with the controls hidden
    /// nothing else on screen is focusable. This invisible button covers the picture
    /// below the top bar, so pressing up still moves focus to the track menu above it.
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
        // Hiding the controls removes the track menu; if it had focus, nothing would be
        // left to receive remote presses.
        .onChange(of: controlsVisible) { _, visible in
            if !visible { surfaceFocused = true }
        }
    }

    private struct InvisibleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.contentShape(.rect)
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

    private func start() {
        let player = MPVPlayer()
        player.load(request.url, headers: request.headers)
        self.player = player
        #if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    private func stop() {
        player?.shutDown()
        player = nil
        #if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    private func showControls() {
        controlsVisible = true
        lastInteraction = .now
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

private struct PlayerControls: View {
    let title: String
    let player: MPVPlayer
    let onClose: () -> Void
    let onInteract: () -> Void

    /// Where the scrubber is while being dragged; nil otherwise, so it follows playback.
    @State private var scrubPosition: Double?

    var body: some View {
        VStack(alignment: .leading) {
            topBar
            Spacer()
            #if !os(tvOS)
            transport
                .frame(maxWidth: .infinity)
            Spacer()
            #endif
            timeline
        }
        #if !os(tvOS)
        // tvOS already keeps content inside its overscan-safe margins.
        .padding(20)
        #endif
        #if !os(tvOS)
        .foregroundStyle(.white)
        #endif
        .background {
            // Scrims behind the bars keep white controls readable over bright frames.
            VStack {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            #if os(iOS)
            Button("Close", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.title3)
            #endif
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            TrackMenu(player: player, onInteract: onInteract)
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
    }

    #if !os(tvOS)
    private var transport: some View {
        HStack(spacing: 56) {
            Button("Back 10 seconds", systemImage: "gobackward.10") {
                player.seek(by: -10)
                onInteract()
            }
            Group {
                if player.isWaiting {
                    ProgressView().controlSize(.large)
                } else {
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
        .font(.title)
        .buttonStyle(.plain)
    }
    #endif

    private var timeline: some View {
        VStack(spacing: 6) {
            if let duration = player.duration, duration > 0 {
                #if os(tvOS)
                ProgressView(value: min(player.position, duration), total: duration)
                #else
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
                #endif
                HStack {
                    #if os(tvOS)
                    // tvOS has no on-screen play button, so this is the only sign playback is paused.
                    Image(systemName: player.status == .paused ? "pause.fill" : "play.fill")
                    #endif
                    Text(format(scrubPosition ?? player.position, longForm: duration >= 3600))
                    Spacer()
                    Text("-" + format(duration - (scrubPosition ?? player.position), longForm: duration >= 3600))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                // Live streams and files still loading have no duration to scrub through.
                Text(format(player.position, longForm: false))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func format(_ seconds: Double, longForm: Bool) -> String {
        Duration.seconds(max(seconds, 0)).formatted(.time(pattern: longForm ? .hourMinuteSecond : .minuteSecond))
    }
}

private struct TrackMenu: View {
    let player: MPVPlayer
    let onInteract: () -> Void

    var body: some View {
        let audio = Self.distinct(player.tracks.filter { $0.kind == .audio })
        let subtitles = Self.distinct(player.tracks.filter { $0.kind == .sub })
        // A single audio track and no subtitles leaves nothing to choose.
        if audio.count > 1 || !subtitles.isEmpty {
            Menu {
                if audio.count > 1 {
                    Section("Audio") {
                        ForEach(audio) { track in
                            toggle(track.displayName, isOn: track.isSelected) { player.select(track, kind: .audio) }
                        }
                    }
                }
                if !subtitles.isEmpty {
                    Section("Subtitles") {
                        toggle("Off", isOn: !subtitles.contains(where: \.isSelected)) { player.select(nil, kind: .sub) }
                        ForEach(subtitles) { track in
                            toggle(track.displayName, isOn: track.isSelected) { player.select(track, kind: .sub) }
                        }
                    }
                }
            } label: {
                Label("Audio and subtitles", systemImage: "captions.bubble")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .simultaneousGesture(TapGesture().onEnded(onInteract))
        }
    }

    /// HLS streams repeat the same rendition once per quality level; listing identical
    /// entries helps nobody, so keep one of each, preferring the selected one.
    private static func distinct(_ tracks: [MPVPlayer.Track]) -> [MPVPlayer.Track] {
        var byName: [String: MPVPlayer.Track] = [:]
        var order: [String] = []
        for track in tracks {
            if let existing = byName[track.displayName] {
                if track.isSelected && !existing.isSelected { byName[track.displayName] = track }
            } else {
                byName[track.displayName] = track
                order.append(track.displayName)
            }
        }
        return order.compactMap { byName[$0] }
    }

    /// A menu item that shows a checkmark when on and selects when chosen.
    private func toggle(_ title: String, isOn: Bool, select: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in select() }))
    }
}
