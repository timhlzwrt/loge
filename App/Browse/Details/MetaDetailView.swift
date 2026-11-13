import LogeCore
import SwiftUI

struct MetaDetailView: View {
    let preview: MetaPreview

    @Environment(AddonStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(TMDBAccount.self) private var tmdb
    @Environment(MDBListAccount.self) private var mdblist
    @State private var state = LoadState.loading
    @State private var tmdbState = TMDBLoadState.disconnected
    @State private var loadAttempt = 0
    @State private var tmdbAttempt = 0
    /// Every Retry on the page, which reviews follow to reload if they failed too.
    @State private var retries = 0
    /// What the TMDB details on screen were loaded for, so returning to the page keeps them.
    @State private var tmdbLoadedKey: TMDBLoadKey?
    @State private var collection: TMDBCollection?
    @State private var scores: TitleScores?
    /// Why the Letterboxd and Rotten Tomatoes scores are missing, when it's something to act on.
    @State private var scoresFailure: String?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    #if !os(tvOS)
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
        /// Retrying doesn't help a title TMDB doesn't have.
        case disconnected, loading, loaded(TMDBDetails), failed(String, canRetry: Bool)
    }

    private struct TMDBLoadKey: Hashable {
        let revision: Int
        let attempt: Int
    }

    var body: some View {
        // Each merges the details and scans the library, so they're worked out once per update.
        let meta = loaded
        let play = PlayAction(preview: preview, meta: meta, library: library)
        ScrollView {
            pageLayout {
                hero(meta: meta, play: play)
                if let meta {
                    if preview.type == MediaType.series, case .loading = state {
                        ProgressView("Loading episodes…")
                            .frame(maxWidth: .infinity)
                    }
                    if let videos = meta.videos, !videos.isEmpty, meta.type == MediaType.series {
                        EpisodesSection(
                            videos: videos,
                            upNextID: library.upNext(metaID: preview.id, videos: videos)?.video.id,
                            backdrop: meta.background ?? preview.background,
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
                    if let collection {
                        CollectionRow(collection: collection, currentID: tmdbDetails?.tmdbID)
                            .detailColumn(.full)
                    }
                    MoreLikeThisRow(titles: tmdbDetails?.recommendations ?? [])
                        .detailColumn(.full)
                    ReviewsSection(preview: preview, pageRetries: retries, pageOffersRetry: offersRetry)
                    InformationSection(meta: meta, details: tmdbDetails, people: people)
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
                tmdbStatus(hasDetails: meta != nil)
                    .detailColumn(.full)
            }
            .padding(.bottom, 40)
        }
        .scrollClipDisabled()
        #if !os(tvOS)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width >= 880 && proxy.size.width > proxy.size.height
        } action: { hasRoomForColumns = $0 && !Metrics.isPhone }
        #endif
        // The backdrop stays put behind the page, so it fades as the hero scrolls away
        // instead of showing behind episodes and cast. On Apple TV a bright backdrop
        // otherwise stays behind the rows' captions.
        .onScrollGeometryChange(for: Double.self) { geometry in
            min(max((geometry.contentOffset.y + geometry.contentInsets.top) / heroHeight, 0), 1)
        } action: { _, progress in
            heroScroll.progress = progress
        }
        // One background with the canvas underneath: as two, the canvas was drawn only as far
        // down as the backdrop on a wide iPad page, leaving the rest of the page black.
        .background {
            ZStack(alignment: .top) {
                Color.canvas.ignoresSafeArea()
                HeroScroll.Fading(scroll: heroScroll) { backdrop(url: meta?.background ?? preview.background) }
            }
        }
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
            // This also runs on returning from Sources or the player. Loading again would
            // flicker the page, and a failure would replace the episodes being used.
            if case .loaded = state { return }
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
            let key = TMDBLoadKey(revision: tmdb.revision, attempt: tmdbAttempt)
            // Details already on screen stay while a changed token loads them again.
            if case .loaded = tmdbState {
                if tmdbLoadedKey == key { return }
            } else {
                tmdbState = .loading
            }
            do {
                let details = try await tmdb.details(imdbID: preview.id, type: preview.type)
                try Task.checkCancellation()
                tmdbState = .loaded(details)
                tmdbLoadedKey = key
            } catch {
                guard !Task.isCancelled else { return }
                if case .loaded = tmdbState { return }
                let message = switch error as? TMDBError {
                case .unauthorized: "TMDB didn't accept the saved token. Check TMDB in Settings."
                case .rateLimited: "TMDB is busy. Try again in a few minutes."
                case .notFound: "This title wasn't found on TMDB."
                default: "Couldn't load TMDB details."
                }
                tmdbState = .failed(message, canRetry: error as? TMDBError != .notFound)
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
        .task(id: "\(tmdb.revision):\(tmdbDetails?.collectionID ?? 0)") {
            guard let id = tmdbDetails?.collectionID else {
                collection = nil
                return
            }
            // An extra row: without it the page is complete, so a failure leaves the page as
            // it is rather than adding a third thing to retry.
            if let loaded = try? await tmdb.collection(id: id) { collection = loaded }
        }
        .task(id: mdblist.revision) {
            guard mdblist.isConfigured, isOnTMDB else {
                scores = nil
                scoresFailure = nil
                return
            }
            do {
                scores = try await mdblist.scores(imdbID: preview.id, type: preview.type)
                scoresFailure = nil
            } catch {
                guard !Task.isCancelled else { return }
                // A title MDBList doesn't have, or a moment without a connection, just leaves the
                // IMDb rating on its own. A key that stopped working needs the user.
                switch error as? MDBListError {
                case .unauthorized: scoresFailure = "MDBList didn't accept the saved key. Check MDBList in Settings."
                case .rateLimited: scoresFailure = "MDBList's requests for today are used up, so Letterboxd and Rotten Tomatoes scores are missing."
                default: scoresFailure = nil
                }
            }
        }
        // Stream addons such as AIOStreams take seconds to answer, so ask while the page is
        // being read; the sources screen picks up the same request.
        .task(id: play?.route.id) {
            guard let route = play?.route else { return }
            for provider in store.addons.streamProviders(type: route.type, id: route.id) {
                provider.prefetchStreams(type: route.type, id: route.id)
            }
        }
    }

    private var usesColumns: Bool {
        #if os(tvOS)
        false
        #else
        hasRoomForColumns
        #endif
    }

    private var pageLayout: AnyLayout {
        let spacing: CGFloat = 32
        return usesColumns
            ? AnyLayout(DetailColumnsLayout(sideTop: heroHeight - 160, spacing: spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
    }

    /// One Retry for everything that failed: addon details, TMDB details and reviews load
    /// separately, but a button for each read as several problems.
    private func retry() {
        retries += 1
        // Whatever loaded stays on the page while the rest is asked again.
        if isAddonFailed {
            state = .loading
            loadAttempt += 1
        }
        if case .failed = tmdbState { tmdbAttempt += 1 }
    }

    /// Whether the page shows a Retry of its own, for the addon or TMDB details.
    private var offersRetry: Bool {
        if isAddonFailed { return true }
        if case .failed(_, canRetry: true) = tmdbState { return true }
        return false
    }

    /// Full details once loaded; until then the catalog entry already has enough to draw the page.
    private var loaded: Meta? {
        let base: Meta? = if case .loaded(let meta) = state { meta } else { nil }
        if case .loaded(let details) = tmdbState {
            return base.map { details.applying(to: $0) } ?? details.meta(for: preview)
        }
        return base
    }

    private var isAddonFailed: Bool {
        if case .failed = state { true } else { false }
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
            // Stands in for a row that only comes with TMDB.
            if tmdb.isConfigured {
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
        }
        .padding(.horizontal, Metrics.gutter)
        .clipped()
    }

    /// Cast & Crew comes with TMDB: without a token the page leaves it out, rather than list
    /// names that have no photos and lead to no filmography. With one, the addon's credits
    /// stand in until TMDB's arrive, and for a title TMDB doesn't have.
    private func creditedPeople(fallback: [Person]) -> [Person] {
        guard tmdb.isConfigured else { return [] }
        if case .loaded(let details) = tmdbState, !details.people.isEmpty { return details.creditedPeople }
        return fallback
    }

    @ViewBuilder
    private func tmdbStatus(hasDetails: Bool) -> some View {
        Group {
            switch tmdbState {
            case .failed(let message, let canRetry):
                HStack {
                    Text(message + (hasDetails ? " Showing available addon details." : ""))
                    // The addon's failure note has the page's Retry already.
                    if canRetry, !isAddonFailed {
                        Button("Retry TMDB", action: retry)
                    }
                }
            case .loading:
                Text("Loading TMDB details…")
            case .disconnected:
                if !tmdb.isConfigured, isOnTMDB, hasDetails {
                    Text("Connect TMDB in Settings for cast and crew, reviews and recommendations.")
                }
            case .loaded:
                EmptyView()
            }
            if let scoresFailure {
                Text(scoresFailure)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.gutter)
    }

    /// What My List and the user's lists keep: the catalog entry, with artwork it lacked
    /// filled in from the full details, so the title has a poster wherever it's listed.
    private func savedPreview(_ meta: Meta?) -> MetaPreview {
        meta.map(preview.fillingArtwork(from:)) ?? preview
    }

    private func route(for video: Video?) -> SourcesRoute {
        PlayAction.route(for: video, preview: preview, meta: loaded)
    }

    private func backdrop(url: String?) -> some View {
        Artwork(url: url)
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

    /// The title and Play lead. The description follows with the facts and scores one size
    /// down beneath it; on a phone that's under the buttons, so it doesn't push them down.
    private func hero(meta: Meta?, play: PlayAction?) -> some View {
        VStack(alignment: heroAlignment, spacing: 20) {
            TitleLogo(logo: meta?.logo ?? preview.logo, name: preview.name, maxHeight: logoHeight, restsOnLettering: true)
                // As tall as the logo is, not as tall as it may be: a wide, low one otherwise
                // floats in the middle of that room, far above the buttons.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: logoWidth, alignment: Alignment(horizontal: heroAlignment, vertical: .center))
            if synopsisUnderButtons {
                buttons(meta: meta, play: play)
                about(meta: meta)
            } else {
                about(meta: meta)
                buttons(meta: meta, play: play)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: heroAlignment, vertical: .bottom))
        .frame(minHeight: heroHeight, alignment: .bottom)
        .padding(.horizontal, Metrics.gutter)
    }

    private func about(meta: Meta?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let description = meta?.description ?? preview.description {
                if synopsisUnderButtons {
                    ExpandableText(text: description)
                } else {
                    Text(description)
                        .font(.synopsis)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(synopsisLines)
                        .frame(maxWidth: synopsisWidth, alignment: .leading)
                }
            }
            facts(meta: meta)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Genres, year and runtime with the scores after them, or under them where one line
    /// doesn't hold both, as with large text.
    private func facts(meta: Meta?) -> some View {
        let info = meta?.infoLine ?? preview.infoLine
        let line = info.quiet
        let scores = ScoresLine(id: preview.id, type: preview.type, imdbRating: info.rating, scores: scores)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                line
                scores
            }
            VStack(alignment: .leading, spacing: 6) {
                line
                scores
            }
        }
    }

    /// Play with Watch Later and More. A phone centres the three under its title, Play in the
    /// middle and a size down; wider screens start with Play, at the leading edge.
    private func buttons(meta: Meta?, play: PlayAction?) -> some View {
        let saved = savedPreview(meta)
        let watchLater = MyListButton(isSaved: library.isSaved(preview.id)) {
            library.toggleSaved(saved)
        }
        .contextMenu { SaveToMenu(title: saved) }
        let more = TitleMoreMenu(
            title: saved,
            trailer: Self.trailerURL(youTubeID: tmdbDetails?.trailerYouTubeID ?? meta?.trailers?.youTubeID),
            chooseSource: play.map { play in
                {
                    var route = play.route
                    route.autoplay = false
                    choosingSource = route
                }
            },
            movie: preview.type == MediaType.series ? nil : play?.route.item)
        // No merging distance: the circles stay apart, as separate buttons.
        return GlassEffectContainer(spacing: 0) {
            // From the top: on Apple TV a focused circle has its name under it, which would
            // otherwise push Play down to stay centred.
            HStack(alignment: .top, spacing: synopsisUnderButtons ? 12 : 16) {
                if synopsisUnderButtons {
                    watchLater
                    playButton(play)
                    more
                } else {
                    playButton(play)
                    watchLater
                    more
                }
            }
        }
        .controlSize(synopsisUnderButtons ? .small : .regular)
    }

    @ViewBuilder
    private func playButton(_ play: PlayAction?) -> some View {
        if let play {
            NavigationLink(value: play.route) {
                Label(play.label, systemImage: "play.fill")
                    // 172 pt with the button's own padding: room for "Resume S2, E10", so the
                    // circles beside it sit in the same place on every title.
                    .frame(minWidth: synopsisUnderButtons ? 128 : nil)
            }
            .buttonStyle(PrimaryButtonStyle())
            .contextMenu {
                // Movies only: a series is marked by season or episode.
                if preview.type != MediaType.series { WatchedMarkButton(item: play.route.item) }
            }
        }
    }

    /// Trailers play on YouTube: its site, which opens the YouTube app where that's installed.
    /// Apple TV has no browser, so there it's the app or no button.
    private static func trailerURL(youTubeID: String?) -> URL? {
        guard let youTubeID else { return nil }
        #if os(tvOS)
        guard let url = URL(string: "youtube://watch/\(youTubeID)"), UIApplication.shared.canOpenURL(url) else { return nil }
        return url
        #else
        return URL(string: "https://www.youtube.com/watch?v=\(youTubeID)")
        #endif
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
    private let logoHeight: CGFloat = 130
    private let logoWidth: CGFloat = 480
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
    /// The title is the one large thing in the hero. A phone gives it the full text width; a
    /// short landscape screen has no room for a tall one.
    private var logoHeight: CGFloat { verticalSizeClass == .compact ? 100 : 130 }
    private var logoWidth: CGFloat { isWide ? 480 : .infinity }
    private let synopsisWidth: CGFloat = 620
    /// iPad's larger text would otherwise show less of the synopsis, with no way to read the rest.
    private let synopsisLines = 4
    /// On a phone the buttons come first, so the synopsis doesn't push them down.
    private var synopsisUnderButtons: Bool { !isWide }
    #endif
}

private struct MyListButton: View {
    let isSaved: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Label(title, systemImage: isSaved ? "checkmark" : "plus")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(GlassIconButtonStyle(caption: isSaved ? "Saved" : "Watch Later"))
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
        let runtime = Meta.minutes(inRuntime: meta?.runtime ?? preview.runtime).map { $0 * 60 }
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
