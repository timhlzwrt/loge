#if DEBUG
import LogeCore
import SwiftUI

/// A nil WatchItem keeps these tests out of the library, remembered sources and Trakt.
struct PlaybackFixtureView: View {
    @Environment(PlaybackSession.self) private var session
    private var url: URL? { ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"].flatMap(URL.init(string:)) }

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 24) {
            Text("Playback verification").font(.title)
            if let url {
                Button("Play fixture") { session.start(PlaybackRequest(title: "Playback fixture", url: url)) }
            } else {
                Text("Set PLAYBACK_FIXTURE_URL to the local test server.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        #if os(macOS)
        .sheet(isPresented: $session.isScreenPresented) { PlayerView() }
        #else
        .fullScreenCover(isPresented: $session.isScreenPresented) { PlayerView() }
        #endif
        .onChange(of: session.player?.duration) { _, duration in
            guard let duration, let player = session.player else { return }
            player.setCommunitySegments([
                PlaybackSegment(kind: .intro, start: 0, end: 20),
                PlaybackSegment(kind: .recap, start: 20, end: 40),
                PlaybackSegment(kind: .credits, start: 40, end: duration),
            ])
        }
    }
}

struct PlaybackFixtureDiagnostics: View {
    let player: MPVPlayer
    @Environment(PlaybackSession.self) private var session

    var body: some View {
        let selected = player.tracks.first { $0.kind == .audio && $0.isSelected }?.language
        VStack(alignment: .leading, spacing: 6) {
            Text("Test position: \(player.position, specifier: "%.1f")")
                .accessibilityIdentifier("fixture-position").accessibilityValue(String(Int(player.position)))
            Text("Test ended")
                .accessibilityIdentifier("fixture-ended").accessibilityValue(player.status == .ended ? "yes" : "no")
            Text("Test audio: \(selected ?? "unknown")")
                .accessibilityIdentifier("fixture-audio")
                .accessibilityValue(selected.flatMap(LanguageCodes.alpha2(for:)) ?? "unknown")
            Text("Expected audio")
                .accessibilityIdentifier("fixture-expected-audio")
                .accessibilityValue(UserDefaults.standard.string(forKey: PlaybackPreferences.audioKey) ?? PlaybackPreferences.defaultAudioLanguage)
            Text("Test source")
                .accessibilityIdentifier("fixture-source")
                .accessibilityValue(session.current?.url.query() ?? "original")
            Button("Replace fixture source") {
                guard var request = session.current else { return }
                request.url.append(queryItems: [.init(name: "source", value: "second")])
                session.start(request)
            }
        }
        .font(.caption)
        .padding(12)
        .background(.black)
    }
}
#endif
