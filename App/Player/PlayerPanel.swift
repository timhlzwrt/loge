#if os(tvOS)
import SwiftUI
import LogeCore

/// The settings behind the Subtitles, Audio and More buttons on Apple TV, in a glass panel
/// that rises above them, as the menus do from the same buttons on iPhone and Mac.
struct PlayerPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case subtitles = "Subtitles", audio = "Audio", more = "More"
        var id: Self { self }

        var systemImage: String {
            switch self {
            case .subtitles: "captions.bubble"
            case .audio: "waveform"
            case .more: "ellipsis"
            }
        }
    }

    let tab: Tab
    let player: MPVPlayer
    let onInteract: () -> Void
    let onPlaybackInfo: () -> Void

    var body: some View {
        // As wide as what the tab holds, so two short track names don't cover half the picture;
        // a long name gets the full width, cut short if it needs more.
        ViewThatFits(in: .horizontal) {
            panel.fixedSize(horizontal: true, vertical: false)
            panel
        }
        .frame(maxWidth: 1000, alignment: .trailing)
    }

    private var panel: some View {
        Group {
            switch tab {
            case .subtitles: subtitles
            case .audio: audio
            case .more: more
            }
        }
        // Only as tall as what the tab holds; two tracks needn't cover the picture.
        .fixedSize(horizontal: false, vertical: true)
        .padding(36)
        // Up from the buttons lands here even with nothing straight above the focused one.
        .focusSection()
        .buttonStyle(PlayerButtonStyle())
        .glassEffect(.player, in: .rect(cornerRadius: 36))
    }

    private var more: some View {
        VStack(alignment: .leading, spacing: 24) {
            PanelStepper(label: "Speed", value: PlaybackSpeed.name(player.speed),
                         decrement: step(speedBy: -1), increment: step(speedBy: 1))
            Button(player.isZoomedToFill ? "Fit to Screen" : "Zoom to Fill") {
                player.setZoomToFill(!player.isZoomedToFill)
                onInteract()
            }
            Button("Playback Info", action: onPlaybackInfo)
        }
    }

    private var subtitles: some View {
        HStack(alignment: .top, spacing: 48) {
            TrackList(player: player, kind: .sub, onInteract: onInteract)
            VStack(alignment: .leading, spacing: 24) {
                SubtitleSizeStepper(player: player, onInteract: onInteract)
                delayStepper(.sub)
            }
        }
    }

    private var audio: some View {
        HStack(alignment: .top, spacing: 48) {
            TrackList(player: player, kind: .audio, onInteract: onInteract)
            delayStepper(.audio)
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
    @FocusState private var focusedRow: String?

    var body: some View {
        let tracks = player.distinctTracks(kind)
        let selection = player.selection(for: kind)
        let selectedRow = selection.wrappedValue.map { "\($0)" } ?? (kind == .sub ? "off" : nil)
        // Wider than the steppers' 8: a focused row's platter reaches above its text, over the label.
        VStack(alignment: .leading, spacing: 22) {
            Text("Language")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Sound can't be turned off, only subtitles.
                    if kind == .sub {
                        row("Off", id: "off", isSelected: selection.wrappedValue == nil) { selection.wrappedValue = nil }
                    }
                    ForEach(tracks) { track in
                        row(track.displayName, id: "\(track.id)", isSelected: track.isSelected) {
                            selection.wrappedValue = track.id
                        }
                    }
                }
            }
            // Room for the focused row's lift and shadow inside the clip, which a long list needs:
            // unclipped, its rows spread over the label and the timeline.
            .contentMargins(.vertical, 16, for: .scrollContent)
            .contentMargins(.horizontal, 10, for: .scrollContent)
            .frame(maxHeight: 452)
            .padding(.vertical, -16)
            .padding(.horizontal, -10)
        }
        .onChange(of: focusedRow) { old, new in
            // Coming in from the buttons, start on the track in use rather than the nearest row.
            guard old == nil, let new, let selectedRow, new != selectedRow else { return }
            focusedRow = selectedRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ name: String, id: String, isSelected: Bool, select: @escaping () -> Void) -> some View {
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
        .focused($focusedRow, equals: id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SubtitleSizeStepper: View {
    let player: MPVPlayer
    let onInteract: () -> Void
    @AppStorage(SyncedSettings.Key.subtitleScale) private var subtitleScale = SyncedSettings().subtitleScale

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

/// `−  Medium  +`; a nil action disables its end.
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
                // Room for the longest value, so the buttons stay put as it changes.
                Text(value)
                    .font(.callout.monospacedDigit())
                    .frame(width: 140)
                Button("More", systemImage: "plus") { increment?() }
                    .disabled(increment == nil)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(PlayerButtonStyle(width: 66))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .accessibilityValue(value)
        }
    }
}
#endif
