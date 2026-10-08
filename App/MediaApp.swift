import MediaCore
import SwiftUI

@main
struct MediaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Phase 1 test screen: proves the addon client and the player work on every
/// platform. Replaced by the real browse UI in phase 3.
struct ContentView: View {
    private static let testVideos: [(name: String, url: URL)] = [
        ("MKV · H.264 1080p", URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mkv/1080/Big_Buck_Bunny_1080_10s_30MB.mkv")!),
        ("MP4 · HEVC 1080p", URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h265/1080/Big_Buck_Bunny_1080_10s_30MB.mp4")!),
        ("HLS · 10 min", URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!),
    ]

    @State private var catalog: Result<[MetaPreview], Error>?
    @State private var path: [URL] = {
        #if DEBUG
        // Opens the player straight away for test runs where no remote or touch input
        // is available: `simctl launch <device> li.tjh.MediaApp -autoplayURL <url>`
        if let string = UserDefaults.standard.string(forKey: "autoplayURL"), let url = URL(string: string) {
            return [url]
        }
        #endif
        return []
    }()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Playback") {
                    ForEach(Self.testVideos, id: \.url) { video in
                        NavigationLink(video.name, value: video.url)
                    }
                }
                Section("Cinemeta · Popular movies") {
                    switch catalog {
                    case nil:
                        ProgressView()
                    case .failure(let error):
                        Text("Couldn't load catalog: \(error.localizedDescription)")
                    case .success(let metas):
                        ForEach(metas.prefix(10)) { meta in
                            LabeledContent(meta.name, value: meta.releaseInfo ?? "")
                        }
                    }
                }
            }
            .navigationTitle("MediaApp")
            .navigationDestination(for: URL.self) { url in
                PlayerView(url: url)
            }
        }
        .task {
            do {
                let client = try AddonClient(manifestURL: "https://v3-cinemeta.strem.io/manifest.json")
                catalog = .success(try await client.catalog(type: "movie", id: "top"))
            } catch {
                catalog = .failure(error)
            }
        }
    }
}
