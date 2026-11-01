#if os(tvOS)
import SwiftUI

/// What swiping down during playback shows, as in the TV app: Info, Subtitles and Audio tabs
/// in a glass capsule at the top, with the chosen tab's settings in a glass panel under it.
struct PlayerPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case info = "Info", subtitles = "Subtitles", audio = "Audio"
        var id: Self { self }
    }

    let title: String
    let player: MPVPlayer
    let onInteract: () -> Void
    @State private var tab = Tab.subtitles
    @State private var showsPlaybackInfo = false
    @FocusState private var focusedTab: Tab?

    var body: some View {
        VStack(spacing: 24) {
            GlassEffectContainer {
                HStack(spacing: 4) {
                    ForEach(Tab.allCases) { tab in
                        Button(tab.rawValue) { self.tab = tab }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .focused($focusedTab, equals: tab)
                            .background(tab == self.tab ? Color.white.opacity(0.2) : .clear, in: .capsule)
                    }
                }
            }
            Group {
                switch tab {
                case .info: info
                case .subtitles: subtitles
                case .audio: audio
                }
            }
            .padding(36)
            .frame(width: 1100, alignment: .topLeading)
            .glassEffect(in: .rect(cornerRadius: 36))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Moving across the tabs switches them, as focus does in the TV app.
        .onChange(of: focusedTab) { _, focused in
            if let focused { tab = focused }
            onInteract()
        }
        // Swiping down came from the picture, so focus has to be brought up here.
        .onAppear { focusedTab = tab }
        .sheet(isPresented: $showsPlaybackInfo) { PlaybackInfoView(player: player) }
    }

    private var info: some View {
        HStack(alignment: .top, spacing: 48) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 24) {
                PanelStepper(label: "Speed", value: PlaybackSpeed.name(player.speed),
                             decrement: step(speedBy: -1), increment: step(speedBy: 1))
                Button(player.isZoomedToFill ? "Fit to Screen" : "Zoom to Fill") {
                    player.setZoomToFill(!player.isZoomedToFill)
                    onInteract()
                }
                Button("Playback Info") { showsPlaybackInfo = true; onInteract() }
            }
            .frame(width: 420, alignment: .leading)
        }
    }

    private var subtitles: some View {
        HStack(alignment: .top, spacing: 48) {
            TrackList(player: player, kind: .sub, onInteract: onInteract)
            VStack(alignment: .leading, spacing: 24) {
                SubtitleSizeStepper(player: player, onInteract: onInteract)
                delayStepper(.sub)
            }
            .frame(width: 420, alignment: .leading)
        }
    }

    private var audio: some View {
        HStack(alignment: .top, spacing: 48) {
            TrackList(player: player, kind: .audio, onInteract: onInteract)
            delayStepper(.audio)
                .frame(width: 420, alignment: .leading)
        }
    }

    private func delayStepper(_ kind: MPVPlayer.Track.Kind) -> some View {
        let delay = kind == .sub ? player.subtitleDelay : player.audioDelay
        return PanelStepper(
            label: "Delay",
            value: TimingFormat.delay(delay),
            decrement: { player.setDelay(TimingFormat.step(delay, by: -0.1), for: kind); onInteract() },
            increment: { player.setDelay(TimingFormat.step(delay, by: 0.1), for: kind); onInteract() }
        )
    }

    private func step(speedBy offset: Int) -> (() -> Void)? {
        let speeds = PlaybackSpeed.all
        guard let index = speeds.firstIndex(of: player.speed), speeds.indices.contains(index + offset) else { return nil }
        return {
            player.setSpeed(speeds[index + offset])
            onInteract()
        }
    }
}

/// "Language" and a list of one kind of track, the active one checked.
private struct TrackList: View {
    let player: MPVPlayer
    let kind: MPVPlayer.Track.Kind
    let onInteract: () -> Void

    var body: some View {
        let tracks = player.distinctTracks(kind)
        let selection = player.selection(for: kind)
        VStack(alignment: .leading, spacing: 8) {
            Text("Language")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Sound can't be turned off, only subtitles.
                    if kind == .sub {
                        row("Off", isSelected: selection.wrappedValue == nil) { selection.wrappedValue = nil }
                    }
                    ForEach(tracks) { track in
                        row(track.displayName, isSelected: track.isSelected) { selection.wrappedValue = track.id }
                    }
                }
            }
            .frame(maxHeight: 420)
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ name: String, isSelected: Bool, select: @escaping () -> Void) -> some View {
        Button {
            select()
            onInteract()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                Text(name)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SubtitleSizeStepper: View {
    let player: MPVPlayer
    let onInteract: () -> Void
    @AppStorage(PlaybackPreferences.subtitleScaleKey) private var subtitleScale = 1.0

    var body: some View {
        let sizes = PlaybackPreferences.subtitleScales
        let index = sizes.firstIndex { $0.scale == subtitleScale } ?? 1
        PanelStepper(
            label: "Size",
            value: sizes[index].name,
            decrement: index > 0 ? { set(sizes[index - 1].scale) } : nil,
            increment: index < sizes.count - 1 ? { set(sizes[index + 1].scale) } : nil
        )
    }

    private func set(_ scale: Double) {
        subtitleScale = scale
        player.setSubtitleScale(scale)
        onInteract()
    }
}

/// `−  Medium  +` in a glass capsule; a nil action disables its end.
private struct PanelStepper: View {
    let label: String
    let value: String
    let decrement: (() -> Void)?
    let increment: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Less", systemImage: "minus") { decrement?() }
                    .disabled(decrement == nil)
                Text(value)
                    .font(.callout.monospacedDigit())
                    .frame(maxWidth: .infinity)
                Button("More", systemImage: "plus") { increment?() }
                    .disabled(increment == nil)
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .accessibilityValue(value)
        }
    }
}
#endif
