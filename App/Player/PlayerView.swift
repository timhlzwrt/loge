import SwiftUI

/// Full-screen playback for one URL. Controls are deliberately minimal until phase 4.
struct PlayerView: View {
    let url: URL

    // Created on appear rather than as a `@State` default, because SwiftUI evaluates
    // default values every time the view is re-initialised and each player
    // starts its own mpv instance.
    @State private var player: MPVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                MPVVideoView(player: player).ignoresSafeArea()
                PlayerControls(player: player)
            }
        }
        .onAppear {
            let player = MPVPlayer()
            player.load(url)
            self.player = player
        }
        .onDisappear {
            player?.shutDown()
            player = nil
        }
        #if os(tvOS)
        .onPlayPauseCommand { player?.togglePause() }
        .onMoveCommand { direction in
            switch direction {
            case .left: player?.seek(by: -10)
            case .right: player?.seek(by: 10)
            default: break
            }
        }
        #endif
    }
}

private struct PlayerControls: View {
    let player: MPVPlayer

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 24) {
                #if !os(tvOS)
                // The Siri Remote drives these on tvOS.
                Button("Back 10 seconds", systemImage: "gobackward.10") { player.seek(by: -10) }
                Button(player.status == .paused ? "Play" : "Pause",
                       systemImage: player.status == .paused ? "play.fill" : "pause.fill") {
                    player.togglePause()
                }
                Button("Forward 10 seconds", systemImage: "goforward.10") { player.seek(by: 10) }
                #endif
                Text(statusText)
                    .monospacedDigit()
            }
            .labelStyle(.iconOnly)
            .padding()
            .background(.black.opacity(0.6), in: .rect(cornerRadius: 8))
            .foregroundStyle(.white)
            .padding()
        }
    }

    private var statusText: String {
        switch player.status {
        case .idle, .loading: "Loading…"
        case .buffering: "Buffering… \(timeText)"
        case .failed(let message): "Couldn't play: \(message)"
        case .ended: "Ended"
        case .playing, .paused: timeText
        }
    }

    private var timeText: String {
        let position = Duration.seconds(player.position).formatted(.time(pattern: .minuteSecond))
        guard let duration = player.duration else { return position }
        return "\(position) / \(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))"
    }
}
