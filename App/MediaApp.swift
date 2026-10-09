import MediaCore
import SwiftUI

@main
struct MediaApp: App {
    @State private var addonStore = AddonStore()
    @State private var library = LibraryStore()

    init() {
        // Artwork is fetched through the shared session; the default cache is too
        // small to keep a screen of posters, so scrolling back re-downloads them.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(addonStore)
                .environment(library)
                .preferredColorScheme(.dark)
                // No accent colour: artwork carries the colour, controls stay neutral.
                .tint(.white)
                .task { await addonStore.refreshManifests() }
        }
        #if os(macOS)
        // A window of its own, so playback can go full screen and sit beside the browser.
        WindowGroup("Player", for: PlaybackRequest.self) { $request in
            if let request {
                PlayerView(request: request)
                    .environment(library)
                    .environment(addonStore)
                    .frame(minWidth: 640, minHeight: 360)
                    .preferredColorScheme(.dark)
                    .navigationTitle(request.title)
            }
        }
        #endif
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                BrowseStack { HomeView() }
            }
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                BrowseStack { SearchView() }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// A navigation stack that opens catalog items in the details screen and their sources from there.
private struct BrowseStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: MetaPreview.self) { MetaDetailView(preview: $0) }
                .navigationDestination(for: SourcesRoute.self) { SourcesView(route: $0) }
                .navigationDestination(for: CatalogSource.self) { CatalogGridView(source: $0) }
        }
    }
}
