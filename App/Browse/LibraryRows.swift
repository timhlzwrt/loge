import MediaCore
import SwiftUI

/// Unfinished movies and episodes, most recent first. Selecting one goes straight
/// to its sources, and playback resumes where it stopped.
struct ContinueWatchingRow: View {
    var onFocus: (MetaPreview) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library
    @FocusState private var focusedID: String?

    var body: some View {
        let entries = library.continueWatching
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                Text("Continue Watching")
                    .font(.headline)
                    .padding(.horizontal, Metrics.gutter)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                        ForEach(entries, id: \.item.id) { entry in
                            NavigationLink(value: SourcesRoute(item: entry.item, title: title(for: entry.item), autoplay: true)) {
                                ContinueWatchingCard(entry: entry)
                            }
                            #if os(tvOS)
                            .buttonStyle(.borderless)
                            #else
                            .buttonStyle(.plain)
                            #endif
                            .focused($focusedID, equals: entry.item.id)
                            .contextMenu {
                                Button("Remove from Continue Watching", systemImage: "eye.slash") {
                                    library.removeFromContinueWatching(metaID: entry.item.metaID)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .onChange(of: focusedID) {
                if let item = entries.first(where: { $0.item.id == focusedID })?.item {
                    onFocus(MetaPreview(id: item.metaID, type: item.type, name: item.title, poster: item.poster, background: item.background))
                }
            }
        }
    }

    private func title(for item: WatchItem) -> String {
        item.episodeCode.map { "\(item.title) · \($0)" } ?? item.title
    }
}

private struct ContinueWatchingCard: View {
    let entry: WatchProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: entry.item.thumbnail ?? entry.item.background)
                .overlay(alignment: .bottom) { WatchProgressBar(progress: entry) }
                .frame(width: Metrics.episodeWidth, height: Metrics.episodeWidth * 9 / 16)
                .clipShape(.rect(cornerRadius: 8))
                #if os(tvOS)
                .hoverEffect(.highlight)
                #endif
            Text(entry.item.title)
                .font(.subheadline)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: Metrics.episodeWidth, alignment: .leading)
    }

    /// "S1 E2 · Trust Fall · 31 min left", or just the time left for movies.
    private var subtitle: String {
        let minutesLeft = max(Int((entry.duration - entry.position) / 60), 1)
        return [entry.item.episodeCode, entry.item.episodeTitle, "\(minutesLeft) min left"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// Titles the user added with the My List button, newest first.
struct MyListRow: View {
    var onFocus: (MetaPreview) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library
    @FocusState private var focusedID: MetaPreview.ID?

    var body: some View {
        if !library.saved.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                Text("My List")
                    .font(.headline)
                    .padding(.horizontal, Metrics.gutter)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Metrics.rowSpacing) {
                        ForEach(library.saved) { meta in
                            NavigationLink(value: meta) {
                                PosterTile(meta: meta)
                            }
                            #if os(tvOS)
                            .buttonStyle(.card)
                            #else
                            .buttonStyle(.plain)
                            #endif
                            .focused($focusedID, equals: meta.id)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    #if os(tvOS)
                    .padding(.vertical, 20)
                    #endif
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .onChange(of: focusedID) {
                if let meta = library.saved.first(where: { $0.id == focusedID }) {
                    onFocus(meta)
                }
            }
        }
    }
}
