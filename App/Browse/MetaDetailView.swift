import MediaCore
import SwiftUI

struct MetaDetailView: View {
    @Environment(TraktAccount.self) private var trakt
    let preview: MetaPreview

    @Environment(AddonStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @State private var state = LoadState.loading
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    /// Set by "Choose Source", which bypasses the remembered source.
    @State private var choosingSource: SourcesRoute?

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
                        EpisodesSection(
                            videos: videos,
                            upNextID: library.upNext(metaID: preview.id, videos: videos)?.video.id,
                            route: route(for:)
                        )
                    }
                case .failed(let message):
                    HStack {
                        Text(message)
                            .foregroundStyle(.secondary)
                        Button("Retry") { state = .loading }
                    }
                    .padding(.horizontal, Metrics.gutter)
                case .loading where preview.type == "series":
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
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
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(item: $choosingSource) { SourcesView(route: $0) }
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

    /// Movies play or resume themselves. Series continue where the viewer left off:
    /// the unfinished episode, else the one after the last finished, else the first.
    private var playRoute: (label: String, route: SourcesRoute)? {
        guard preview.type == "series" else {
            let label = library.resumePosition(for: preview.id) == nil ? "Play" : "Resume"
            return (label, autoplaying(route(for: nil)))
        }
        guard let videos = loaded?.videos else { return nil }
        if let next = library.upNext(metaID: preview.id, videos: videos) {
            let code = EpisodesSection.code(for: next.video)
            return ("\(next.resumeAt == nil ? "Play" : "Resume") \(code)", autoplaying(route(for: next.video)))
        }
        guard let first = EpisodesSection.firstEpisode(in: videos) else { return nil }
        return ("Play \(EpisodesSection.code(for: first))", autoplaying(route(for: first)))
    }

    @ViewBuilder
    private var moreMenu: some View {
        if let play = playRoute {
            Menu {
                Button("Choose Source", systemImage: "list.bullet") {
                    var route = play.route
                    route.autoplay = false
                    choosingSource = route
                }
                if preview.type != "series" {
                    if library.isWatched(preview.id) {
                        Button("Mark as Unwatched", systemImage: "eye.slash") {
                            library.markUnwatched([preview.id])
                            trakt.markUnwatched([play.route.item])
                        }
                    } else {
                        Button("Mark as Watched", systemImage: "checkmark.circle") {
                            library.markWatched([play.route.item])
                            trakt.markWatched([play.route.item])
                        }
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
                    #if !os(tvOS)
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.15), in: .circle)
                    #endif
            }
            #if os(tvOS)
            .labelStyle(.iconOnly)
            #else
            .buttonStyle(.plain)
            #endif
        }
    }

    /// The sources route for the movie itself, or for one of the series' episodes.
    private func route(for video: Video?) -> SourcesRoute {
        let name = loaded?.name ?? preview.name
        let item = WatchItem(
            id: video?.id ?? preview.id,
            type: preview.type,
            metaID: preview.id,
            title: name,
            season: video?.season,
            episode: video?.episode,
            episodeTitle: video?.displayTitle,
            poster: loaded?.poster ?? preview.poster,
            background: loaded?.background ?? preview.background,
            thumbnail: video?.thumbnail
        )
        let title = video.map { "\(name) · \(EpisodesSection.code(for: $0))" } ?? name
        return SourcesRoute(item: item, title: title)
    }

    /// The Play button's route, which goes straight to playback when a source is remembered.
    private func autoplaying(_ route: SourcesRoute) -> SourcesRoute {
        var route = route
        route.autoplay = true
        return route
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
            // Extends under the status bar while the text stays below it; the extra height
            // makes up for the part that moves up there.
            .frame(height: heroHeight + 100)
            .clipped()
            .ignoresSafeArea(edges: .top)
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
            HStack(spacing: 16) {
                if let play = playRoute {
                    PlayButton(label: play.label, route: play.route)
                }
                MyListButton(isSaved: library.isSaved(preview.id)) {
                    library.toggleSaved(preview)
                }
                moreMenu
            }
            .padding(.top, 6)
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
    // A centred stack suits a portrait phone; wider screens read better left-aligned,
    // and a short landscape screen needs a shorter hero.
    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
    private var heroAlignment: HorizontalAlignment { isWide ? .leading : .center }
    private var heroHeight: CGFloat {
        verticalSizeClass == .compact ? 300 : horizontalSizeClass == .regular ? 500 : 460
    }
    private var logoHeight: CGFloat { isWide ? 100 : 80 }
    private var logoWidth: CGFloat { isWide ? 360 : 240 }
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

private struct MyListButton: View {
    let isSaved: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Label("My List", systemImage: isSaved ? "checkmark" : "plus")
                .contentTransition(.symbolEffect(.replace))
                #if !os(tvOS)
                .labelStyle(.iconOnly)
                .font(.headline)
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.15), in: .circle)
                #endif
        }
        #if os(tvOS)
        .buttonStyle(.bordered)
        #else
        .buttonStyle(.plain)
        .accessibilityValue(isSaved ? "Added" : "Not added")
        #endif
    }
}

