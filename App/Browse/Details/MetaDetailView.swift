import LogeCore
import SwiftUI

struct MetaDetailView: View {
    @Environment(TraktAccount.self) private var trakt
    let preview: MetaPreview

    @Environment(AddonStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(TMDBAccount.self) private var tmdb
    @State private var state = LoadState.loading
    @State private var tmdbState = TMDBLoadState.disconnected
    @State private var loadAttempt = 0
    @State private var tmdbAttempt = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The page's own shape rather than the screen's: window resizing narrows it.
    @State private var hasRoomForColumns = false
    #endif
    /// Set by "Choose a Source" and by picking an episode, which bypass the remembered source.
    @State private var choosingSource: SourcesRoute?
    @State private var heroScroll = HeroScroll()

    private enum LoadState {
        case loading
        case loaded(Meta)
        case failed(String)
    }

    private enum TMDBLoadState {
        case disconnected, loading, loaded(TMDBDetails), failed(String)
    }

    private struct TMDBLoadKey: Hashable {
        let revision: Int
        let attempt: Int
    }

    var body: some View {
        ScrollView {
            pageLayout {
                hero
                if let meta = loaded {
                    if preview.type == MediaType.series, case .loading = state {
                        ProgressView("Loading episodes…")
                            .frame(maxWidth: .infinity)
                    }
                    if let videos = meta.videos, !videos.isEmpty, meta.type == MediaType.series {
                        EpisodesSection(
                            videos: videos,
                            upNextID: library.upNext(metaID: preview.id, videos: videos)?.video.id,
                            route: route(for:),
                            choose: { choosingSource = route(for: $0) },
                            staysInColumn: usesColumns
                        )
                    }
                    if case .failed = state {
                        HStack {
                            Text(preview.type == MediaType.series
                                 ? "Addon details are unavailable. Episodes could not be loaded."
                                 : "Addon details are unavailable.")
                                .foregroundStyle(.secondary)
                            Button("Retry", action: retry)
                        }
                        .padding(.horizontal, Metrics.gutter)
                    }
                    let people = creditedPeople(fallback: meta.people)
                    if !people.isEmpty {
                        PeopleRow(people: people, title: preview, staysInColumn: usesColumns)
                            .detailColumn(.side)
                    }
                    MoreLikeThisRow(titles: tmdbDetails?.recommendations ?? [])
                        .detailColumn(.full)
                    ReviewsSection(preview: preview)
                    InformationSection(meta: meta, details: tmdbDetails)
                        .detailColumn(.side)
                } else if case .failed(let message) = state {
                    HStack {
                        Text(message)
                            .foregroundStyle(.secondary)
                        Button("Retry", action: retry)
                    }
                    .padding(.horizontal, Metrics.gutter)
                } else {
                    detailsPlaceholder
                }
                tmdbStatus
                    .detailColumn(.full)
            }
            .padding(.bottom, 40)
        }
        .scrollClipDisabled()
        #if os(iOS)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width >= 880 && proxy.size.width > proxy.size.height
        } action: { hasRoomForColumns = $0 && !Metrics.isPhone }
        #endif
        // The backdrop stays put behind the page, so it fades as the hero scrolls away
        // instead of showing behind episodes and cast.
        .onScrollGeometryChange(for: Double.self) { geometry in
            min(max((geometry.contentOffset.y + geometry.contentInsets.top) / heroHeight, 0), 1)
        } action: { _, progress in
            heroScroll.progress = progress
        }
        .background(alignment: .top) {
            HeroScroll.Fading(scroll: heroScroll) { backdrop }
        }
        .background(Color.canvas)
        .hidingPhoneTabBar()
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #elseif os(macOS)
        // Otherwise the window title falls back to the app's name.
        .navigationTitle(preview.name)
        // The backdrop runs up under the toolbar, which keeps only the back button.
        .ignoresSafeArea(edges: .top)
        #endif
        #if os(tvOS)
        .fullScreenCover(item: $choosingSource) { SourcesView(route: $0, isChoosing: true) }
        #else
        .sheet(item: $choosingSource) { SourcesView(route: $0, isChoosing: true) }
        #endif
        .task(id: loadAttempt) {
            guard let client = store.addons.metaClient(type: preview.type, id: preview.id) else {
                state = .failed("None of your addons provides details for this title.")
                return
            }
            do {
                let meta = try await client.meta(type: preview.type, id: preview.id)
                try Task.checkCancellation()
                state = .loaded(meta)
                // Entries saved before this title's artwork was known get it now.
                library.fillArtwork(from: meta)
            } catch is CancellationError {
                // Navigated away; nothing to show.
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed("Couldn't load the details for \(preview.name).")
            }
        }
        .task(id: TMDBLoadKey(revision: tmdb.revision, attempt: tmdbAttempt)) {
            guard tmdb.isConfigured, isOnTMDB else {
                tmdbState = .disconnected
                return
            }
            tmdbState = .loading
            do {
                let details = try await tmdb.details(imdbID: preview.id, type: preview.type)
                try Task.checkCancellation()
                tmdbState = .loaded(details)
            } catch {
                guard !Task.isCancelled else { return }
                let message = switch error as? TMDBError {
                case .unauthorized: "TMDB didn't accept the saved token. Check TMDB in Settings."
                case .rateLimited: "TMDB is busy. Try again in a few minutes."
                case .notFound: "This title wasn't found on TMDB."
                default: "Couldn't load TMDB details."
                }
                tmdbState = .failed(message)
            }
        }
        .task(id: "\(tmdb.revision):\(tmdbDetails?.people.map { String($0.id) }.joined(separator: ",") ?? "")") {
            guard let details = tmdbDetails else { return }
            let ids = [details.people.first?.id, details.people.first { $0.roles.contains(.director) }?.id]
            var warmed = Set<Int>()
            for id in ids.compactMap({ $0 }) where warmed.insert(id).inserted {
                guard !Task.isCancelled else { return }
                // Speculative work: the person page presents errors and retries if this fails.
                _ = try? await tmdb.personDetails(id: id)
            }
        }
        // Stream addons such as AIOStreams take seconds to answer, so ask while the page is
        // being read; the sources screen picks up the same request.
        .task(id: playAction?.route.id) {
            guard let route = playAction?.route else { return }
            for provider in store.addons.streamProviders(type: route.type, id: route.id) {
                provider.prefetchStreams(type: route.type, id: route.id)
            }
        }
    }

