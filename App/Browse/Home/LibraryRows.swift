import LogeCore
import SwiftUI

/// Unfinished movies and episodes, and episodes that came out since their series was last
/// watched, most recent first. Selecting one goes straight to its sources, and playback
/// resumes where it stopped.
struct ContinueWatchingRow: View {
    var onFocus: (MetaPreview) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library
    @Environment(EpisodeSchedule.self) private var schedule
    @FocusState private var isFirstFocused: Bool

    fileprivate struct Entry: Identifiable {
        let item: WatchItem
        /// Nil for a new episode, which hasn't been started.
        let progress: WatchProgress?
        /// When it was last played, or when it aired.
        let date: Date

        var id: String { item.id }
    }

    private var entries: [Entry] {
        let watching = library.continueWatching.map { Entry(item: $0.item, progress: $0, date: $0.updatedAt) }
        let new = schedule.newEpisodes(in: library).map { Entry(item: $0.item, progress: nil, date: $0.date) }
        return (watching + new).sorted { $0.date > $1.date }
    }

    var body: some View {
        let entries = entries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Continue Watching")
                    .font(.sectionTitle)
                    .padding(.horizontal, Metrics.gutter)
                HorizontalShelf("Continue Watching") {
                    LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                        ForEach(entries) { entry in
                            #if os(tvOS)
                            if entry.id == entries.first?.id {
                                card(entry).focused($isFirstFocused)
                            } else {
                                card(entry)
                            }
                            #else
                            card(entry)
                            #endif
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    #if os(tvOS)
                    // Room for the focus lift, clear of the row's title.
                    .padding(.vertical, 20)
                    #endif
                }
                .scrollClipDisabled()
                #if os(tvOS)
                // Home opens on what's being watched rather than on the tab bar.
                .defaultFocus($isFirstFocused, true)
                #endif
            }
        }
    }

    private func card(_ entry: Entry) -> some View {
        NavigationLink(value: SourcesRoute(item: entry.item, title: title(for: entry.item), autoplay: true)) {
            ContinueWatchingCard(entry: entry)
                #if os(tvOS)
                .modifier(ReportsFocus {
                    let item = entry.item
                    onFocus(MetaPreview(id: item.metaID, type: item.type, name: item.title,
                                        poster: item.poster, background: item.background))
                })
                #endif
        }
        #if os(tvOS)
        .buttonStyle(.borderless)
        #else
        .buttonStyle(.plain)
        #endif
        .contextMenu {
            WatchLaterToggle(title: MetaPreview(
                id: entry.item.metaID, type: entry.item.type, name: entry.item.title,
                poster: entry.item.poster, background: entry.item.background))
            Button("Remove from Continue Watching", systemImage: "eye.slash") {
                library.removeFromContinueWatching(metaID: entry.item.metaID)
            }
        }
    }

    private func title(for item: WatchItem) -> String {
        item.episodeCode.map { "\(item.title) · \($0)" } ?? item.title
    }
}

/// A watch card that says how much is left, or that the episode is new.
private struct ContinueWatchingCard: View {
    let entry: ContinueWatchingRow.Entry

    var body: some View {
        let minutesLeft = entry.progress.map { max(Int(($0.duration - $0.position) / 60), 1) }
        WatchCard(item: entry.item, progress: entry.progress,
                  detail: minutesLeft.map { "\($0) min left" } ?? "New episode")
            .frame(width: Metrics.cardWidth)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(minutesLeft.map { "\($0) minutes left" } ?? "New episode")
    }

