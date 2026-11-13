import LogeCore
import SwiftUI

struct EpisodesSection: View {
    let videos: [Video]
    let upNextID: String?
    /// The series' backdrop, shown for episodes without a still of their own.
    let backdrop: String?
    let route: (Video) -> SourcesRoute
    /// Opens the sources for an episode.
    let choose: (Video) -> Void
    /// Beside another column, where a shelf can't draw past its own edges.
    let staysInColumn: Bool
    @State private var season: Int
    @State private var isConfirmingUnwatched = false
    @Environment(LibraryStore.self) private var library

    init(videos: [Video], upNextID: String?, backdrop: String?, route: @escaping (Video) -> SourcesRoute,
         choose: @escaping (Video) -> Void, staysInColumn: Bool = false) {
        self.videos = videos
        self.upNextID = upNextID
        self.backdrop = backdrop
        self.route = route
        self.choose = choose
        self.staysInColumn = staysInColumn
        // Open on the season being watched, otherwise the first real one rather than specials (season 0).
        let upNextSeason = videos.first { $0.id == upNextID }?.season
        _season = State(initialValue: upNextSeason ?? Self.seasons(in: videos).first ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            seasonMenu
                .padding(.horizontal, Metrics.gutter)
            #if os(macOS)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.episodeWidth), spacing: 18, alignment: .top)],
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
                .scrollClipDisabled(!staysInColumn)
                .onAppear {
                    if let upNextID { proxy.scrollTo(upNextID, anchor: .leading) }
                }
                // A new season starts at its first episode, not where the last one was scrolled to.
                .onChange(of: season) {
                    if let first = episodes.first { proxy.scrollTo(first.id, anchor: .leading) }
                }
            }
            #endif
        }
    }

    private func episodeButton(_ video: Video) -> some View {
        Button {
            choose(video)
        } label: {
            EpisodeCard(video: video, backdrop: backdrop)
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
                    library.markWatched(episodes.filter { $0.isReleased() }.map { route($0).item })
                }
                // Clears the progress of every episode in the season, so it asks first.
                Button("Mark Season as Unwatched", systemImage: "eye.slash") {
                    isConfirmingUnwatched = true
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(Self.seasonName(season))
                    .font(.sectionTitle)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .titleTapTarget()
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
        .confirmationDialog("Mark \(Self.seasonName(season)) as unwatched?", isPresented: $isConfirmingUnwatched,
                            titleVisibility: .visible) {
            Button("Mark as Unwatched", role: .destructive) {
                library.markUnwatched(episodes.map(\.id))
            }
        } message: {
            Text("Progress and watched marks for its episodes are removed.")
        }
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
struct SeasonMenuStyle: ButtonStyle {
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

struct EpisodeCard: View {
    let video: Video
    /// Shown when the episode has no still: addons often leave whole seasons without them.
    var backdrop: String?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let progress = library.progress[video.id]
        VStack(alignment: .leading, spacing: 3) {
            Artwork(url: video.thumbnail, fallbacks: [backdrop].compactMap { $0 })
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
                #else
                .modifier(PointerHighlight())
                #endif
                .padding(.bottom, 9)
            if let caption = caption(progress) {
                Text(caption)
                    .font(.episodeCaption)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            Text(video.displayTitle ?? "Untitled")
                .font(.episodeTitle)
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

    /// "Episode 6 · 17 min left", or when an upcoming episode airs.
    private func caption(_ progress: WatchProgress?) -> String? {
        var parts = [video.episode.map { "Episode \($0)" }]
        if !video.isReleased(), let date = video.releaseDate {
            parts.append("Airs \(date.formatted(.dateTime.day().month().locale(.interface)))")
        } else if let progress, !progress.isFinished {
            parts.append("\(max(Int((progress.duration - progress.position) / 60), 1)) min left")
        }
        let kept = parts.compactMap { $0 }
        return kept.isEmpty ? nil : kept.joined(separator: " · ")
    }
}

/// What Play does for a title. Movies play or resume themselves. Series continue where the
