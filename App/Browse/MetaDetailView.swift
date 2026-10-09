import MediaCore
import SwiftUI

struct MetaDetailView: View {
    let preview: MetaPreview

    @Environment(AddonStore.self) private var store
    @State private var state = LoadState.loading

    private enum LoadState {
        case loading
        case loaded(Meta)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                switch state {
                case .loaded(let meta):
                    if let videos = meta.videos, !videos.isEmpty, meta.type == "series" {
                        EpisodesSection(showName: meta.name, videos: videos)
                    }
                case .failed(let message):
                    HStack {
                        Text(message)
                            .foregroundStyle(.secondary)
                        Button("Retry") { state = .loading }
                    }
                    .padding(.horizontal, Metrics.gutter)
                case .loading:
                    EmptyView()
                }
            }
            .padding(.bottom, 40)
        }
        .scrollClipDisabled()
        .background(alignment: .top) {
            backdrop
        }
        .background(Color.canvas)
        #if os(iOS)
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .task(id: isLoading) {
            guard isLoading else { return }
            guard let client = store.addons.metaClient(type: preview.type, id: preview.id) else {
                state = .failed("None of your addons provides details for this title.")
                return
            }
            do {
                state = .loaded(try await client.meta(type: preview.type, id: preview.id))
            } catch is CancellationError {
                // Navigated away; nothing to show.
            } catch {
                state = .failed("Couldn't load the details for \(preview.name).")
            }
        }
    }

    private var isLoading: Bool {
        if case .loading = state { true } else { false }
    }

    /// Full details once loaded; until then the catalog entry already has enough to draw the page.
    private var loaded: Meta? {
        if case .loaded(let meta) = state { meta } else { nil }
    }

    /// Movies play themselves; series start at their first episode until
    /// watch progress exists to resume from.
    private var playRoute: (label: String, route: SourcesRoute)? {
        guard preview.type == "series" else {
            return ("Play", SourcesRoute(type: preview.type, id: preview.id, title: preview.name))
        }
        guard let first = loaded?.videos.flatMap(EpisodesSection.firstEpisode) else { return nil }
        let code = EpisodesSection.code(for: first)
        return ("Play \(code)", SourcesRoute(type: preview.type, id: first.id, title: "\(preview.name) · \(code)"))
    }

    private var backdrop: some View {
        Artwork(url: loaded?.background ?? preview.background)
            .overlay { BackdropFade() }
            #if os(tvOS)
            .overlay {
                LinearGradient(colors: [.canvas, .canvas.opacity(0)], startPoint: .leading, endPoint: .center)
            }
            .ignoresSafeArea()
            #else
            .frame(height: 560)
            .clipped()
            #endif
            .accessibilityHidden(true)
    }

    private var hero: some View {
        VStack(alignment: heroAlignment, spacing: 14) {
            TitleLogo(logo: loaded?.logo ?? preview.logo, name: preview.name, maxHeight: logoHeight)
                .frame(maxWidth: logoWidth, alignment: Alignment(horizontal: heroAlignment, vertical: .center))
            (loaded?.infoLine ?? preview.infoLine)
            if let description = loaded?.description ?? preview.description {
                ExpandableText(text: description)
                    .frame(maxWidth: 900, alignment: .leading)
            }
            if let cast = loaded?.cast, !cast.isEmpty {
                Text("Starring \(cast.prefix(4).formatted(.list(type: .and)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 900, alignment: .leading)
            }
            if let play = playRoute {
                PlayButton(label: play.label, route: play.route)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: heroAlignment, vertical: .bottom))
        .frame(minHeight: heroHeight, alignment: .bottom)
        .padding(.horizontal, Metrics.gutter)
    }

    #if os(tvOS)
    private let heroAlignment = HorizontalAlignment.leading
    private let heroHeight: CGFloat = 640
    private let logoHeight: CGFloat = 160
    private let logoWidth: CGFloat = 560
    #elseif os(macOS)
    private let heroAlignment = HorizontalAlignment.leading
    private let heroHeight: CGFloat = 420
    private let logoHeight: CGFloat = 110
    private let logoWidth: CGFloat = 360
    #else
    private let heroAlignment = HorizontalAlignment.center
    private let heroHeight: CGFloat = 520
    private let logoHeight: CGFloat = 80
    private let logoWidth: CGFloat = 240
    #endif
}

