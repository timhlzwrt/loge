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
                                SaveToMenu(meta: MetaPreview(
                                    id: entry.item.metaID, type: entry.item.type, name: entry.item.title,
                                    poster: entry.item.poster, background: entry.item.background))
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

/// The default saved list, newest additions first.
struct MyListRow: View {
    var onFocus: (MetaPreview) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library
    @FocusState private var focusedID: MetaPreview.ID?

    var body: some View {
        if !library.saved.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Watch Later")
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

/// Saved collections, with Watch Later retaining titles saved by earlier versions.
struct MyListView: View {
    @Environment(LibraryStore.self) private var library
    @State private var selectedID = LibraryStore.watchLaterID
    @State private var editor: ListEditor?
    @State private var confirmingDelete = false

    private var selected: SavedList {
        library.lists.first { $0.id == selectedID } ?? library.lists[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("List", selection: $selectedID) {
                ForEach(library.lists) { list in
                    Text(list.name).tag(list.id)
                }
            }
            .padding(.horizontal, Metrics.gutter)

            if selected.titles.isEmpty {
                ContentUnavailableView(
                    "Nothing in \(selected.name)",
                    systemImage: "text.badge.plus",
                    description: Text("Hold a poster to save it to a list. The + button saves to Watch Later.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing)],
                              spacing: Metrics.rowSpacing) {
                        ForEach(selected.titles) { meta in
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
        .navigationTitle("My Lists")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("New List", systemImage: "plus") {
                        editor = ListEditor(listID: nil, name: "")
                    }
                    if selected.id != LibraryStore.watchLaterID {
                        Button("Rename List", systemImage: "pencil") {
                            editor = ListEditor(listID: selected.id, name: selected.name)
                        }
                        Button("Delete List", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                } label: {
                    Label("Manage Lists", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editor) { editor in
            SavedListEditor(listID: editor.listID, name: editor.name) { id in
                selectedID = id
            }
        }
        .alert("Delete \(selected.name)?", isPresented: $confirmingDelete) {
            Button("Delete List", role: .destructive) {
                library.deleteList(selected.id)
                selectedID = LibraryStore.watchLaterID
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Titles saved to other lists will stay there. Watch history is kept.")
        }
    }

    private struct ListEditor: Identifiable {
        let id = UUID()
        let listID: String?
        let name: String
    }
}

private struct SavedListEditor: View {
    let listID: String?
    @State var name: String
    var onSaved: (String) -> Void
    @State private var hasError = false
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("List name", text: $name)
                    .onSubmit(save)
                if hasError {
                    Text("Enter a name that isn't already used by another list.")
                        .foregroundStyle(.red)
                }
                Button("Save", action: save)
                #if os(tvOS)
                Button("Cancel", role: .cancel) { dismiss() }
                #endif
            }
            #if os(macOS)
            .padding(20)
            #endif
            .navigationTitle(listID == nil ? "New List" : "Rename List")
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(width: 440, height: 260)
        #endif
    }

    private func save() {
        if let listID {
            guard library.renameList(listID, to: name) else {
                hasError = true
                return
            }
            onSaved(listID)
        } else {
            guard let id = library.createList(name: name) else {
                hasError = true
                return
            }
            onSaved(id)
        }
        dismiss()
    }
}
