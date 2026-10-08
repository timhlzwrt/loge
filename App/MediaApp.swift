import MediaCore
import SwiftUI

@main
struct MediaApp: App {
    @State private var addonStore = AddonStore()

    init() {
        // Artwork is fetched through the shared session; the default cache is too
        // small to keep a screen of posters, so scrolling back re-downloads them.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(addonStore)
                .preferredColorScheme(.dark)
                // No accent colour: artwork carries the colour, controls stay neutral.
                .tint(.white)
                .task { await addonStore.refreshManifests() }
        }
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
            Tab("Addons", systemImage: "puzzlepiece.extension") {
                NavigationStack { AddonSettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// A navigation stack that opens catalog items in the details screen.
private struct BrowseStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: MetaPreview.self) { MetaDetailView(preview: $0) }
        }
    }
}