private struct EpisodesSection: View {
    @Environment(TraktAccount.self) private var trakt
    let videos: [Video]
    let upNextID: String?
    let route: (Video) -> SourcesRoute
    @State private var season: Int
    @Environment(LibraryStore.self) private var library

    init(videos: [Video], upNextID: String?, route: @escaping (Video) -> SourcesRoute) {
        self.videos = videos
        self.upNextID = upNextID
        self.route = route
        // Open on the season being watched, otherwise the first real one rather than specials (season 0).
        let upNextSeason = videos.first { $0.id == upNextID }?.season
        _season = State(initialValue: upNextSeason ?? Self.seasons(in: videos).first ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            HStack(spacing: 12) {
                Picker("Season", selection: $season) {
                    ForEach(Self.seasons(in: videos), id: \.self) { number in
                        Text(number == 0 ? "Specials" : "Season \(number)").tag(number)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Menu {
                    Button("Mark Season as Watched", systemImage: "checkmark.circle") {
                        let items = episodes.filter { $0.isReleased() }.map { route($0).item }
                        library.markWatched(items)
                        trakt.markWatched(items)
                    }
                    Button("Mark Season as Unwatched", systemImage: "eye.slash") {
                        library.markUnwatched(episodes.map(\.id))
                        trakt.markUnwatched(episodes.map { route($0).item })
                    }
                } label: {
                    Label("Season options", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                #if !os(tvOS)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                #endif
            }
            .padding(.horizontal, Metrics.gutter)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                        ForEach(episodes) { video in
                            NavigationLink(value: route(video)) {
                                EpisodeCard(video: video, isUpNext: video.id == upNextID)
                            }
                            #if os(tvOS)
                            // Lifts just the thumbnail on focus, with the text below it, like the TV app.
                            .buttonStyle(.borderless)
                            #else
                            .buttonStyle(.plain)
                            #endif
                            .contextMenu { watchedActions(for: video) }
                            .id(video.id)
                        }
                    }
                }
                // Margins rather than padding, so scrolling to Up Next keeps the inset.
                .contentMargins(.horizontal, Metrics.gutter, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .onAppear {
                    if let upNextID { proxy.scrollTo(upNextID, anchor: .leading) }
                }
            }
        }
    }

    @ViewBuilder
    private func watchedActions(for video: Video) -> some View {
        if library.isWatched(video.id) {
            Button("Mark as Unwatched", systemImage: "eye.slash") {
                library.markUnwatched([video.id])
                trakt.markUnwatched([route(video).item])
            }
        } else {
            Button("Mark as Watched", systemImage: "checkmark.circle") {
                library.markWatched([route(video).item])
                trakt.markWatched([route(video).item])
            }
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
    let isUpNext: Bool
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: video.thumbnail)
                .overlay(alignment: .bottom) {
                    if let progress = library.progress[video.id] {
                        WatchProgressBar(progress: progress)
                    }
                }
                .frame(width: Metrics.episodeWidth, height: Metrics.episodeWidth * 9 / 16)
                .clipShape(.rect(cornerRadius: 8))
                .opacity(video.isReleased() ? 1 : 0.5)
                #if os(tvOS)
                .hoverEffect(.highlight)
                #endif
            HStack(spacing: 6) {
                if isUpNext {
                    Text("Up Next")
                        .foregroundStyle(.primary)
                        .fontWeight(.semibold)
                }
                if let number = video.episode {
                    Text("Episode \(number)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            Text(video.displayTitle ?? "Untitled")
                .font(.subheadline)
                .lineLimit(2)
            if let overview = video.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let date = video.releaseDate {
                // Upcoming episodes say when they air rather than looking playable.
                Text(video.isReleased() ? date.formatted(.dateTime.day().month().year()) : "Airs \(date.formatted(.dateTime.day().month()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Metrics.episodeWidth, alignment: .leading)
    }
}
