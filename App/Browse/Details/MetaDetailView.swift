import LogeCore
import SwiftUI

struct MetaDetailView: View {
    let preview: MetaPreview

    @Environment(AddonStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(TMDBAccount.self) private var tmdb
    @State private var state = LoadState.loading
    @State private var tmdbState = TMDBLoadState.disconnected
    @State private var loadAttempt = 0
    @State private var tmdbAttempt = 0
    /// What the TMDB details on screen were loaded for, so returning to the page keeps them.
    @State private var tmdbLoadedKey: TMDBLoadKey?
    @State private var collection: TMDBCollection?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    #if !os(tvOS)
    /// The page's own shape rather than the screen's: window resizing narrows it.
    @State private var hasRoomForColumns = false
    #endif
    /// Set by "Choose a Source" and by picking an episode, which bypass the remembered source.
    @State private var choosingSource: SourcesRoute?
    @State private var heroScroll = HeroScroll()
    /// Taken from the backdrop; the canvas until it's known.
    @State private var tone = Color.canvas
    @State private var isConfirmingSeriesUnwatched = false
    #if os(macOS)
    /// Set by the Title menu's Play, which can't follow the page's Play link itself.
    @State private var isPlayRequested = false
    #endif
    #if os(tvOS)
    /// Focus starts on Play, whichever button the engine would otherwise pick. A series'
    /// Play arrives with its episodes, after focus has landed, so it's moved there once.
    @FocusState private var isPlayFocused: Bool
    @State private var hasFocusedPlay = false
    #endif
    @Environment(\.openURL) private var openURL

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
                            runtime: meta.runtime,
                            route: route(for:),
                            choose: { choosingSource = route(for: $0) }
                        )
                        .detailColumn(.side)
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
                    #if os(tvOS)
                    // At ten feet, what to watch next comes before who made this one.
                    MoreLikeThisRow(titles: tmdbDetails?.recommendations ?? [])
                    #endif
                    let people = creditedPeople(fallback: meta.people)
                    if !people.isEmpty {
                        PeopleRow(people: people, title: preview, staysInColumn: usesColumns)
                            .detailColumn(.side)
                    }
                    // The facts stay under the summary; what can be opened goes on the right.
                    InformationSection(meta: meta, details: tmdbDetails, people: people)
                    if let collection {
                        CollectionRow(collection: collection, currentID: tmdbDetails?.tmdbID)
                            .detailColumn(.side)
                    }
                    #if !os(tvOS)
                    MoreLikeThisRow(titles: tmdbDetails?.recommendations ?? [])
                        .detailColumn(.side)
                    #endif
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
                Room(tone: tone)
                HeroScroll.Fading(scroll: heroScroll) { backdrop(url: meta?.background ?? preview.background) }
            }
        }
        .roomTone(of: meta?.background ?? preview.background, into: $tone)
        .hidingPhoneTabBar()
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        // The name takes the bar once the logo has scrolled away.
        .toolbar {
            ToolbarItem(placement: .principal) { HeroScroll.Title(scroll: heroScroll, name: preview.name) }
        }
        .navigationBarTitleDisplayMode(.inline)
        #elseif os(macOS)
        // Otherwise the window title falls back to the app's name.
        .navigationTitle(preview.name)
        .focusedSceneValue(\.titleActions, titleCommandActions(meta: meta, play: play))
        .navigationDestination(isPresented: $isPlayRequested) {
            if let route = play?.route { SourcesView(route: route) }
        }
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
        // Stream addons such as AIOStreams take seconds to answer, so ask while the page is
        // being read; the sources screen picks up the same request.
        .task(id: play?.route.id) {
            guard let route = play?.route else { return }
            let providers = store.addons.streamProviders(type: route.type, id: route.id)
                .chosen(UserDefaults.standard.string(forKey: [StreamProvider].chosenAddonKey),
                        combined: UserDefaults.standard.bool(forKey: SyncedSettings.Key.combinesAddonSources))
            for provider in providers {
                provider.prefetchStreams(type: route.type, id: route.id)
            }
            // The source Play would start by itself, chosen as the sources screen's autoplay
            // chooses it, is warmed so its addon has the link resolved by then. Without a
            // remembered source Play leaves the choice to the list, so nothing is.
            guard let remembered = library.sources[route.item.metaID],
                  let provider = providers.first(where: { $0.id == remembered.providerURL }),
                  let streams = try? await provider.streams(type: route.type, id: route.id),
                  !Task.isCancelled
            else { return }
            let runtime = route.bitrateRuntime(in: library)
            let allowed = SourceSelection.automatic(streams, maximumBitrate: PlaybackPreferences.maximumBitrate,
                                                    cachedOnly: PlaybackPreferences.cachedOnly) {
                StreamDetails($0, runtime: runtime)
            }
            if let stream = SourceSelection.continuing(remembered, itemID: route.id, in: allowed) {
                StreamWarmup.shared.warm(stream)
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
            ? AnyLayout(DetailColumnsLayout(sideTop: heroHeight - 170, spacing: spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
    }

    /// One Retry for everything that failed: addon and TMDB details load separately, but a
    /// button for each read as several problems.
    private func retry() {
        // Whatever loaded stays on the page while the rest is asked again.
        if isAddonFailed {
            state = .loading
            loadAttempt += 1
        }
        if case .failed = tmdbState { tmdbAttempt += 1 }
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
        MediaType.isIMDbTitle(preview.id)
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
                    Text("Connect TMDB in Settings for cast and crew and recommendations.")
                }
            case .loaded:
                EmptyView()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Metrics.gutter)
    }

    /// What Watch Later keeps: the catalog entry, with artwork it lacked
    /// filled in from the full details, so the title has a poster wherever it's listed.
    private func savedPreview(_ meta: Meta?) -> MetaPreview {
        meta.map(preview.fillingArtwork(from:)) ?? preview
    }

    private func route(for video: Video?) -> SourcesRoute {
        PlayAction.route(for: video, preview: preview, meta: loaded)
    }

    private func backdrop(url: String?) -> some View {
        Artwork(url: url)
            .overlay { BackdropFade(tone: tone) }
            #if os(tvOS)
            .overlay {
                LinearGradient(colors: [tone.opacity(0.8), tone.opacity(0)], startPoint: .leading, endPoint: .center)
                    .animation(.easeOut(duration: 0.6), value: tone)
            }
            #else
            // Beside two columns, the artwork takes the top right and fades out towards the
            // summary on the left.
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: usesColumns ? 0.4 : 0)],
                               startPoint: .leading, endPoint: .trailing)
            }
            .containerRelativeFrame(.horizontal) { width, _ in usesColumns ? width * 0.64 : width }
            .frame(maxWidth: .infinity, alignment: .trailing)
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

    private func logo(meta: Meta?) -> some View {
        TitleLogo(logo: meta?.logo ?? preview.logo, name: preview.name, maxHeight: logoHeight, restsOnLettering: true,
                  isWhite: true)
            // As tall as the logo is, not as tall as it may be: a wide, low one otherwise
            // floats in the middle of that room, far above the buttons.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: logoWidth, alignment: Alignment(horizontal: heroAlignment, vertical: .center))
    }

    /// The logo low on the backdrop, one line of facts, Play, the other actions with their
    /// names, then the description: centred down a phone, the left column on iPad and Mac.
    /// Apple TV puts two lines of description before the buttons, with nothing focusable in
    /// between, so one press down from Play reaches the episodes.
    private func hero(meta: Meta?, play: PlayAction?) -> some View {
        VStack(alignment: heroAlignment, spacing: 0) {
            logo(meta: meta)
                // The logo's foot stays in one place, so taller logos reach further up the backdrop.
                .frame(minHeight: usesColumns ? 150 : heroHeight - 175, alignment: .bottom)
            facts(meta: meta)
                .multilineTextAlignment(heroAlignment == .center ? .center : .leading)
                .padding(.top, 14)
            #if os(tvOS)
            if let description = meta?.description ?? preview.description {
                Text(description)
                    .font(.synopsis)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .frame(maxWidth: 900, alignment: .leading)
                    .padding(.top, 14)
            }
            HStack(spacing: 24) {
                playButton(play)
                actions(meta: meta, play: play)
            }
            .padding(.top, 34)
            if let left = timeLeft(play) {
                Text(left)
                    .font(.metaLine)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            }
            #else
            playButton(play)
                .padding(.top, 16)
            actions(meta: meta, play: play)
                .padding(.top, 16)
            #endif
            #if !os(tvOS)
            if let description = meta?.description ?? preview.description {
                ExpandableText(text: description)
                    .padding(.top, 18)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: heroAlignment, vertical: .top))
        .padding(.horizontal, Metrics.gutter)
    }

    #if os(tvOS)
    /// "31 min left" of what Play resumes, under the buttons.
    private func timeLeft(_ play: PlayAction?) -> String? {
        guard let id = play?.route.id, let progress = library.progress[id], !progress.isFinished,
              library.resumePosition(for: id) != nil else { return nil }
        return "\(max(Int((progress.duration - progress.position) / 60), 1)) min left"
    }
    #endif

    /// Genres, year and runtime with the scores after them, or under them where one line
    /// doesn't hold both, as with large text.
    private func facts(meta: Meta?) -> some View {
        let info = meta?.infoLine ?? preview.infoLine
        let line = info.quiet
        let scores = ScoresLine(id: preview.id, imdbRating: info.rating)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                line
                scores
            }
            VStack(alignment: heroAlignment, spacing: 6) {
                line
                scores
            }
        }
    }

    /// Everything besides Play, each with its name: circles in equal columns; on the Mac small
    /// buttons in a row, in two when the column is too narrow for one.
    private func actions(meta: Meta?, play: PlayAction?) -> some View {
        Group {
            #if os(macOS)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actionButtons(meta: meta, play: play) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    actionButtons(meta: meta, play: play)
                }
            }
            #else
            HStack(alignment: .top, spacing: Self.actionSpacing) { actionButtons(meta: meta, play: play) }
            #endif
        }
        .confirmationDialog("Mark \(preview.name) as unwatched?", isPresented: $isConfirmingSeriesUnwatched,
                            titleVisibility: .visible) {
            Button("Mark as Unwatched", role: .destructive) {
                library.markUnwatched((meta?.videos ?? []).map(\.id))
            }
        } message: {
            Text("Progress and watched marks for all its episodes are removed.")
        }
    }

    @ViewBuilder
    private func actionButtons(meta: Meta?, play: PlayAction?) -> some View {
        let isSaved = library.isSaved(preview.id)
        let saved = savedPreview(meta)
        Button(isSaved ? "In Watch Later" : "Watch Later", systemImage: isSaved ? "checkmark" : "plus") {
            library.toggleSaved(saved)
        }
        .buttonStyle(RoundButtonStyle(isOn: isSaved))
        .accessibilityLabel(isSaved ? "Remove from Watch Later" : "Add to Watch Later")
        if let trailer = trailerURL(meta) {
            Button("Trailer", systemImage: "play.rectangle") { openURL(trailer) }
                .buttonStyle(RoundButtonStyle())
        }
        Button("Sources", systemImage: "list.bullet") { chooseSource(play)?() }
            .buttonStyle(RoundButtonStyle())
            .disabled(play == nil)
        watchedButton(meta: meta, play: play)
    }

    #if os(macOS)
    /// The page's buttons for the Title menu, which works on the title in the key window.
    private func titleCommandActions(meta: Meta?, play: PlayAction?) -> TitleCommandActions {
        let saved = savedPreview(meta)
        let isWatched: Bool
        let toggleWatched: (() -> Void)?
        if preview.type == MediaType.series {
            let released = (meta?.videos ?? []).filter { $0.isReleased() && $0.season != 0 }
            isWatched = !released.isEmpty && released.allSatisfy { library.isWatched($0.id) }
            toggleWatched = released.isEmpty ? nil
                : isWatched ? { isConfirmingSeriesUnwatched = true }
                : { library.markWatched(released.map { route(for: $0).item }) }
        } else if let item = play?.route.item {
            isWatched = library.isWatched(item.id)
            toggleWatched = { [isWatched] in
                if isWatched { library.markUnwatched([item.id]) } else { library.markWatched([item]) }
            }
        } else {
            isWatched = false
            toggleWatched = nil
        }
        return TitleCommandActions(
            playLabel: play?.label ?? "Play",
            play: play == nil ? nil : { isPlayRequested = true },
            isSaved: library.isSaved(preview.id),
            toggleSaved: { library.toggleSaved(saved) },
            chooseSource: chooseSource(play),
            isWatched: isWatched,
            toggleWatched: toggleWatched)
    }
    #endif

    /// A movie's mark, or for a series every episode out so far; taking a series' marks
    /// away clears all its progress, so that asks first.
    @ViewBuilder
    private func watchedButton(meta: Meta?, play: PlayAction?) -> some View {
        if preview.type == MediaType.series {
            let released = (meta?.videos ?? []).filter { $0.isReleased() && $0.season != 0 }
            let isWatched = !released.isEmpty && released.allSatisfy { library.isWatched($0.id) }
            Menu {
                if !isWatched {
                    Button("Mark All as Watched", systemImage: "checkmark.circle") {
                        library.markWatched(released.map { route(for: $0).item })
                    }
                }
                if released.contains(where: { library.progress[$0.id] != nil }) {
                    Button("Mark All as Unwatched", systemImage: "eye.slash") { isConfirmingSeriesUnwatched = true }
                }
            } label: {
                Label("Watched", systemImage: "checkmark.circle")
            }
            .menuIndicator(.hidden)
            // Without it the Mac draws a menu its own way and ignores the button style.
            .menuStyle(.button)
            .buttonStyle(RoundButtonStyle(isOn: isWatched))
            .disabled(released.isEmpty)
        } else if let item = play?.route.item {
            let isWatched = library.isWatched(item.id)
            Button("Watched", systemImage: "checkmark.circle") {
                if isWatched { library.markUnwatched([item.id]) } else { library.markWatched([item]) }
            }
            .buttonStyle(RoundButtonStyle(isOn: isWatched))
            .accessibilityLabel(isWatched ? "Mark as Unwatched" : "Mark as Watched")
        }
    }

    /// Circles share the width in equal columns; the TV's buttons sit apart.
    #if os(tvOS)
    private static let actionSpacing: CGFloat = 24
    #else
    private static let actionSpacing: CGFloat = 0
    #endif

    /// The sources for what Play would start, to pick one by hand.
    private func chooseSource(_ play: PlayAction?) -> (() -> Void)? {
        play.map { play in
            {
                var route = play.route
                route.autoplay = false
                choosingSource = route
            }
        }
    }

    private func trailerURL(_ meta: Meta?) -> URL? {
        Self.trailerURL(youTubeID: tmdbDetails?.trailerYouTubeID ?? meta?.trailers?.youTubeID)
    }

    @ViewBuilder
    private func playButton(_ play: PlayAction?) -> some View {
        if let play {
            NavigationLink(value: play.route) {
                Label(play.label, systemImage: "play.fill")
                    #if !os(tvOS)
                    .frame(maxWidth: .infinity)
                    #else
                    .frame(minWidth: 260)
                    #endif
            }
            .buttonStyle(PrimaryButtonStyle())
            #if os(tvOS)
            .focused($isPlayFocused)
            .onAppear {
                guard !hasFocusedPlay else { return }
                hasFocusedPlay = true
                isPlayFocused = true
            }
            #endif
        }
    }

    /// Trailers play on YouTube: its site, which opens the YouTube app where that's installed.
    /// Apple TV has no browser to open it in, so it offers none.
    private static func trailerURL(youTubeID: String?) -> URL? {
        #if os(tvOS)
        nil
        #else
        youTubeID.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") }
        #endif
    }

    #if os(tvOS)
    private let heroAlignment = HorizontalAlignment.leading
    /// Short enough for the first row below, episodes or cast, to show under the buttons.
    private let heroHeight: CGFloat = 560
    private let logoHeight: CGFloat = 160
    private let logoWidth: CGFloat = 560
    #elseif os(macOS)
    private let heroAlignment = HorizontalAlignment.leading
    private let heroHeight: CGFloat = 420
    private let logoHeight: CGFloat = 130
    private let logoWidth: CGFloat = 400
    #else
    // A centred stack suits the portrait phone; the landscape iPad reads better left-aligned.
    // Browsing never turns sideways, on either.
    private var isWide: Bool { horizontalSizeClass == .regular }
    private var heroAlignment: HorizontalAlignment { isWide ? .leading : .center }
    private var heroHeight: CGFloat { isWide ? 500 : 400 }
    /// The title is the one large thing in the hero. A phone gives it the full text width.
    private let logoHeight: CGFloat = 130
    private var logoWidth: CGFloat { isWide ? 400 : .infinity }
    #endif
}

/// viewer left off: the unfinished episode, else the one after the last finished, else the first.
@MainActor
struct PlayAction {
    /// "Play", "Resume" or "Resume S1 E6".
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
            label = "\(next.resumeAt == nil ? "Play" : "Resume") \(EpisodesSection.code(for: next.video))"
            route = Self.route(for: next.video, preview: preview, meta: meta, autoplay: true)
        } else if let first = EpisodesSection.firstEpisode(in: videos) {
            label = "Play \(EpisodesSection.code(for: first))"
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

    /// The title's name in the bar, once the logo has scrolled under it.
    struct Title: View {
        let scroll: HeroScroll
        let name: String

        var body: some View {
            Text(name)
                .font(.headline)
                .lineLimit(1)
                .opacity(scroll.progress > 0.85 ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: scroll.progress > 0.85)
                .accessibilityHidden(scroll.progress <= 0.85)
        }
    }
}
