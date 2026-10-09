import MediaCore
import SwiftUI

/// A movie or episode whose sources should be listed.
struct SourcesRoute: Hashable {
    let type: String
    let id: String
    let title: String
}

/// Every playable source from the user's stream addons, grouped by addon in their order.
struct SourcesView: View {
    let route: SourcesRoute

    @Environment(AddonStore.self) private var store
    @State private var results: [StreamProvider.ID: Result<[StreamSource], Error>] = [:]
    @State private var playing: PlaybackRequest?
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        let providers = store.addons.streamProviders(type: route.type, id: route.id)
        Group {
            if providers.isEmpty {
                ContentUnavailableView(
                    "No stream addons",
                    systemImage: "play.slash",
                    description: Text("Install an addon that provides streams in Addons.")
                )
            } else {
                list(providers)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .navigationTitle(route.title)
        .task {
            await load(providers)
        }
        #if !os(macOS)
        .fullScreenCover(item: $playing) { PlayerView(request: $0) }
        #endif
    }

    private func list(_ providers: [StreamProvider]) -> some View {
        List {
            ForEach(providers) { provider in
                Section(provider.name) {
                    switch results[provider.id] {
                    case nil:
                        ProgressView()
                    case .failure:
                        Text("Couldn't reach \(provider.name).")
                            .foregroundStyle(.secondary)
                    case .success(let streams):
                        section(for: streams, from: provider)
                    }
                }
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
    }

    @ViewBuilder
    private func section(for streams: [StreamSource], from provider: StreamProvider) -> some View {
        let playable = streams.filter { $0.playbackURL != nil }
        ForEach(Array(playable.enumerated()), id: \.offset) { _, stream in
            Button {
                play(stream)
            } label: {
                StreamRow(stream: stream, fallbackName: provider.name)
            }
            #if !os(tvOS)
            .buttonStyle(.plain)
            #endif
        }
        if playable.isEmpty && streams.isEmpty {
            Text("No sources found.")
                .foregroundStyle(.secondary)
        }
        let unsupported = streams.count - playable.count
        if unsupported > 0 {
            Text("\(unsupported) torrent or external \(unsupported == 1 ? "source isn't" : "sources aren't") supported yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func load(_ providers: [StreamProvider]) async {
        let route = route
        await withTaskGroup(of: (StreamProvider.ID, Result<[StreamSource], Error>).self) { group in
            for provider in providers where results[provider.id] == nil {
                group.addTask {
                    do {
                        return (provider.id, .success(try await provider.streams(type: route.type, id: route.id)))
                    } catch {
                        return (provider.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                results[id] = result
            }
        }
    }

    private func play(_ stream: StreamSource) {
        guard let url = stream.playbackURL else { return }
        let request = PlaybackRequest(title: route.title, url: url, headers: stream.requestHeaders)
        #if os(macOS)
        openWindow(value: request)
        #else
        playing = request
        #endif
    }
}

/// Addons put the quality in `name` ("Debrid\n1080p") and file details in
/// `description` or the older `title`, so they're laid out side by side like Stremio.
private struct StreamRow: View {
    let stream: StreamSource
    let fallbackName: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(stream.cleanName ?? fallbackName)
                .font(.subheadline.weight(.semibold))
                .frame(width: nameWidth, alignment: .leading)
            Text(stream.description ?? stream.title ?? stream.behaviorHints?.filename ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    #if os(tvOS)
    private let nameWidth: CGFloat = 240
    #else
    private let nameWidth: CGFloat = 96
    #endif
}
