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
                    .font(.sectionTitle)
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

/// The still with its title over it; the progress bar says how far along it is.
private struct ContinueWatchingCard: View {
    let entry: WatchProgress
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Artwork(url: entry.item.thumbnail ?? entry.item.background)
                .overlay {
                    // Keeps the title legible over bright stills.
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(entry.item.title)
                        .font(.cardTitle)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 1)
                        .padding(.horizontal, WatchProgressBar.inset)
                        .padding(.bottom, WatchProgressBar.inset * 0.75 + WatchProgressBar.height + 6)
                }
                .overlay { WatchProgressBar(progress: entry) }
                .frame(width: Metrics.cardWidth, height: Metrics.cardWidth * 9 / 16)
                .clipShape(.rect(cornerRadius: Metrics.cardRadius))
                #if os(tvOS)
                .hoverEffect(.highlight)
                #endif
            #if os(tvOS)
            // Only the focused card says how long is left; the space is kept so the row doesn't jump.
            Text("\(minutesLeft) min left")
                .font(.metaLine)
                .foregroundStyle(.secondary)
                .opacity(isFocused ? 1 : 0)
                .padding(.top, 8)
            #endif
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue("\(minutesLeft) minutes left")
    }

    private var minutesLeft: Int {
        max(Int((entry.duration - entry.position) / 60), 1)
    }

    /// "Lanterns, S1 E2, Trust Fall": the card shows only the title, but which episode matters.
    private var accessibilityTitle: String {
        [entry.item.title, entry.item.episodeCode, entry.item.episodeTitle].compactMap { $0 }.joined(separator: ", ")
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
                    .font(.sectionTitle)
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

/// Everything on My List as a grid, newest first.
struct MyListView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Group {
            if library.saved.isEmpty {
                ContentUnavailableView(
                    "Nothing on My List",
                    systemImage: "plus",
                    description: Text("Add a title with the + button on its page.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing)],
                              spacing: Metrics.rowSpacing) {
                        ForEach(library.saved) { meta in
                            NavigationLink(value: meta) {
                                PosterTile(meta: meta, width: nil)
                            }
                            #if os(tvOS)
                            .buttonStyle(.card)
                            #else
                            .buttonStyle(.plain)
                            #endif
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
        .navigationTitle("My List")
    }
}
