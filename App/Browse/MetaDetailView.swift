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
    #endif
    /// Set by "Choose a Source" and by picking an episode, which bypass the remembered source.
    @State private var choosingSource: SourcesRoute?

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
            VStack(alignment: .leading, spacing: 28) {
                hero
                if let meta = loaded {
                    if preview.type == "series", case .loading = state {
                        ProgressView("Loading episodes…")
                            .frame(maxWidth: .infinity)
                    }
                    if let videos = meta.videos, !videos.isEmpty, meta.type == "series" {
                        EpisodesSection(
                            videos: videos,
                            upNextID: library.upNext(metaID: preview.id, videos: videos)?.video.id,
                            route: route(for:),
                            choose: { choosingSource = route(for: $0) }
                        )
                    }
                    if case .failed = state {
                        HStack {
                            Text("Addon details are unavailable.\(preview.type == "series" ? " Episodes could not be loaded." : "")")
                                .foregroundStyle(.secondary)
                            Button("Retry", action: retry)
                        }
                        .padding(.horizontal, Metrics.gutter)
                    }
                    let people = creditedPeople(fallback: meta.people)
                    if !people.isEmpty {
                        PeopleRow(people: people, title: preview)
                    }
                    ReviewsSection(preview: preview)
                    InformationSection(meta: meta, details: tmdbDetails)
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
        #elseif os(macOS)
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
            guard tmdb.isConfigured, preview.id.wholeMatch(of: /tt\d+/) != nil,
                  preview.type == "movie" || preview.type == "series" else {
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
            case .loaded, .disconnected:
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
                    .lineLimit(3)
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

    private var buttons: some View {
        HStack(spacing: 12) {
            if let play = playAction {
                NavigationLink(value: play.route) {
                    Label(play.label, systemImage: "play.fill")
                        .frame(maxWidth: synopsisUnderButtons ? .infinity : nil)
                }
                .buttonStyle(PrimaryButtonStyle())
                .contextMenu { watchedActions(play.route.item) }
            }
            // No merging distance: the circles stay apart, as separate buttons.
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 12) {
                    MyListButton(isSaved: library.isSaved(preview.id)) {
                        library.toggleSaved(savedPreview)
                    }
                    .contextMenu { SaveToMenu(title: savedPreview) }
                    ListsMenu(title: savedPreview)
                    if let play = playAction {
                        Button("Choose a Source", systemImage: "list.bullet") {
                            var route = play.route
                            route.autoplay = false
                            choosingSource = route
                        }
                        .buttonStyle(GlassIconButtonStyle())
                    }
                }
            }
        }
    }

    /// Movies only: a series is marked by season or episode.
    @ViewBuilder
    private func watchedActions(_ item: WatchItem) -> some View {
        if preview.type != "series" {
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
    private let synopsisUnderButtons = false
    #elseif os(macOS)
    private let heroAlignment = HorizontalAlignment.leading
    private let heroHeight: CGFloat = 420
    private let logoHeight: CGFloat = 110
    private let logoWidth: CGFloat = 360
    private let synopsisWidth: CGFloat = 540
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
    /// On a phone the buttons come first, so the synopsis doesn't push them down.
    private var synopsisUnderButtons: Bool { !isWide }
    #endif
}

/// Facts the hero's meta line leaves out, as label and value pairs in as many columns as fit.
private struct InformationSection: View {
    let meta: Meta
    let details: TMDBDetails?

    var body: some View {
        let facts = facts
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Information")
                    .font(.sectionTitle)
                if let tagline = details?.tagline {
                    Text(tagline).font(.synopsis).italic().foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.infoColumnWidth), spacing: 24, alignment: .topLeading)],
                          alignment: .leading, spacing: 20) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fact.label)
                                .font(.metaLine)
                                .foregroundStyle(.secondary)
                            Text(fact.value)
                                .font(.synopsis)
                                .foregroundStyle(.white.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
    }

    /// Runtime, year and rating are already in the meta line; the line shows only the first genres.
    private var facts: [(label: String, value: String)] {
        var facts: [(label: String, value: String)] = []
        if let genres = meta.genres, !genres.isEmpty {
            facts.append(("Genres", genres.joined(separator: ", ")))
        }
        if let date = details?.releaseDate {
            facts.append((meta.type == "series" ? "First Aired" : "Released", formattedDate(date)))
        } else if let date = meta.releaseDate {
            facts.append((meta.type == "series" ? "First Aired" : "Released", date.formatted(date: .long, time: .omitted)))
        }
        if let status = details?.status { facts.append(("Status", status)) }
        if let seasons = details?.seasonCount {
            let episodes = details?.episodeCount.map { " · \($0) \($0 == 1 ? "episode" : "episodes")" } ?? ""
            facts.append(("Series", "\(seasons) \(seasons == 1 ? "season" : "seasons")\(episodes)"))
        }
        if let lastAirDate = details?.lastAirDate { facts.append(("Last Aired", formattedDate(lastAirDate))) }
        if let originalTitle = details?.originalTitle, originalTitle != meta.name {
            facts.append(("Original Title", originalTitle))
        }
        if let language = details?.originalLanguage {
            facts.append(("Original Language", Locale(identifier: "en").localizedString(forLanguageCode: language) ?? language))
        }
        if let countries = details?.countries, !countries.isEmpty {
            facts.append(("Country", countries.joined(separator: ", ")))
        } else if let country = meta.country, !country.isEmpty {
            facts.append(("Country", country))
        }
        if let studios = details?.studios, !studios.isEmpty { facts.append(("Production", studios.joined(separator: ", "))) }
        if let rating = details?.rating, let votes = details?.voteCount {
            facts.append(("TMDB Rating", "\(rating.formatted(.number.precision(.fractionLength(1))))/10 · \(votes.formatted()) votes"))
        }
        if let budget = details?.budget { facts.append(("Budget", budget.formatted(.currency(code: "USD").precision(.fractionLength(0))))) }
        if let revenue = details?.revenue { facts.append(("Box Office", revenue.formatted(.currency(code: "USD").precision(.fractionLength(0))))) }
        if let awards = meta.awards, !awards.isEmpty {
            facts.append(("Awards", awards))
        }
        return facts
    }

    private func formattedDate(_ value: String) -> String {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return value }
        return date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en")))
    }
}

