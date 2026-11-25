import LogeCore
import SwiftUI

struct EpisodesSection: View {
    let videos: [Video]
    let upNextID: String?
    /// The series' backdrop, shown for episodes without a still of their own.
    let backdrop: String?
    /// The series' usual episode length, "49 min", for a phone's episode rows.
    let runtime: String?
    let route: (Video) -> SourcesRoute
    /// Opens the sources for an episode.
    let choose: (Video) -> Void
    @State private var season: Int
    @State private var isConfirmingUnwatched = false
    #if os(tvOS)
    /// The pills above the episodes take focus only once an episode has had it, so one press
    /// down from Play lands on the episodes; up from the pills goes back to Play.
    @State private var pillsReachable = false
    #endif
    @Environment(LibraryStore.self) private var library

    init(videos: [Video], upNextID: String?, backdrop: String?, runtime: String?,
         route: @escaping (Video) -> SourcesRoute, choose: @escaping (Video) -> Void) {
        self.videos = videos
        self.upNextID = upNextID
        self.backdrop = backdrop
        self.runtime = runtime
        self.route = route
        self.choose = choose
        // Open on the season being watched, otherwise the first real one rather than specials (season 0).
        let upNextSeason = videos.first { $0.id == upNextID }?.season
        _season = State(initialValue: upNextSeason ?? Self.seasons(in: videos).first ?? 0)
    }

    var body: some View {
        Group {
            #if os(tvOS)
            shelf
            #else
            list
            #endif
        }
        .confirmationDialog("Mark \(Self.seasonName(season)) as unwatched?", isPresented: $isConfirmingUnwatched,
                            titleVisibility: .visible) {
            Button("Mark as Unwatched", role: .destructive) {
                library.markUnwatched(episodes.map(\.id))
            }
        } message: {
            Text("Progress and watched marks for its episodes are removed.")
        }
    }