    private var usesColumns: Bool {
        #if os(iOS)
        hasRoomForColumns
        #else
        false
        #endif
    }

    private var pageLayout: AnyLayout {
        let spacing: CGFloat = 28
        return usesColumns
            ? AnyLayout(DetailColumnsLayout(sideTop: heroHeight - 160, spacing: spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
    }

    private func retry() {
        state = .loading
        loadAttempt += 1
        tmdbAttempt += 1
    }

    /// Full details once loaded; until then the catalog entry already has enough to draw the page.
    private var loaded: Meta? {
        let base: Meta? = if case .loaded(let meta) = state { meta } else { nil }
        if case .loaded(let details) = tmdbState {
            return base.map { details.applying(to: $0) } ?? details.meta(for: preview)
        }
        return base
    }

    private var tmdbDetails: TMDBDetails? {
        if case .loaded(let details) = tmdbState { details } else { nil }
    }

    /// TMDB is asked by IMDb ID, for films and series only.
    private var isOnTMDB: Bool {
        preview.id.wholeMatch(of: /tt\d+/) != nil
            && (preview.type == MediaType.movie || preview.type == MediaType.series)
    }

    private var detailsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgressView("Loading details…")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Cast & Crew").font(.sectionTitle)
            HStack(alignment: .top, spacing: Metrics.rowSpacing) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(spacing: 12) {
                        Circle().fill(.white.opacity(0.06))
                            .frame(width: Metrics.personSize, height: Metrics.personSize)
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.06))
                            .frame(width: Metrics.personSize, height: 12)
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Metrics.gutter)
        .clipped()
    }

    private func creditedPeople(fallback: [Person]) -> [Person] {
        if case .loaded(let details) = tmdbState, !details.people.isEmpty { return details.creditedPeople }
        return fallback
    }

    @ViewBuilder
    private var tmdbStatus: some View {
        Group {
            switch tmdbState {
            case .failed(let message):
                HStack {
                    Text(message + (loaded == nil ? "" : " Showing available addon details."))
                    Button("Retry TMDB") { tmdbAttempt += 1 }
                }
            case .loading:
                Text("Loading TMDB details…")
            case .disconnected:
                if !tmdb.isConfigured, isOnTMDB, loaded != nil {
                    Text("Connect TMDB in Settings for cast photos, reviews and recommendations.")
                }
            case .loaded:
                EmptyView()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.gutter)
    }

    /// What My List and the user's lists keep: the catalog entry, with artwork it lacked
    /// filled in from the full details, so the title has a poster wherever it's listed.
    private var savedPreview: MetaPreview {
        loaded.map(preview.fillingArtwork(from:)) ?? preview
    }

    private var playAction: PlayAction? {
        PlayAction(preview: preview, meta: loaded, library: library)
    }

    private func route(for video: Video?) -> SourcesRoute {
        PlayAction.route(for: video, preview: preview, meta: loaded)
    }

    private var backdrop: some View {
        Artwork(url: loaded?.background ?? preview.background)
            .overlay { BackdropFade() }
            #if !os(iOS)
            .overlay {
                LinearGradient(colors: [.canvas.opacity(0.8), .canvas.opacity(0)], startPoint: .leading, endPoint: .center)
            }
            #endif
            #if os(tvOS)
            .ignoresSafeArea()
            #else
            // Extends under the status bar while the text stays below it; the extra height
            // makes up for the part that moves up there.
            .frame(height: heroHeight + 100)
            .clipped()
            #if os(macOS)
            .backgroundExtensionEffect()
            #endif
            .ignoresSafeArea(edges: .top)
            #endif
            .accessibilityHidden(true)
    }

    private var description: String? {
        loaded?.description ?? preview.description
    }

    private var hero: some View {
        VStack(alignment: heroAlignment, spacing: 12) {
            TitleLogo(logo: loaded?.logo ?? preview.logo, name: preview.name, maxHeight: logoHeight)
                .frame(maxWidth: logoWidth, alignment: Alignment(horizontal: heroAlignment, vertical: .center))
            (loaded?.infoLine ?? preview.infoLine)
                .multilineTextAlignment(heroAlignment == .center ? .center : .leading)
            if !synopsisUnderButtons, let description {
                Text(description)
                    .font(.synopsis)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(synopsisLines)
                    .frame(maxWidth: synopsisWidth, alignment: .leading)
            }
            buttons
                .padding(.top, 6)
            if synopsisUnderButtons, let description {
                ExpandableText(text: description)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: heroAlignment, vertical: .bottom))
        .frame(minHeight: heroHeight, alignment: .bottom)
        .padding(.horizontal, Metrics.gutter)
    }

    /// On a phone Play takes the full width and the other actions sit in a row beneath it;
    /// wider screens keep them on one line.
    @ViewBuilder
    private var buttons: some View {
        if synopsisUnderButtons {
            VStack(spacing: 20) {
                playButton
                // Icons differ in height, which large text makes visible; the captions stay level.
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    secondaryButtons(isBare: true)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                playButton
                // No merging distance: the circles stay apart, as separate buttons.
                GlassEffectContainer(spacing: 0) {
                    HStack(alignment: .top, spacing: 16) { secondaryButtons(isBare: false) }
                }
            }
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if let play = playAction {
            NavigationLink(value: play.route) {
                Label(play.label, systemImage: "play.fill")
                    .frame(maxWidth: synopsisUnderButtons ? .infinity : nil)
            }
            .buttonStyle(PrimaryButtonStyle())
            .contextMenu { watchedActions(play.route.item) }
        }
    }

    @ViewBuilder
    private func secondaryButtons(isBare: Bool) -> some View {
        MyListButton(isSaved: library.isSaved(preview.id), isBare: isBare) {
            library.toggleSaved(savedPreview)
        }
        .contextMenu { SaveToMenu(title: savedPreview) }
        ListsMenu(title: savedPreview, isBare: isBare)
        if let play = playAction {
            Button("Choose a Source", systemImage: "list.bullet") {
                var route = play.route
                route.autoplay = false
                choosingSource = route
            }
            .buttonStyle(GlassIconButtonStyle(caption: "Sources", isBare: isBare))
            .help("Choose a Source")
        }
    }

    /// Movies only: a series is marked by season or episode.
    @ViewBuilder
    private func watchedActions(_ item: WatchItem) -> some View {
        if preview.type != MediaType.series {
            if library.isWatched(preview.id) {
                Button("Mark as Unwatched", systemImage: "eye.slash") {
                    library.markUnwatched([preview.id])
                    trakt.markUnwatched([item])
                }
            } else {
                Button("Mark as Watched", systemImage: "checkmark.circle") {
                    library.markWatched([item])
                    trakt.markWatched([item])
                }
            }
        }
    }

    #if os(tvOS)
    private let heroAlignment = HorizontalAlignment.leading
    /// Short enough for the first row below, episodes or cast, to show under the buttons.
    private let heroHeight: CGFloat = 560
    private let logoHeight: CGFloat = 160
    private let logoWidth: CGFloat = 560
    private let synopsisWidth: CGFloat = 900
    private let synopsisLines = 3
    private let synopsisUnderButtons = false
    #elseif os(macOS)
    private let heroAlignment = HorizontalAlignment.leading
    private let heroHeight: CGFloat = 420
    private let logoHeight: CGFloat = 110
    private let logoWidth: CGFloat = 360
    private let synopsisWidth: CGFloat = 540
    private let synopsisLines = 3
    private let synopsisUnderButtons = false
    #else
    // A centred stack suits a portrait phone; wider screens read better left-aligned,
    // and a short landscape screen needs a shorter hero.
    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
    private var heroAlignment: HorizontalAlignment { isWide ? .leading : .center }
    private var heroHeight: CGFloat {
        verticalSizeClass == .compact ? 300 : horizontalSizeClass == .regular ? 500 : 400
    }
    private var logoHeight: CGFloat { isWide ? 100 : 80 }
    private var logoWidth: CGFloat { isWide ? 360 : 260 }
    private let synopsisWidth: CGFloat = 620
    /// iPad's larger text would otherwise show less of the synopsis, with no way to read the rest.
    private let synopsisLines = 4
    /// On a phone the buttons come first, so the synopsis doesn't push them down.
    private var synopsisUnderButtons: Bool { !isWide }
    #endif
}

private struct MyListButton: View {
    let isSaved: Bool
    let isBare: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Label(title, systemImage: isSaved ? "checkmark" : "plus")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(GlassIconButtonStyle(caption: isSaved ? "Saved" : "Watch Later", isBare: isBare))
        .help(title)
    }

    private var title: String { isSaved ? "Remove from Watch Later" : "Add to Watch Later" }
}