/// A description clamped to a few lines, with a "more" control when it overflows.
private struct ExpandableText: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        #if os(tvOS)
        // A focusable "More" would take initial focus from Play, which matters more on a TV.
        Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(4)
        #else
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(isExpanded ? nil : 3)
            if !isExpanded {
                Button("More") { isExpanded = true }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        #endif
    }
}

private struct PlayButton: View {
    let label: String
    let route: SourcesRoute

    var body: some View {
        NavigationLink(value: route) {
            Label(label, systemImage: "play.fill")
                .font(.headline)
                #if !os(tvOS)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(.white, in: .capsule)
                .foregroundStyle(.black)
                #endif
        }
        #if os(tvOS)
        // The system style supplies the focus highlight a custom background would lose.
        .buttonStyle(.bordered)
        #else
        .buttonStyle(.plain)
        #endif
    }
}

private struct EpisodesSection: View {
    let showName: String
    let videos: [Video]
    @State private var season: Int

    init(showName: String, videos: [Video]) {
        self.showName = showName
        self.videos = videos
        // Start on the first real season rather than specials (season 0).
        _season = State(initialValue: Self.seasons(in: videos).first ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            Picker("Season", selection: $season) {
                ForEach(Self.seasons(in: videos), id: \.self) { number in
                    Text(number == 0 ? "Specials" : "Season \(number)").tag(number)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .padding(.horizontal, Metrics.gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                    ForEach(episodes) { video in
                        NavigationLink(value: SourcesRoute(
                            type: "series",
                            id: video.id,
                            title: "\(showName) · \(Self.code(for: video))"
                        )) {
                            EpisodeCard(video: video)
                        }
                        #if os(tvOS)
                        // Lifts just the thumbnail on focus, with the text below it, like the TV app.
                        .buttonStyle(.borderless)
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private var episodes: [Video] {
        videos.filter { $0.season == season }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    /// "S1 E2", or just the season or title when an addon omits numbering.
    static func code(for video: Video) -> String {
        switch (video.season, video.episode) {
        case let (season?, episode?): "S\(season) E\(episode)"
        case let (season?, nil): "S\(season)"
        default: video.displayTitle ?? "Episode"
        }
    }

    static func firstEpisode(in videos: [Video]) -> Video? {
        guard let season = seasons(in: videos).first else { return videos.first }
        return videos.filter { $0.season == season }.min { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    /// Numbered seasons in order, with specials last.
    private static func seasons(in videos: [Video]) -> [Int] {
        Set(videos.compactMap(\.season)).sorted { lhs, rhs in
            lhs == 0 ? false : rhs == 0 ? true : lhs < rhs
        }
    }
}

private struct EpisodeCard: View {
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: video.thumbnail)
                .frame(width: Metrics.episodeWidth, height: Metrics.episodeWidth * 9 / 16)
                .clipShape(.rect(cornerRadius: 8))
                #if os(tvOS)
                .hoverEffect(.highlight)
                #endif
            if let number = video.episode {
                Text("Episode \(number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(video.displayTitle ?? "Untitled")
                .font(.subheadline)
                .lineLimit(2)
            if let date = releaseDate {
                Text(date, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Metrics.episodeWidth, alignment: .leading)
    }

    /// Addons send ISO 8601 dates both with and without fractional seconds.
    private var releaseDate: Date? {
        guard let released = video.released else { return nil }
        return (try? Date(released, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(released, strategy: .iso8601))
    }
}
