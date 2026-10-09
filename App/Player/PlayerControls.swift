import SwiftUI

/// The overlay shown over playing video: title, menus, transport and timeline.
struct PlayerControls: View {
    let title: String
    let player: MPVPlayer
    /// Where the timeline is being dragged or swiped to; nil while it follows playback.
    @Binding var scrubPosition: Double?
    let onClose: () -> Void
    let onInteract: () -> Void

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
                // A larger target than the glyph, since this is the main way out.
                .frame(width: 44, height: 44)
                .contentShape(.rect)
            #endif
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            TrackMenu(player: player, onInteract: onInteract)
            OptionsMenu(player: player, onInteract: onInteract)
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
                ProgressView(value: min(scrubPosition ?? player.position, duration), total: duration)
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

/// A menu item that shows a checkmark when on and selects when chosen.
private func menuToggle(_ title: String, isOn: Bool, select: @escaping () -> Void) -> some View {
    Button(action: select) {
        if isOn {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

private struct TrackMenu: View {
    let player: MPVPlayer
    let onInteract: () -> Void

    @AppStorage(PlaybackPreferences.subtitleScaleKey) private var subtitleScale = 1.0

    var body: some View {
        let audio = Self.distinct(player.tracks.filter { $0.kind == .audio })
        let subtitles = Self.distinct(player.tracks.filter { $0.kind == .sub })
        // A single audio track and no subtitles leaves nothing to choose.
        if audio.count > 1 || !subtitles.isEmpty {
            Menu {
                if audio.count > 1 {
                    Section("Audio") {
                        ForEach(audio) { track in
                            menuToggle(track.displayName, isOn: track.isSelected) { player.select(track, kind: .audio) }
                        }
                    }
                }
                if !subtitles.isEmpty {
                    Section("Subtitles") {
                        menuToggle("Off", isOn: !subtitles.contains(where: \.isSelected)) { player.select(nil, kind: .sub) }
                        ForEach(subtitles) { track in
                            menuToggle(track.displayName, isOn: track.isSelected) { player.select(track, kind: .sub) }
                        }
                    }
                    Menu("Subtitle Size") {
                        ForEach(PlaybackPreferences.subtitleScales, id: \.scale) { option in
                            menuToggle(option.name, isOn: subtitleScale == option.scale) {
                                subtitleScale = option.scale
                                player.setSubtitleScale(option.scale)
                            }
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
}

/// Playback speed and picture zoom; neither is remembered between videos.
private struct OptionsMenu: View {
    let player: MPVPlayer
    let onInteract: () -> Void

    private static let speeds = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        Menu {
            Section("Speed") {
                ForEach(Self.speeds, id: \.self) { value in
                    menuToggle(value == 1 ? "Normal" : "\(value.formatted())×", isOn: player.speed == value) {
                        player.setSpeed(value)
                    }
                }
            }
            Section {
                menuToggle("Zoom to Fill", isOn: player.isZoomedToFill) {
                    player.setZoomToFill(!player.isZoomedToFill)
                }
            }
        } label: {
            Label("Playback options", systemImage: player.speed == 1 ? "gauge.with.dots.needle.33percent" : "gauge.with.dots.needle.67percent")
                .labelStyle(.iconOnly)
                .font(.title3)
        }
        .simultaneousGesture(TapGesture().onEnded(onInteract))
    }
}