/// A description clamped to two lines, with "more" at the end when it overflows.
private struct ExpandableText: View {
    let text: String
    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    var body: some View {
        let isTruncated = !isExpanded && fullHeight > shownHeight + 1
        Button {
            if isTruncated || isExpanded { isExpanded.toggle() }
        } label: {
            Text(text)
                .font(.synopsis)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(isExpanded ? nil : 2)
                // Otherwise the hero's stack squeezes the expanded text back to a few lines.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                .background(alignment: .top) {
                    // The unclamped text, measured to tell whether two lines cut it short.
                    Text(text)
                        .font(.synopsis)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isTruncated {
                        Text("more")
                            .font(.synopsis.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 24)
                            .background(alignment: .trailing) {
                                LinearGradient(colors: [.canvas.opacity(0), .canvas], startPoint: .leading, endPoint: .init(x: 0.4, y: 0.5))
                            }
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityHint(isTruncated ? "Shows the whole description" : "")
    }
}

private struct MyListButton: View {
    let isSaved: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Label(isSaved ? "Remove from Watch Later" : "Add to Watch Later", systemImage: isSaved ? "checkmark" : "plus")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(GlassIconButtonStyle())
    }
}

private struct EpisodesSection: View {
    @Environment(TraktAccount.self) private var trakt
    let videos: [Video]
    let upNextID: String?
    let route: (Video) -> SourcesRoute
    /// Opens the sources for an episode.
    let choose: (Video) -> Void
    @State private var season: Int
    @Environment(LibraryStore.self) private var library

    init(videos: [Video], upNextID: String?, route: @escaping (Video) -> SourcesRoute, choose: @escaping (Video) -> Void) {
        self.videos = videos
        self.upNextID = upNextID
        self.route = route
        self.choose = choose
        // Open on the season being watched, otherwise the first real one rather than specials (season 0).
        let upNextSeason = videos.first { $0.id == upNextID }?.season
        _season = State(initialValue: upNextSeason ?? Self.seasons(in: videos).first ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            seasonMenu
                .padding(.horizontal, Metrics.gutter)
            #if os(macOS)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .top), count: 4),
                      alignment: .leading, spacing: 28) {
                ForEach(episodes) { episodeButton($0) }
            }
            .padding(.horizontal, Metrics.gutter)
            #else
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                        ForEach(episodes) { video in
                            episodeButton(video)
                                .frame(width: Metrics.episodeWidth)
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
            #endif
        }
    }

