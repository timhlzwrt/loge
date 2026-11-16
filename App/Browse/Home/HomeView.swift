import LogeCore
import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AddonStore.self) private var store
    @Environment(EpisodeSchedule.self) private var schedule
    @AppStorage(HomeLayout.storageKey) private var storedLayout: Data?
    /// Replaced on pull-to-refresh, which rebuilds the rows so they load again.
    @State private var refreshID = UUID()
    /// Returning to Home runs `.task` again; its artwork is already cached by then.
    @State private var prefetched = false
    #if !os(tvOS)
    /// Opened by the carousel's Play. Declared here rather than in the carousel's lazy stacks,
    /// where navigation destinations aren't reliably found.
    @State private var playing: SourcesRoute?
    @State private var opening: MetaPreview?
    #endif
    #if os(macOS)
    /// The scroll view runs under the toolbar, so what it holds can't read this itself.
    @State private var topInset: CGFloat = 0
    #endif

    var body: some View {
        let rows = HomeLayout(storedData: storedLayout).rows(addons: store.addons)
        let sources = rows.catalogs
        #if os(tvOS)
        TVHome(rows: rows)
            // On every return to Home: a series started since then is followed from here on.
            .task { await schedule.refresh(for: library, addons: store) }
        #else
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                // From the first movie and series shelves, which by default are the popular ones.
                let movies = sources.first { $0.catalog.type == MediaType.movie }
                let series = sources.first { $0.catalog.type == MediaType.series }
                if movies != nil || series != nil {
                    FeaturedCarousel(movies: movies, series: series, playing: $playing, opening: $opening)
                        // Loads its pages once, so other shelves start it over.
                        .id([movies?.id, series?.id])
                }
                ForEach(rows) { row in
                    switch row {
                    case .catalog(let source): CatalogRow(source: source, page: sources)
                    case .genres: GenreRow()
                    case .continueWatching: ContinueWatchingRow()
                    case .watchLater: MyListRow()
                    case .recommended: RecommendedRow()
                    }
                }
            }
            .padding(.bottom, 32)
            .id(refreshID)
        }
        .task {
            guard !prefetched else { return }
            prefetched = true
            await prefetchArtwork(of: sources)
        }
        // On every return to Home: a series started since then is followed from here on.
        .task { await schedule.refresh(for: library, addons: store) }
        .refreshable {
            // The spinner stays until every row's first page is fresh; then the rows rebuild from them.
            await CatalogCache.shared.expireAll()
            await schedule.refresh(for: library, addons: store, force: true)
            await prefetchArtwork(of: sources)
            refreshID = UUID()
        }
        .navigationDestination(item: $playing) { SourcesView(route: $0) }
        .navigationDestination(item: $opening) { MetaDetailView(preview: $0) }
        #if os(macOS)
        // The hero is a button reaching under the toolbar, where it took the click meant to
        // move the window. This strip stays put while the page scrolls.
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: topInset)
                .contentShape(.rect)
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
        #endif
        // The hero starts at the top edge of the screen, under the status bar or toolbar.
        .ignoresSafeArea(edges: .top)
        .background(Color.canvas)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #elseif os(macOS)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        // The hero names what's on screen; the window needs no title over it.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        #endif
    }
}

/// Downloads artwork into the shared URL cache that `Artwork` and `TitleLogo` load from,
/// so it's already there when a row scrolls in or the carousel pages. Plain data tasks
/// rather than a task group: opening anything from Home cancels its task, and a Release
/// crash on the iPhone (a group child finishing after its group was gone) followed opening
/// a title from Home while this was likely still running.
@MainActor
func prefetch(_ urls: [String?]) {
    for url in Set(urls.compactMap { $0 }).compactMap(URL.init(string:)) where ArtworkCache.cached(url) == nil {
        // Only warms the cache: the view that shows the image handles a failure.
        let task = URLSession.shared.dataTask(with: url)
        // Behind the posters already on screen, which load at the same time.
        task.priority = URLSessionTask.lowPriority
        task.resume()
    }
}

/// The first posters of every Home row in screen order, so rows further down have theirs
/// before they scroll in. Their catalog responses are cached too, so the rows don't
/// download them again.
func prefetchArtwork(of sources: [CatalogSource]) async {
    for source in sources {
        guard !Task.isCancelled else { return }
        // A row that fails shows its own error and retry.
        guard let metas = try? await source.items() else { continue }
        var urls = metas.prefix(12).map(\.poster)
        #if os(tvOS)
        // Focus usually enters a row at its start, which fills the screen with its backdrop.
        urls += metas.prefix(2).map(\.featuredBackground)
        #endif
        await prefetch(urls)
    }
}
