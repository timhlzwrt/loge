import LogeCore
import SwiftUI

/// What a title offers besides Play and Watch Later, behind one button so the two stand
/// alone: its trailer, the sources list, the user's lists and, for a movie, the watched mark.
struct TitleMoreMenu: View {
    /// What the lists keep.
    let title: MetaPreview
    let trailer: URL?
    /// Nil until there's something to play.
    let chooseSource: (() -> Void)?
    /// Nil for a series, which is marked by season or episode.
    let movie: WatchItem?

    @Environment(LibraryStore.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        Menu {
            if let trailer {
                Button("Watch Trailer", systemImage: "play.rectangle") { openURL(trailer) }
            }
            if let chooseSource {
                Button("Choose a Source", systemImage: "list.bullet", action: chooseSource)
            }
            Section("Save to") {
                ListMembershipActions(title: title)
                Button("New List…", systemImage: "plus") {
                    name = ""
                    isNaming = true
                }
            }
            if let movie {
                Section { WatchedMarkButton(item: movie) }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
        // The icon-only style leaves the menu without a name of its own.
        .accessibilityLabel("More")
        #if os(tvOS)
        .buttonStyle(GlassIconButtonStyle(caption: "More"))
        #else
        .buttonStyle(GlassIconButtonStyle())
        #endif
        .help("More")
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

/// Marks a movie watched without playing it, or takes the mark and its progress away.
struct WatchedMarkButton: View {
    let item: WatchItem
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if library.isWatched(item.id) {
            Button("Mark as Unwatched", systemImage: "eye.slash") {
                library.markUnwatched([item.id])
            }
        } else {
            Button("Mark as Watched", systemImage: "checkmark.circle") {
                library.markWatched([item])
            }
        }
    }
}
