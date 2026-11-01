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
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
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
                #if os(tvOS)
                // Home opens on what's being watched rather than on the sidebar.
                .defaultFocus($focusedID, entries.first?.item.id)
                #endif
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
            // Episode stills are often missing (Cinemeta links one for every episode, aired
            // or not), so a still that fails falls back to the backdrop, then the poster.
            Artwork(url: entry.item.thumbnail ?? entry.item.background,
                    fallbacks: [entry.item.background, entry.item.poster].compactMap { $0 })
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

/// One half of My List, newest first: series, or everything else.
struct MyListRow: View {
    enum Shelf { case series, movies }

    let shelf: Shelf
    var onFocus: (MetaPreview) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library
    @FocusState private var focusedID: MetaPreview.ID?

    var body: some View {
        let titles = shelf == .series ? library.savedSeries : library.savedMovies
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text(shelf == .series ? "My List · Series" : "My List · Movies")
                    .font(.sectionTitle)
                    .padding(.horizontal, Metrics.gutter)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Metrics.rowSpacing) {
                        ForEach(titles) { meta in
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
                if let meta = titles.first(where: { $0.id == focusedID }) {
                    onFocus(meta)
                }
            }
        }
    }
}

/// My List as grids, series first, then the user's own lists in the order they were made.
struct MyListView: View {
    @Environment(LibraryStore.self) private var library
    @State private var renaming: TitleList?
    @State private var name = ""

    var body: some View {
        Group {
            if library.saved.isEmpty && library.lists.isEmpty {
                ContentUnavailableView(
                    "Nothing on My List",
                    systemImage: "plus",
                    description: Text("Add a title with the + button on its page.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        if !library.savedSeries.isEmpty {
                            section(library.savedSeries) { Text("Series") }
                        }
                        if !library.savedMovies.isEmpty {
                            section(library.savedMovies) { Text("Movies") }
                        }
                        ForEach(library.lists) { list in
                            section(list.titles) { listMenu(list) }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .navigationTitle("My List")
        .alert("Rename List", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Rename") {
                if let renaming { library.renameList(renaming.id, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func section(_ titles: [MetaPreview], @ViewBuilder header: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            header()
                .font(.sectionTitle)
                .padding(.horizontal, Metrics.gutter)
            if titles.isEmpty {
                Text("Add titles with the list button on their page.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Metrics.gutter)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing)],
                          spacing: Metrics.rowSpacing) {
                    ForEach(titles) { meta in
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
            }
        }
    }

    /// "Horror ⌄": a list's name doubles as the way to rename or delete it.
    private func listMenu(_ list: TitleList) -> some View {
        Menu {
            Button("Rename…", systemImage: "pencil") {
                name = list.name
                renaming = list
            }
            Button("Delete List", systemImage: "trash", role: .destructive) {
                library.deleteList(list.id)
            }
        } label: {
            HStack(spacing: 6) {
                Text(list.name)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        #if !os(tvOS)
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        #endif
        .fixedSize()
    }
}

/// Puts a title on the user's own lists, or starts a new list with it.
struct ListsMenu: View {
    let title: MetaPreview

    @Environment(LibraryStore.self) private var library
    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        Menu {
            ForEach(library.lists) { list in
                Toggle(list.name, isOn: Binding(
                    get: { library.isInList(title.id, list: list.id) },
                    set: { _ in library.toggle(title, inList: list.id) }
                ))
            }
            Button("New List…", systemImage: "plus") {
                name = ""
                isNaming = true
            }
        } label: {
            // Not a bulleted list: "Choose a Source" sits beside it with one.
            Label("Add to a List", systemImage: "rectangle.stack.badge.plus")
        }
        .menuIndicator(.hidden)
        .buttonStyle(GlassIconButtonStyle())
        .alert("New List", isPresented: $isNaming) {
            TextField("Name", text: $name)
            Button("Create") {
                library.toggle(title, inList: library.createList(named: name))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(title.name) goes on it.")
        }
    }
}