    #if !os(tvOS)
    /// Seasons as a row of pills over the season's episodes, one per row.
    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.seasons(in: videos), id: \.self) { number in
                        Button(Self.seasonName(number)) { season = number }
                            .buttonStyle(PillButtonStyle(isSelected: number == season))
                            // Long-pressing a season selects it and offers its marks.
                            .contextMenu { seasonActions(number) }
                    }
                }
            }
            .contentMargins(.horizontal, Metrics.gutter, for: .scrollContent)
            .scrollIndicators(.hidden)
            .padding(.bottom, 4)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(episodes) { video in
                    Button { choose(video) } label: {
                        EpisodeRow(video: video, backdrop: backdrop, runtime: runtime)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { watchedActions(for: video) }
                }
            }
        }
    }

    #else
    /// Apple TV's: season pills over a shelf of episode cards, scrolled to the one up next.
    private var shelf: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            HStack(spacing: 14) {
                ForEach(Self.seasons(in: videos), id: \.self) { number in
                    Button(Self.seasonName(number)) { season = number }
                        .buttonStyle(PillButtonStyle(isSelected: number == season))
                        .fixedSize()
                        .disabled(!pillsReachable)
                        .onMoveCommand { if $0 == .up { pillsReachable = false } }
                        .contextMenu { seasonActions(number) }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .focusSection()
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                        ForEach(episodes) { video in
                            Button { choose(video) } label: {
                                EpisodeCard(video: video, backdrop: backdrop, runtime: runtime)
                                    .modifier(ReportsFocus { pillsReachable = true })
                            }
                            // Lifts just the still on focus, with the text below it, like the TV app.
                            .buttonStyle(.borderless)
                            .contextMenu { watchedActions(for: video) }
                            .frame(width: Metrics.episodeWidth)
                            .id(video.id)
                        }
                    }
                    .padding(.vertical, 20)
                }
                // Margins rather than padding, so scrolling to Up Next keeps the inset.
                .contentMargins(.horizontal, Metrics.gutter, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .onAppear {
                    if let upNextID { proxy.scrollTo(upNextID, anchor: .leading) }
                }
                // A new season starts at its first episode, not where the last one was scrolled to.
                .onChange(of: season) {
                    if let first = episodes.first { proxy.scrollTo(first.id, anchor: .leading) }
                }
            }
            .focusSection()
        }
    }
    #endif

    /// A season's marks; clearing them asks first, as it clears their progress.
    @ViewBuilder
    private func seasonActions(_ number: Int) -> some View {
        Button("Mark Season as Watched", systemImage: "checkmark.circle") {
            season = number
            library.markWatched(episodes(in: number).filter { $0.isReleased() }.map { route($0).item })
        }
        Button("Mark Season as Unwatched", systemImage: "eye.slash") {
            season = number
            isConfirmingUnwatched = true
        }
    }

    /// "31 min left", when an upcoming episode airs, or the series' usual length.
    static func timeLine(for video: Video, progress: WatchProgress?, runtime: String?) -> String? {
        if !video.isReleased(), let date = video.releaseDate {
            return "Airs \(date.formatted(.dateTime.day().month().locale(.interface)))"
        }
        if let progress, !progress.isFinished {
            return "\(max(Int((progress.duration - progress.position) / 60), 1)) min left"
        }
        return runtime
    }

    @ViewBuilder
    private func watchedActions(for video: Video) -> some View {
        if library.isWatched(video.id) {
            Button("Mark as Unwatched", systemImage: "eye.slash") {
                library.markUnwatched([video.id])
            }
        } else {
            Button("Mark as Watched", systemImage: "checkmark.circle") {
                library.markWatched([route(video).item])
            }
        }
    }

    private var episodes: [Video] {
        episodes(in: season)
    }

    private func episodes(in season: Int) -> [Video] {
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

#if !os(tvOS)
/// An episode: its still on the left with the progress over it, the number and title, and how
/// much is left; a check once it's watched. Wider screens add the episode's summary.
private struct EpisodeRow: View {
    let video: Video
    let backdrop: String?
    let runtime: String?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let progress = library.progress[video.id]
        let isWatched = progress?.isFinished == true
        HStack(alignment: .top, spacing: 14) {
            Artwork(url: video.thumbnail, fallbacks: [backdrop].compactMap { $0 })
                .overlay {
                    if let progress, !isWatched { WatchProgressBar(progress: progress, inset: 7) }
                }
                .frame(width: Self.stillWidth, height: Self.stillWidth * 9 / 16)
                .modifier(PointerHighlight())
                .clipShape(.rect(cornerRadius: 9))
                .brightness(isWatched ? -0.25 : 0)
                .opacity(video.isReleased() ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 3) {
                Text([video.episode.map { "\($0)." }, video.displayTitle ?? "Untitled"].compactMap { $0 }.joined(separator: " "))
                    .font(Metrics.isPhone ? .subheadline.weight(.semibold) : .headline)
                    .lineLimit(2)
                if !Metrics.isPhone, let overview = video.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
                if let detail = detail(progress) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            if isWatched {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black, .white.opacity(0.85))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        // Read as the cards on wider screens are: "Episode 4, Woe's Hollow".
        .accessibilityLabel([video.episode.map { "Episode \($0)" }, video.displayTitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue([isWatched ? "Watched" : nil, detail(progress)].compactMap { $0 }.joined(separator: ", "))
    }

    private func detail(_ progress: WatchProgress?) -> String? {
        EpisodesSection.timeLine(for: video, progress: progress, runtime: runtime)
    }

    private static let stillWidth: CGFloat = Metrics.isPhone ? 132 : 200
}
#endif

#if os(tvOS)
/// An episode on Apple TV: its still with the progress over it, "4. Woe's Hollow", and how much
/// is left, that it's watched, or its length.
struct EpisodeCard: View {
    let video: Video
    /// Shown when the episode has no still: addons often leave whole seasons without them.
    var backdrop: String?
    let runtime: String?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let progress = library.progress[video.id]
        let isWatched = progress?.isFinished == true
        let detail = isWatched ? "Watched" : EpisodesSection.timeLine(for: video, progress: progress, runtime: runtime)
        VStack(alignment: .leading, spacing: 4) {
            Artwork(url: video.thumbnail, fallbacks: [backdrop].compactMap { $0 })
                .overlay {
                    if let progress, !isWatched { WatchProgressBar(progress: progress) }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(.rect(cornerRadius: Metrics.cardRadius))
                .brightness(isWatched ? -0.25 : 0)
                .opacity(video.isReleased() ? 1 : 0.5)
                .hoverEffect(.highlight)
                // Clear of the focus lift, as in Continue Watching.
                .padding(.bottom, 18)
            Text([video.episode.map { "\($0)." }, video.displayTitle ?? "Untitled"].compactMap { $0 }.joined(separator: " "))
                .font(.episodeTitle)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.metaLine)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([video.episode.map { "Episode \($0)" }, video.displayTitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(detail ?? "")
    }
}
#endif

/// What Play does for a title. Movies play or resume themselves. Series continue where the
