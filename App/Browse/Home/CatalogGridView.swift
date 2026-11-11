import LogeCore
import SwiftUI

/// A whole catalog as a grid, loading further pages as it scrolls and, where the
/// addon supports it, filtered by genre (or year) and sorted by switching to a sibling catalog.
struct CatalogGridView: View {
    let source: CatalogSource

    @Environment(AddonStore.self) private var store
    @State private var sortOptions: [AddonManifest.Catalog] = []
    @State private var sortID: String
    @State private var genre: String?
    @State private var items: [MetaPreview] = []
    @State private var phase = Phase.loading
    @State private var reachedEnd = false
    @State private var loadGeneration = UUID()
    #if os(tvOS)
    /// Only the first poster is bound to focus, as in `CatalogRow`. The grid opens empty, so
    /// focus starts on the Sort and Genre buttons and has to be brought down once titles arrive.
    @FocusState private var isFirstFocused: Bool
    @State private var hasPlacedFocus = false
    #endif

    private enum Phase: Equatable {
        case loading, idle, failed
    }

    init(source: CatalogSource) {
        self.source = source
        _sortID = State(initialValue: source.catalog.id)
    }

    private var catalog: AddonManifest.Catalog {
        sortOptions.first { $0.id == sortID } ?? source.catalog
    }

    /// The catalog being shown, which keeps a genre the source is fixed to.
    private var shown: CatalogSource {
        catalog.id == source.catalog.id
            ? source
            : CatalogSource(manifestURL: source.manifestURL, catalog: catalog, genre: source.defaultGenre)
    }

    private var title: String {
        let base = catalog.id == source.catalog.id ? source.title : shown.title
        let filter = catalog.id == source.catalog.id ? genre : genre ?? source.defaultGenre
        return filter.map { "\(base) · \($0)" } ?? base
    }

    private struct Filter: Hashable {
        let sortID: String
        let genre: String?
    }

    var body: some View {
        content
            .background(Color.canvas)
            .pageTitle(title)
            #if !os(tvOS)
            .toolbar {
                if !sortOptions.isEmpty {
                    ToolbarItem {
                        sortMenu
                    }
                }
                if hasGenres {
                    ToolbarItem {
                        genreMenu
                    }
                }
            }
            #endif
            .task { await loadSortOptions() }
            .task(id: Filter(sortID: sortID, genre: genre)) {
                loadGeneration = UUID()
                items = []
                reachedEnd = false
                phase = .idle
                await loadNextPage()
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
        VStack(spacing: 0) {
            if !sortOptions.isEmpty || hasGenres {
                // In a toolbar these sit in the top right corner, where Up only reaches them
                // from the last columns. A section as wide as the grid takes focus from any column.
                HStack(spacing: 20) {
                    if !sortOptions.isEmpty { sortMenu }
                    if hasGenres { genreMenu }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 24)
                .focusSection()
                // Posters lift and scroll past the grid's top edge, and would cross the buttons.
                .background { Color.canvas.ignoresSafeArea(edges: .horizontal) }
                .zIndex(1)
            }
            grid
        }
        #else
        grid
        #endif
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing)],
                      spacing: Metrics.rowSpacing) {
                ForEach(items) { meta in
                    #if os(tvOS)
                    if meta.id == items.first?.id {
                        tile(meta).focused($isFirstFocused)
                    } else {
                        tile(meta)
                    }
                    #else
                    tile(meta)
                    #endif
                }
            }
            .padding(.horizontal, Metrics.gutter)
            #if os(tvOS)
            // Room for the first row's focus lift under the buttons.
            .padding(.top, 20)
            #endif
            footer
                .padding(.vertical, 24)
        }
        .scrollClipDisabled()
        // A new filter is a new list, so it starts from the top.
        .id(Filter(sortID: sortID, genre: genre))
    }

    private var hasGenres: Bool {
        source.defaultGenre == nil && !catalog.genres.isEmpty
    }

    private func tile(_ meta: MetaPreview) -> some View {
        NavigationLink(value: meta) {
            PosterTile(meta: meta, width: nil)
        }
        .tileButtonStyle()
        .onAppear {
            // Start the next page a little before the end comes into view.
            if meta.id == items.dropLast(6).last?.id || meta.id == items.last?.id {
                Task { await loadNextPage() }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: Binding(get: { sortID }, set: sort)) {
                ForEach(sortOptions, id: \.id) { Text($0.name ?? $0.id).tag($0.id) }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    /// Catalogs differ in their genres, and Cinemeta's "New" lists years and needs one, so
    /// the genre changes along with the catalog rather than in a second load.
    private func sort(by id: String) {
        sortID = id
        if let genre, !catalog.genres.contains(genre) { self.genre = nil }
        if genre == nil, source.defaultGenre == nil, catalog.requiresGenre { genre = catalog.genres.first }
    }

    private var genreMenu: some View {
        let noun = catalog.genresAreYears ? "Year" : "Genre"
        return Menu {
            Picker(noun, selection: $genre) {
                if !catalog.requiresGenre {
                    Text(catalog.genresAreYears ? "All Years" : "All Genres").tag(String?.none)
                }
                ForEach(catalog.genres, id: \.self) { Text($0).tag(Optional($0)) }
            }
        } label: {
            Label(noun, systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    /// Sort orders come from the addon's manifest: the installed copy, or for the built-in
    /// Cinemeta a fresh one. Without it the grid just offers no sort menu.
    private func loadSortOptions() async {
        let manifest: AddonManifest?
        if let installed = store.addons.first(where: { $0.manifestURL == source.manifestURL })?.manifest {
            manifest = installed
        } else {
            manifest = try? await AddonClient(manifestURL: source.manifestURL).manifest()
        }
        sortOptions = manifest?.sortOptions(for: source) ?? []
    }

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .failed:
            VStack(spacing: 8) {
                Text("Couldn't load more of \(source.title).")
                    .foregroundStyle(.secondary)
                Button("Retry") { Task { await loadNextPage() } }
            }
            .frame(maxWidth: .infinity)
        case .idle where items.isEmpty && reachedEnd:
            ContentUnavailableView("Nothing here", systemImage: "square.grid.2x2",
                                   description: Text("This catalog has no titles for this filter."))
        case .idle:
            EmptyView()
        }
    }

    private func loadNextPage() async {
        guard phase != .loading, !reachedEnd else { return }
        phase = .loading
        let requestedGenre = genre
        let generation = loadGeneration
        let shown = shown
        do {
            let page = try await shown.items(genre: requestedGenre, skip: items.count)
            try Task.checkCancellation()
            // A previous filter's request must not overwrite the current list or loading state.
            guard generation == loadGeneration, requestedGenre == genre else { return }
            // Addons that ignore `skip` return the first page again; treat that as the end.
            var known = Set(items.map(\.id))
            let fresh = page.filter { known.insert($0.id).inserted }
            items += fresh
            reachedEnd = fresh.isEmpty || !shown.catalog.supportsPaging
            phase = .idle
            #if os(tvOS)
            // Once: after choosing a genre or sort order, focus belongs on that button.
            if !hasPlacedFocus, !items.isEmpty {
                hasPlacedFocus = true
                isFirstFocused = true
            }
            #endif
        } catch {
            guard generation == loadGeneration, requestedGenre == genre else { return }
            phase = error is CancellationError || Task.isCancelled ? .idle : .failed
        }
    }
}
