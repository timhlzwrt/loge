import LogeCore
import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AddonStore.self) private var store
    @Environment(EpisodeSchedule.self) private var schedule
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
        let sources = DiscoveryCatalogs.home
        #if os(tvOS)
        TVHome(sources: sources)
            // On every return to Home: a series started since then is followed from here on.
            .task { await schedule.refresh(for: library, addons: store) }
        #else
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                FeaturedCarousel(movies: sources[0], series: sources[1], playing: $playing, opening: $opening)
                ContinueWatchingRow()
                UpcomingRow()
                MyListRow()
                RecommendedRow()
                // Genres follow the popular shelves, ahead of the narrower ones.
                ForEach(sources.prefix(3)) { CatalogRow(source: $0, page: sources) }
                GenreRow()
                ForEach(sources.dropFirst(3)) { CatalogRow(source: $0, page: sources) }
                DiscoveryCollectionRow(title: "Film Festivals", collections: FilmCollection.festivals)
                PopularDirectorsRow()
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
/// a festival while this was likely still running.
func prefetch(_ urls: [String?]) {
    for url in Set(urls.compactMap { $0 }).compactMap(URL.init(string:)) {
        // Only warms the cache: the view that shows the image handles a failure.
        URLSession.shared.dataTask(with: url).resume()
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
        prefetch(urls)
    }
}
