import MediaCore
import SwiftUI

/// A movie or episode whose sources should be listed.
struct SourcesRoute: Hashable {
    let item: WatchItem
    /// "Lanterns · S1 E2", shown as the screen and player title.
    let title: String
    /// Start playing straight away with the source last used for this title, if there is
    /// one, rather than waiting for a choice. The list stays underneath as a fallback.
    var autoplay = false

    var type: String { item.type }
    var id: String { item.id }
}

/// Every playable source from the user's stream addons, grouped by addon in their order
/// or as one list with the best quality first.
struct SourcesView: View {
    let route: SourcesRoute

    enum Order: String {
        case addons, quality
    }

    @Environment(AddonStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var results: [StreamProvider.ID: Result<[StreamSource], Error>] = [:]
    @State private var hasAutoplayed = false
    @State private var playedAutomatically = false
    @Environment(PlaybackSession.self) private var playback
    @AppStorage("sourcesOrder") private var order = Order.addons

    var body: some View {
        let providers = store.addons.streamProviders(type: route.type, id: route.id)
        Group {
            if providers.isEmpty {
                ContentUnavailableView(
                    "No stream addons",
                    systemImage: "play.slash",
                    description: Text("Install an addon that provides streams in Settings.")
                )
            } else {
                list(providers)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .navigationTitle(route.title)
        .task {
            playRememberedSourceIfPossible()
            await load(providers)
            if playedAutomatically, let current = playback.current, current.item?.id == route.id {
                playback.offerFallbacks(fallbacks(for: current), for: current)
            }
            playContinuingSourceIfPossible()
            // Either way the attempt is over; without a match the list is the way forward.
            hasAutoplayed = true
        }
        .onChange(of: playback.current == nil) { _, ended in
            // Playback started straight from Play or Continue Watching passed through
            // this list; ending it goes back to where that tap came from.
            if ended && route.autoplay && playedAutomatically { dismiss() }
        }
    }

    private func list(_ providers: [StreamProvider]) -> some View {
        List {
            if route.autoplay && !hasAutoplayed && library.sources[route.item.metaID] != nil {
                Label("Starting with your last source…", systemImage: "play.circle")
                    .foregroundStyle(.secondary)
            }
            Picker("Order", selection: $order) {
                Text("Addon Order").tag(Order.addons)
                Text("Best Quality").tag(Order.quality)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            switch order {
            case .addons:
                ForEach(providers) { provider in
                    Section(provider.name) {
                        switch results[provider.id] {
                        case nil:
                            ProgressView()
                        case .failure:
                            unreachable(provider)
                        case .success(let streams):
                            section(for: streams, from: provider)
                        }
                    }
                }
            case .quality:
                bestFirst(providers)
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
            row(stream, from: provider, showsProvider: false)
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

    /// Every addon's sources in one list, best first; ties keep the user's addon order.
    @ViewBuilder
    private func bestFirst(_ providers: [StreamProvider]) -> some View {
        let ranked = providers.enumerated()
            .flatMap { index, provider -> [(Int, StreamProvider, StreamSource, StreamDetails)] in
                guard case .success(let streams) = results[provider.id] else { return [] }
                return streams.filter { $0.playbackURL != nil }.map { (index, provider, $0, StreamDetails($0)) }
            }
            .enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (lhs.element.3, rhs.element.3)
                if StreamDetails.bestFirst(a, b) { return true }
                if StreamDetails.bestFirst(b, a) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        Section {
            ForEach(Array(ranked.enumerated()), id: \.offset) { _, entry in
                row(entry.2, from: entry.1, showsProvider: providers.count > 1)
            }
            if providers.contains(where: { results[$0.id] == nil }) {
                ProgressView()
            }
            ForEach(providers.filter { if case .failure = results[$0.id] { true } else { false } }) { provider in
                unreachable(provider)
            }
            if ranked.isEmpty && providers.allSatisfy({ results[$0.id] != nil }) {
                Text("No sources found.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func unreachable(_ provider: StreamProvider) -> some View {
        HStack {
            Text("Couldn't reach \(provider.name).")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry") {
                results[provider.id] = nil
                Task { await load([provider]) }
            }
        }
    }

    private func row(_ stream: StreamSource, from provider: StreamProvider, showsProvider: Bool) -> some View {
        Button {
            play(stream, from: provider)
        } label: {
            StreamRow(stream: stream, providerName: provider.name, showsProvider: showsProvider)
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
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

    /// Resuming the item last played: its stream URL is already known.
    private func playRememberedSourceIfPossible() {
        guard route.autoplay, !hasAutoplayed, let remembered = library.sources[route.item.metaID],
              remembered.itemID == route.id
        else { return }
        hasAutoplayed = true
        playedAutomatically = true
        playback.start(PlaybackRequest(
            title: route.title, url: remembered.url, headers: remembered.headers, item: route.item,
            startAt: library.resumePosition(for: route.id),
            providerURL: remembered.providerURL, bingeGroup: remembered.bingeGroup
        ))
    }

    /// Another episode of a series: the same addon's stream in the same binge group.
    private func playContinuingSourceIfPossible() {
        guard route.autoplay, !hasAutoplayed, let remembered = library.sources[route.item.metaID],
              case .success(let streams) = results[remembered.providerURL],
              let stream = StreamSource.continuing(bingeGroup: remembered.bingeGroup, in: streams),
              let provider = store.addons.streamProviders(type: route.type, id: route.id)
                .first(where: { $0.id == remembered.providerURL })
        else { return }
        hasAutoplayed = true
        playedAutomatically = true
        play(stream, from: provider)
    }

    private func play(_ stream: StreamSource, from provider: StreamProvider) {
        guard let request = request(for: stream, from: provider) else { return }
        playback.start(request, fallbacks: fallbacks(for: request))
    }

    private func request(for stream: StreamSource, from provider: StreamProvider) -> PlaybackRequest? {
        guard let url = stream.playbackURL else { return nil }
        return PlaybackRequest(
            title: route.title,
            url: url,
            headers: stream.requestHeaders,
            item: route.item,
            startAt: library.resumePosition(for: route.id),
            providerURL: provider.manifestURL,
            bingeGroup: stream.behaviorHints?.bingeGroup,
            subtitles: stream.subtitles ?? [],
            filename: stream.behaviorHints?.filename
        )
    }

    /// What to try if `request` doesn't open: the same release and quality first, then
    /// the rest in the user's addon order. Only a few, so a dead account doesn't spend
    /// minutes working through every link.
    private func fallbacks(for request: PlaybackRequest) -> [PlaybackRequest] {
        let all = store.addons.streamProviders(type: route.type, id: route.id).flatMap { provider in
            guard case .success(let streams) = results[provider.id] else { return [PlaybackRequest]() }
            return streams.compactMap { self.request(for: $0, from: provider) }
        }
        let others = all.filter { $0.url != request.url }
        let sameGroup = others.filter { request.bingeGroup != nil && $0.bingeGroup == request.bingeGroup }
        let rest = others.filter { request.bingeGroup == nil || $0.bingeGroup != request.bingeGroup }
        return Array((sameGroup + rest).prefix(3))
    }
}

/// One source: what the picture will look like first, then the file, then the addon's own
/// text, which can mention things the tags don't, such as languages or the release group.
private struct StreamRow: View {
    let stream: StreamSource
    let providerName: String
    /// In the best-first list, rows from several addons sit together.
    let showsProvider: Bool

    var body: some View {
        let details = StreamDetails(stream)
        let fileLine = [details.file, details.isCached == false ? "Not cached" : nil, showsProvider ? providerName : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
        VStack(alignment: .leading, spacing: 3) {
            // Without recognisable tags, the addon's name line is the best summary.
            Text(details.picture ?? stream.cleanName?.components(separatedBy: .newlines).joined(separator: " ") ?? providerName)
                .font(.subheadline.weight(.semibold))
            if !fileLine.isEmpty {
                Text(fileLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let text = stream.description ?? stream.title ?? stream.behaviorHints?.filename {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
