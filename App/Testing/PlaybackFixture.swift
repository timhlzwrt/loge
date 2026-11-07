#if DEBUG
import LogeCore
import SwiftUI

/// Ordinary playback checks use no WatchItem; progress checks opt into a synthetic episode.
struct PlaybackFixtureView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(LibraryStore.self) private var library
    private var item: WatchItem? {
        ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_PROGRESS_ID"].map {
            WatchItem(id: "\($0):1:1", type: "series", metaID: $0, title: "Progress fixture", season: 1, episode: 1)
        }
    }
    private var url: URL? { ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"].flatMap(URL.init(string:)) }

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 24) {
            Text("Playback verification").font(.title)
            if let url {
                Button("Play fixture") {
                    session.start(PlaybackRequest(title: "Playback fixture", url: url, item: item,
                        startAt: item.flatMap { library.resumePosition(for: $0.id) }))
                }
                if let item {
                    Button("Play remote fixture") {
                        library.mergeRemote(item, fraction: 0.5, estimatedDuration: 2_700, at: .now)
                        session.start(PlaybackRequest(title: "Playback fixture", url: url, item: item,
                            startAt: library.resumePosition(for: item.id)))
                        // Force the ordering where a local update arrives before the real-duration seek.
                        library.record(item, position: 35, duration: 60)
                    }
                    Text("Saved fixture position")
                        .accessibilityIdentifier("fixture-saved-position")
                        .accessibilityValue(String(Int(library.progress[item.id]?.position ?? 0)))
                    Button("Remove fixture progress") { library.removeFromContinueWatching(metaID: item.metaID) }
                }
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
    @Environment(LibraryStore.self) private var library

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
                .accessibilityValue(UserDefaults.standard.string(forKey: PlaybackPreferences.audioKey)
                                    ?? PlaybackPreferences.defaultAudioLanguage)
            Text("Test source")
                .accessibilityIdentifier("fixture-source")
                .accessibilityValue(session.current?.url.query() ?? "original")
            if let item = session.current?.item {
                Text("Saved fixture position")
                    .accessibilityIdentifier("fixture-saved-position")
                    .accessibilityValue(String(Int(library.progress[item.id]?.position ?? 0)))
                Button("Seek fixture to 35 seconds") { player.seek(to: 35) }
            }
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
