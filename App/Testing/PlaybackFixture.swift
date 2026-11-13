#if DEBUG
import LogeCore
import SwiftUI

/// Ordinary playback checks use no WatchItem; progress checks opt into a synthetic episode.
struct PlaybackFixtureView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(LibraryStore.self) private var library
    private var item: WatchItem? {
        if ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_MOVIE"] != nil {
            return WatchItem(id: "fixture-movie", type: "movie", metaID: "fixture-movie", title: "Movie fixture")
        }
        return ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_PROGRESS_ID"].map {
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
                        startAt: item.flatMap { library.resumePosition(for: $0.id) },
                        subtitles: [Subtitle(url: url.deletingLastPathComponent().appending(path: "subs/stream-en.srt").absoluteString, lang: "eng")]))
                }
                if let item {
                    Button("Play remote fixture") {
                        // Halfway through on another device, whose file ran 45 minutes.
                        var snapshot = library.playbackSyncSnapshot
                        // Left by "Remove fixture progress"; a snapshot can't hold both.
                        snapshot.removals[item.id] = nil
                        snapshot.entries[item.id] = WatchProgress(item: item, position: 1_350, duration: 2_700, updatedAt: .now)
                        do {
                            try library.applyPlaybackSyncSnapshot(snapshot)
                        } catch {
                            assertionFailure("Couldn't save the remote fixture's progress: \(error)")
                        }
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
            if let mode = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_NEXT"], mode != "late" {
                offerNext()
            }
        }
        // "late": the lookup lands only after the end, once the end card shows.
        .onChange(of: session.player?.status == .ended) { _, ended in
            guard ended, ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_NEXT"] == "late" else { return }
            Task {
                try? await Task.sleep(for: .seconds(3))
                offerNext()
            }
        }
    }
}

extension PlaybackFixtureView {
    private func offerNext() {
        guard var next = session.current, next.url.query() == nil else { return }
        next.title = "Next fixture"
        next.url.append(queryItems: [.init(name: "source", value: "next")])
        session.offerNextForTesting(next)
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
            Text("Test subtitle")
                .accessibilityIdentifier("fixture-subtitle")
                .accessibilityValue(player.tracks.first { $0.kind == .sub && $0.isSelected }?.language ?? "off")
            Text("Test A/V offset")
                .accessibilityIdentifier("fixture-av-sync")
                .accessibilityValue(player.playbackInfo.avSync.map { String(abs($0)) } ?? "unknown")
            Text("Test source")
                .accessibilityIdentifier("fixture-source")
                .accessibilityValue(session.current?.url.query() ?? "original")
            if let item = session.current?.item {
                Text("Saved fixture position")
                    .accessibilityIdentifier("fixture-saved-position")
                    .accessibilityValue(String(Int(library.progress[item.id]?.position ?? 0)))
                #if !os(tvOS)
                Button("Seek fixture to 35 seconds") { player.seek(to: 35) }
                #endif
            }
            // On tvOS these would take focus from the player being checked.
            #if !os(tvOS)
            Button("Replace fixture source") {
                guard var request = session.current else { return }
                request.url.append(queryItems: [.init(name: "source", value: "second")])
                session.start(request)
            }
            if let shorter = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_SHORT_URL"].flatMap(URL.init(string:)) {
                Button("Replace with shorter source") {
                    guard var request = session.current else { return }
                    request.url = shorter
                    session.start(request)
                }
            }
            #endif
        }
        .font(.caption)
        .padding(12)
        .background(.black)
        .task {
            while !Task.isCancelled {
                player.refreshPlaybackInfo()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
#endif
