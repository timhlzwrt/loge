import MediaCore
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
                                Text(Self.title(for: day.day))
                                    .font(.sectionTitle)
                                // Room for the focus lift on tvOS.
                                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                                    ForEach(day.entries, id: \.item.id) { entry in
                                        row(entry)
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
        .navigationTitle("History")
    }

    private func row(_ entry: WatchProgress) -> some View {
        let item = entry.item
        return NavigationLink(value: MetaPreview(
            id: item.metaID, type: item.type, name: item.title, poster: item.poster, background: item.background
        )) {
            HistoryRow(entry: entry)
        }
        #if os(tvOS)
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

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let format = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        return calendar.isDate(day, equalTo: .now, toGranularity: .year)
            ? day.formatted(format)
            : day.formatted(format.year())
    }
}

/// The still beside the title, the episode and how far it got.
private struct HistoryRow: View {
    let entry: WatchProgress

    var body: some View {
        let item = entry.item
        HStack(spacing: Metrics.rowSpacing) {
            Artwork(url: item.thumbnail ?? item.background, fallbacks: [item.background, item.poster].compactMap { $0 })
                .overlay { WatchProgressBar(progress: entry) }
                .frame(width: Metrics.historyStillWidth, height: Metrics.historyStillWidth * 9 / 16)
                .clipShape(.rect(cornerRadius: Metrics.cardRadius))
                #if os(tvOS)
                .hoverEffect(.highlight)
                #endif
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.cardTitle)
                    .lineLimit(1)
                if let episode = episodeLine {
                    Text(episode)
                        .font(.synopsis)
                        .lineLimit(1)
                }
                Text(statusLine)
                    .font(.metaLine)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// "S1 E2 · Trust Fall".
    private var episodeLine: String? {
        let parts = [entry.item.episodeCode, entry.item.episodeTitle].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Watched · 21:14", or "23 min left · 21:14".
    private var statusLine: String {
        let state = entry.isFinished ? "Watched" : "\(max(Int((entry.duration - entry.position) / 60), 1)) min left"
        return "\(state) · \(entry.updatedAt.formatted(date: .omitted, time: .shortened))"
    }
}
