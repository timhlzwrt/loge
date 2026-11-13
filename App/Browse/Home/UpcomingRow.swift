import LogeCore
import SwiftUI

/// The next episode of each series being watched that hasn't aired yet, soonest first.
/// There's nothing to play, so selecting one opens its series.
struct UpcomingRow: View {
    var onFocus: (MetaPreview) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library
    @Environment(EpisodeSchedule.self) private var schedule

    var body: some View {
        let episodes = schedule.upcoming(in: library)
        if !episodes.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Upcoming")
                    .font(.sectionTitle)
                    .padding(.horizontal, Metrics.gutter)
                HorizontalShelf("Upcoming") {
                    LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                        ForEach(episodes) { episode in
                            let item = episode.item
                            let series = MetaPreview(id: item.metaID, type: item.type, name: item.title,
                                                     poster: item.poster, background: item.background)
                            NavigationLink(value: series) {
                                WatchCard(item: item, detail: HistoryView.dayTitle(episode.date, short: true))
                                    .frame(width: Metrics.historyCardWidth)
                                    #if os(tvOS)
                                    .modifier(ReportsFocus { onFocus(series) })
                                    #endif
                            }
                            #if os(tvOS)
                            .buttonStyle(.borderless)
                            #else
                            .buttonStyle(.plain)
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
            }
        }
    }
}