/// viewer left off: the unfinished episode, else the one after the last finished, else the first.
@MainActor
struct PlayAction {
    /// "Play", "Resume" or "Resume S1, E6".
    let label: String
    /// Autoplays the remembered source, if there is one.
    let route: SourcesRoute

    /// Nil for a series until its episodes are known.
    init?(preview: MetaPreview, meta: Meta?, library: LibraryStore) {
        guard preview.type == MediaType.series else {
            label = library.resumePosition(for: preview.id) == nil ? "Play" : "Resume"
            route = Self.route(for: nil, preview: preview, meta: meta, autoplay: true)
            return
        }
        guard let videos = meta?.videos else { return nil }
        if let next = library.upNext(metaID: preview.id, videos: videos) {
            label = "\(next.resumeAt == nil ? "Play" : "Resume") \(Self.shortCode(for: next.video))"
            route = Self.route(for: next.video, preview: preview, meta: meta, autoplay: true)
        } else if let first = EpisodesSection.firstEpisode(in: videos) {
            label = "Play \(Self.shortCode(for: first))"
            route = Self.route(for: first, preview: preview, meta: meta, autoplay: true)
        } else {
            return nil
        }
    }

    /// The sources route for the movie itself, or for one of the series' episodes.
    static func route(for video: Video?, preview: MetaPreview, meta: Meta?, autoplay: Bool = false) -> SourcesRoute {
        let name = meta?.name ?? preview.name
        let item = WatchItem(
            id: video?.id ?? preview.id,
            type: preview.type,
            metaID: preview.id,
            title: name,
            season: video?.season,
            episode: video?.episode,
            episodeTitle: video?.displayTitle,
            poster: meta?.poster ?? preview.poster,
            background: meta?.background ?? preview.background,
            thumbnail: video?.thumbnail
        )
        let title = video.map { "\(name) · \(EpisodesSection.code(for: $0))" } ?? name
        let runtime = TraktAccount.minutes(meta?.runtime ?? preview.runtime).map { $0 * 60 }
        return SourcesRoute(item: item, title: title, autoplay: autoplay, runtime: runtime)
    }

    /// "S1, E6", as the button says it.
    private static func shortCode(for video: Video) -> String {
        switch (video.season, video.episode) {
        case let (season?, episode?): "S\(season), E\(episode)"
        default: EpisodesSection.code(for: video)
        }
    }
}

/// How far the hero has scrolled away, from 0 to 1. An object of its own, so scrolling
/// redraws only the backdrop rather than the whole page.
@MainActor @Observable
private final class HeroScroll {
    var progress = 0.0

    struct Fading<Content: View>: View {
        let scroll: HeroScroll
        @ViewBuilder let content: Content

        var body: some View {
            // Flattened first: faded layer by layer, the image shows through the opaque foot of
            // its bottom fade, and the frame's edge appears as a hard line.
            content.compositingGroup().opacity(1 - scroll.progress)
        }
    }
}
