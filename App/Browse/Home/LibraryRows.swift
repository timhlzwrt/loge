import LogeCore
import SwiftUI

/// Unfinished movies and episodes, most recent first. Selecting one goes straight
/// to its sources, and playback resumes where it stopped.
struct ContinueWatchingRow: View {
    var onFocus: (MetaPreview) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library
    @FocusState private var isFirstFocused: Bool

    var body: some View {
        let entries = library.continueWatching
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Continue Watching")
                    .font(.sectionTitle)
                    .padding(.horizontal, Metrics.gutter)
                HorizontalShelf("Continue Watching") {
                    LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                        ForEach(entries, id: \.item.id) { entry in
                            #if os(tvOS)
                            if entry.item.id == entries.first?.item.id {
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
                // Home opens on what's being watched rather than on the sidebar.
                .defaultFocus($isFirstFocused, true)
                #endif
            }
        }
    }

    private func card(_ entry: WatchProgress) -> some View {
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
            SaveToMenu(title: MetaPreview(
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

/// A watch card that says how much is left.
private struct ContinueWatchingCard: View {
    let entry: WatchProgress

    var body: some View {
        WatchCard(entry: entry, detail: "\(minutesLeft) min left")
            .frame(width: Metrics.cardWidth)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue("\(minutesLeft) minutes left")
    }

    private var minutesLeft: Int {
        max(Int((entry.duration - entry.position) / 60), 1)
    }

    /// "Lanterns, S1 E2, Trust Fall".
    private var accessibilityTitle: String {
        [entry.item.title, entry.item.episodeCode, entry.item.episodeTitle].compactMap { $0 }.joined(separator: ", ")
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

/// Watch Later as a grid, then the user's own lists in the order they were made.
struct MyListView: View {
    @Environment(LibraryStore.self) private var library
    @State private var renaming: TitleList?
    @State private var name = ""

    var body: some View {
        Group {
            if library.saved.isEmpty && library.lists.isEmpty && library.progress.isEmpty {
                ContentUnavailableView(
                    "Nothing saved yet",
                    systemImage: "bookmark",
                    description: Text("Tap Watch Later on a title to save it here, or Lists to start a list of your own.")
                )
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
                            section(library.saved) { Text("Watch Later") }
                        }
                        ForEach(library.lists) { list in
                            section(list.titles) { listMenu(list) }
                        }
                        if !library.progress.isEmpty {
                            historySection
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        #if !os(tvOS)
        .navigationTitle("My Lists")
        #endif
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                header()
                    .font(.sectionTitle)
                Text(titles.count, format: .number)
                    .font(.metaLine)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(titles.count) \(titles.count == 1 ? "title" : "titles")")
            }
            .padding(.horizontal, Metrics.gutter)
            if titles.isEmpty {
                Text("Add titles with the Lists button on their page.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Metrics.gutter)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing)],
                          spacing: Metrics.rowSpacing) {
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
                #endif
            }
        }
    }

    /// The latest history as a row of stills, opening the whole history like a catalog row's "›".
    private var historySection: some View {
        let recent = library.history.prefix(12)
        return VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Group {
                #if os(tvOS)
                // On tvOS the row ends in a "See All" tile instead, which focus reaches naturally.
                Text("History")
                #else
                NavigationLink(value: HistoryRoute()) {
                    HStack(spacing: 4) {
                        Text("History")
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows everything you've watched")
                #endif
            }
            .font(.sectionTitle)
            .padding(.horizontal, Metrics.gutter)
            HorizontalShelf("history") {
                LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                    ForEach(recent, id: \.item.id) { entry in
                        HistoryCardLink(entry: entry, when: HistoryView.dayTitle(entry.updatedAt, short: true))
                            .frame(width: Metrics.historyCardWidth)
                    }
                    #if os(tvOS)
                    NavigationLink(value: HistoryRoute()) {
                        Label("See All", systemImage: "clock")
                            .font(.headline)
                            .frame(width: Metrics.historyCardWidth, height: Metrics.historyCardWidth * 9 / 16)
                            .background(.white.opacity(0.06))
                    }
                    .buttonStyle(.card)
                    #endif
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollClipDisabled()
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
    var isBare = false

    @Environment(LibraryStore.self) private var library
    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        Menu {
            ListMembershipActions(title: title)
            Button("New List…", systemImage: "plus") {
                name = ""
                isNaming = true
            }
        } label: {
            // Not a bulleted list: "Choose a Source" sits beside it with one.
            Label("Save to", systemImage: "rectangle.stack.badge.plus")
        }
        .menuIndicator(.hidden)
        .buttonStyle(GlassIconButtonStyle(isBare: isBare))
        .help("Save to a List")
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

/// A poster's long press uses the same memberships as the detail page's list button.
struct SaveToMenu: View {
    let title: MetaPreview

    var body: some View {
        Menu("Save to", systemImage: "rectangle.stack.badge.plus") {
            ListMembershipActions(title: title)
        }
    }
}

private struct ListMembershipActions: View {
    let title: MetaPreview
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Toggle("Watch Later", isOn: Binding(
            get: { library.isSaved(title.id) },
            set: { _ in library.toggleSaved(title) }
        ))
        ForEach(library.lists) { list in
            Toggle(list.name, isOn: Binding(
                get: { library.isInList(title.id, list: list.id) },
                set: { _ in library.toggle(title, inList: list.id) }
            ))
        }
    }
}
