import LogeCore
import SwiftUI

struct HomeView: View {
    /// Replaced on pull-to-refresh, which rebuilds the rows so they load again.
    @State private var refreshID = UUID()

    var body: some View {
        let sources = DiscoveryCatalogs.home
        #if os(tvOS)
        TVHome(sources: sources)
        #else
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                FeaturedCarousel(movies: sources[0], series: sources[1])
                ContinueWatchingRow()
                MyListRow()
                RecommendedRow()
                // Genres follow the popular shelves, ahead of the narrower ones.
                ForEach(sources.prefix(3)) { CatalogRow(source: $0) }
                GenreRow()
                ForEach(sources.dropFirst(3)) { CatalogRow(source: $0) }
                DiscoveryCollectionRow(title: "Film Festivals", collections: FilmCollection.festivals)
                PopularDirectorsRow()
            }
            .padding(.bottom, 32)
            .id(refreshID)
        }
        .task(id: refreshID) {
            await prefetchArtwork(of: sources)
        }
        .refreshable {
            refreshID = UUID()
        }
        // The hero starts at the top edge of the screen, under the status bar or toolbar.
        .ignoresSafeArea(edges: .top)
        .background(Color.canvas)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #elseif os(macOS)
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
