import LogeCore
import SwiftUI

/// Opens History. Pushed as a value like the other routes: a title link inside a screen
/// pushed by a destination link doesn't navigate.
struct HistoryRoute: Hashable {}

/// Everything played or marked watched on this device or synced from Trakt, by day,
/// newest first. Selecting an entry opens its title, where Play picks up from there.
struct HistoryView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let days = Self.days(library.history)
        Group {
            if days.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock",
                    description: Text("Movies and episodes you play show up here.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(days, id: \.day) { day in
                            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                                Text(Self.dayTitle(day.day))
                                    .font(.sectionTitle)
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: Metrics.historyCardWidth), spacing: Metrics.rowSpacing,
                                   alignment: .top)],
                                    alignment: .leading, spacing: 28
                                ) {
                                    ForEach(day.entries, id: \.item.id) { entry in
                                        HistoryCardLink(entry: entry, when: entry.updatedAt.formatted(date: .omitted, time: .shortened))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 24)
                }
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .pageTitle("History")
    }

    /// Entries are already newest first, so each day's run of them stays together.
    private static func days(_ history: [WatchProgress]) -> [(day: Date, entries: [WatchProgress])] {
        var days: [(day: Date, entries: [WatchProgress])] = []
        for entry in history {
            let day = Calendar.current.startOfDay(for: entry.updatedAt)
            if days.last?.day == day {
                days[days.count - 1].entries.append(entry)
            } else {
                days.append((day, [entry]))
            }
        }
        return days
    }

    /// "Today", "Yesterday", "Saturday, October 24"; short drops the weekday, for card captions.
    static func dayTitle(_ date: Date, short: Bool = false) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        var format = short ? Date.FormatStyle.dateTime.day().month(.abbreviated) : .dateTime.weekday(.wide).day().month(.wide)
        if !calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            format = format.year()
        }
        return date.formatted(format.locale(.interface))
    }
}

/// A history entry that opens its title, with removal on a long press.
struct HistoryCardLink: View {
    let entry: WatchProgress
    /// When it was watched, in the caption: a time within a day's group, a day elsewhere.
    let when: String

    @Environment(LibraryStore.self) private var library

    var body: some View {
        let item = entry.item
        NavigationLink(value: MetaPreview(
            id: item.metaID, type: item.type, name: item.title, poster: item.poster, background: item.background
        )) {
            WatchCard(entry: entry, detail: when)
        }
        #if os(tvOS)
        // Lifts just the still on focus, with the text below it, like the episode cards.
        .buttonStyle(.borderless)
        #else
        .buttonStyle(.plain)
        #endif
        .contextMenu {
            // Also clears the watched mark: history is the same progress that marks it.
            Button("Remove from History", systemImage: "eye.slash") {
                library.markUnwatched([item.id])
            }
        }
    }
}

/// Something started or watched, in History and Continue Watching. Laid out like the
/// episode cards on a title's page, with the show's name added.
struct WatchCard: View {
    let entry: WatchProgress
    /// After the episode in the caption: when it was watched, or how much is left.
    let detail: String

    var body: some View {
        let item = entry.item
        VStack(alignment: .leading, spacing: 3) {
            // Stills are often missing, so a still that fails falls back to the backdrop, then the poster.
            Artwork(url: item.thumbnail ?? item.background, fallbacks: [item.background, item.poster].compactMap { $0 })
                .overlay { WatchProgressBar(progress: entry) }
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