    /// "Lanterns, S1 E2, Trust Fall".
    private var accessibilityTitle: String {
        [entry.item.title, entry.item.episodeCode, entry.item.episodeTitle].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Something started, or a new episode, in Continue Watching. Laid out like
/// the episode cards on a title's page, with the show's name added.
struct WatchCard: View {
    let item: WatchItem
    /// Nil draws no bar or checkmark: for an episode that hasn't been started, and in Recently
    /// Watched, where everything is finished.
    var progress: WatchProgress?
    /// After the episode in the caption: how much is left, that the episode is new, or when it was finished.
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Stills are often missing, so a still that fails falls back to the backdrop, then the poster.
            Artwork(url: item.thumbnail ?? item.background, fallbacks: [item.background, item.poster].compactMap { $0 })
                .overlay { if let progress { WatchProgressBar(progress: progress) } }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(.rect(cornerRadius: Metrics.cardRadius))
                #if os(tvOS)
                .hoverEffect(.highlight)
                // Clear of the focus lift.
                .padding(.bottom, 18)
                #else
                .modifier(PointerHighlight())
                .padding(.bottom, 9)
                #endif
            Text([item.episodeCode, detail].compactMap { $0 }.joined(separator: " · "))
                .font(.episodeCaption)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.episodeTitle)
                .lineLimit(1)
            if let episodeTitle = item.episodeTitle {
                Text(episodeTitle)
                    .font(.metaLine)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Otherwise cards in a row share its height, and those with less text get a larger still.
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Watch Later, newest first, series and movies together as they were saved.
struct MyListRow: View {
    var onFocus: (MetaPreview) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library

    var body: some View {
        let titles = library.saved
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Watch Later")
                    .font(.sectionTitle)
                    .padding(.horizontal, Metrics.gutter)
                HorizontalShelf("Watch Later") {
                    LazyHStack(spacing: Metrics.rowSpacing) {
                        ForEach(titles) { meta in
                            NavigationLink(value: meta) {
                                PosterTile(meta: meta)
                                    #if os(tvOS)
                                    .modifier(ReportsFocus { onFocus(meta) })
                                    #endif
                            }
                            .tileButtonStyle()
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    #if os(tvOS)
                    .padding(.vertical, 20)
                    #endif
                }
                .scrollClipDisabled()
            }
        }
    }
}

/// Watch Later as a grid, then what was finished lately.
struct MyListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(EpisodeSchedule.self) private var schedule

    var body: some View {
        let recent = library.recentlyWatched(excluding: Set(schedule.newEpisodes(in: library).map(\.item.metaID)))
        Group {
            if library.saved.isEmpty && recent.isEmpty {
                // Said like Settings: grey words, low on a phone where the thumb is, the glow above.
                Sentence {
                    Words("Nothing saved yet. Choose")
                    Text("Watch Later")
                    Words("on a title to keep it here.")
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: Metrics.isPhone ? .bottomLeading : .leading)
                #if os(tvOS)
                // With nothing to focus, the remote can't reach the tab menu and Menu leaves the app.
                .focusable()
                #endif
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        #if os(tvOS)
                        // Lined up with the rows; the system's title is centred. The padding clears the tab menu.
                        Text("My Lists")
                            .font(.system(size: 57, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 60)
                        #endif
                        if !library.saved.isEmpty {
                            section(library.saved)
                        }
                        if !recent.isEmpty {
                            RecentlyWatchedRow(entries: recent)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PageGlow() }
        #if !os(tvOS)
        .navigationTitle("My Lists")
        #endif
    }

    private func section(_ titles: [MetaPreview]) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Watch Later")
                    .font(.sectionTitle)
                Text(titles.count, format: .number.locale(.interface))
                    .font(.metaLine)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(titles.count) \(titles.count == 1 ? "title" : "titles")")
            }
            .padding(.horizontal, Metrics.gutter)
            LazyVGrid(columns: Metrics.posterGridColumns, spacing: Metrics.rowSpacing) {
                ForEach(titles) { meta in
                    NavigationLink(value: meta) {
                        PosterTile(meta: meta, width: nil)
                    }
                    .tileButtonStyle()
                }
            }
            .padding(.horizontal, Metrics.gutter)
            #if os(tvOS)
            // Room for the focus lift, clear of the section's title.
            .padding(.top, 20)
            // Across the full width, so a short list isn't skipped moving down from the tabs.
            .focusSection()
            #endif
        }
    }
}

/// The titles finished most recently, each opening its page. Removing one only hides it here.
private struct RecentlyWatchedRow: View {
    let entries: [WatchProgress]

    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text("Recently Watched")
                .font(.sectionTitle)
                .padding(.horizontal, Metrics.gutter)
            HorizontalShelf("Recently Watched") {
                LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                    ForEach(entries, id: \.item.metaID) { entry in
                        card(entry.item, finishedAt: entry.updatedAt)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                #if os(tvOS)
                // Room for the focus lift, clear of the row's title.
                .padding(.vertical, 20)
                #endif
            }
            .scrollClipDisabled()
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    private func card(_ item: WatchItem, finishedAt date: Date) -> some View {
        let day = Self.day(date)
        return NavigationLink(value: MetaPreview(id: item.metaID, type: item.type, name: item.title,
                                                 poster: item.poster, background: item.background)) {
            // Episodes lead with their code, so only a film says what the date is.
            WatchCard(item: item, detail: item.episodeCode == nil ? "Finished \(day)" : day)
                .frame(width: Metrics.cardWidth)
        }
        #if os(tvOS)
        .buttonStyle(.borderless)
        #else
        .buttonStyle(.plain)
        #endif
        .contextMenu {
            Button("Remove from Recently Watched", systemImage: "eye.slash") {
                library.hideFromRecentlyWatched(metaID: item.metaID)
            }
        }
    }

    /// "Today", "Yesterday", "Oct 24", or "Oct 24, 2025" before this year.
    private static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let style = Date.FormatStyle.dateTime.day().month().locale(.interface)
        return date.formatted(calendar.isDate(date, equalTo: .now, toGranularity: .year) ? style : style.year())
    }
}

/// A poster's long press adds the title to Watch Later or takes it off.
struct WatchLaterToggle: View {
    let title: MetaPreview
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let isSaved = library.isSaved(title.id)
        Button(isSaved ? "Remove from Watch Later" : "Add to Watch Later",
               systemImage: isSaved ? "checkmark" : "plus") {
            library.toggleSaved(title)
        }
    }
}