    private func episodeButton(_ video: Video) -> some View {
        Button {
            choose(video)
        } label: {
            EpisodeCard(video: video)
        }
        #if os(tvOS)
        // Lifts just the still on focus, with the text below it, like the TV app.
        .buttonStyle(.borderless)
        #else
        .buttonStyle(.plain)
        #endif
        .contextMenu { watchedActions(for: video) }
    }

    /// "Season 1 ⌄": the title doubles as the season picker, with the season's marking actions.
    private var seasonMenu: some View {
        Menu {
            Picker("Season", selection: $season) {
                ForEach(Self.seasons(in: videos), id: \.self) { number in
                    Text(Self.seasonName(number)).tag(number)
                }
            }
            .pickerStyle(.inline)
            Section {
                Button("Mark Season as Watched", systemImage: "checkmark.circle") {
                    let items = episodes.filter { $0.isReleased() }.map { route($0).item }
                    library.markWatched(items)
                    trakt.markWatched(items)
                }
                Button("Mark Season as Unwatched", systemImage: "eye.slash") {
                    library.markUnwatched(episodes.map(\.id))
                    trakt.markUnwatched(episodes.map { route($0).item })
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(Self.seasonName(season))
                    .font(.sectionTitle)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        #if os(tvOS)
        .buttonStyle(SeasonMenuStyle())
        #else
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        #endif
        .fixedSize()
        .accessibilityLabel("Season")
        .accessibilityValue(Self.seasonName(season))
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

    private static func seasonName(_ number: Int) -> String {
        number == 0 ? "Specials" : "Season \(number)"
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

#if os(tvOS)
/// The title stays where it is and gains the accent focus platter around it, since a
/// borderless menu shows no focus at all.
private struct SeasonMenuStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? .black : .white)
                .background {
                    Capsule()
                        .fill(.tint)
                        .padding(.horizontal, -20)
                        .padding(.vertical, -6)
                        .opacity(isFocused ? 1 : 0)
                }
                .scaleEffect(isFocused ? 1.04 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
#endif

private struct EpisodeCard: View {
    let video: Video
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let progress = library.progress[video.id]
        VStack(alignment: .leading, spacing: 3) {
            Artwork(url: video.thumbnail)
                .overlay {
                    if let progress {
                        WatchProgressBar(progress: progress)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(.rect(cornerRadius: Metrics.cardRadius))
                .opacity(video.isReleased() ? 1 : 0.5)
                #if os(tvOS)
                .hoverEffect(.highlight)
                #endif
                .padding(.bottom, 9)
            if let caption = caption(progress) {
                Text(caption)
                    .font(Self.captionFont)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            Text(video.displayTitle ?? "Untitled")
                .font(Self.titleFont)
                .lineLimit(2)
            #if !os(tvOS)
            if let overview = video.overview, !overview.isEmpty {
                Text(overview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    #if os(tvOS)
    private static let captionFont = Font.system(size: 17, weight: .semibold)
    private static let titleFont = Font.system(size: 21, weight: .semibold)
    #else
    private static let captionFont = Font.caption.weight(.semibold)
    private static let titleFont = Font.headline
    #endif

    /// "Episode 6 · 17 min left", or when an upcoming episode airs.
    private func caption(_ progress: WatchProgress?) -> String? {
        var parts = [video.episode.map { "Episode \($0)" }]
        if !video.isReleased(), let date = video.releaseDate {
            parts.append("Airs \(date.formatted(.dateTime.day().month()))")
        } else if let progress, !progress.isFinished {
            parts.append("\(max(Int((progress.duration - progress.position) / 60), 1)) min left")
        }
        let kept = parts.compactMap { $0 }
        return kept.isEmpty ? nil : kept.joined(separator: " · ")
    }
}

/// What Play does for a title. Movies play or resume themselves. Series continue where the
/// viewer left off: the unfinished episode, else the one after the last finished, else the first.
@MainActor
struct PlayAction {
    /// "Play", "Resume" or "Resume S1, E6".
    let label: String
    /// Autoplays the remembered source, if there is one.
    let route: SourcesRoute

    /// Nil for a series until its episodes are known.
    init?(preview: MetaPreview, meta: Meta?, library: LibraryStore) {
        guard preview.type == "series" else {
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
