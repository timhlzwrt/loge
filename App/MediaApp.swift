import MediaCore
import SwiftUI

@main
struct MediaApp: App {
    @State private var addonStore: AddonStore
    @State private var library: LibraryStore
    @State private var trakt: TraktAccount
    @State private var playback: PlaybackSession

    init() {
        let addonStore = AddonStore()
        let library = LibraryStore()
        _addonStore = State(initialValue: addonStore)
        _library = State(initialValue: library)
        let trakt = TraktAccount(library: library, addons: addonStore)
        _trakt = State(initialValue: trakt)
        _playback = State(initialValue: PlaybackSession(library: library, addons: addonStore, trakt: trakt))

        // Artwork is fetched through the shared session; the default cache is too
        // small to keep a screen of posters, so scrolling back re-downloads them.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                #if os(macOS)
                // Also corrects a too-small frame the system restored from an earlier launch.
                .frame(minWidth: 900, minHeight: 600)
                #endif
                .environment(addonStore)
                .environment(library)
                .environment(playback)
                .environment(trakt)
                .preferredColorScheme(.dark)
                // No accent colour: artwork carries the colour, controls stay neutral.
                .tint(.white)
                .task {
                    await addonStore.refreshManifests()
                    // Needs the addons to look up titles started on other devices.
                    await trakt.pullProgress()
                    await library.fillMissingArtwork(from: addonStore)
                }
        }
        #if os(macOS)
        // Room for the hero and a couple of rows; the system remembers any size the user picks.
        .defaultSize(width: 1280, height: 820)
        .commands { PlaybackCommands(playback: playback) }
        #endif
        #if os(macOS)
        // A window of its own, so playback can go full screen and sit beside the browser.
        Window("Player", id: PlayerView.windowID) {
            PlayerView()
                .environment(playback)
                .frame(minWidth: 640, minHeight: 360)
                .tint(.white)
                .preferredColorScheme(.dark)
                .navigationTitle(playback.current?.title ?? "")
        }
        #endif
    }
}

struct RootView: View {
    @Environment(PlaybackSession.self) private var playback
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        @Bindable var playback = playback
        tabs
            #if os(macOS)
            .onChange(of: playback.isScreenPresented) { _, presented in
                if presented {
                    openWindow(id: PlayerView.windowID)
                } else {
                    dismissWindow(id: PlayerView.windowID)
                }
            }
            #else
            .fullScreenCover(isPresented: $playback.isScreenPresented) { PlayerView() }
            #endif
    }

    private var tabs: some View {
        TabView {
            tab("Home", systemImage: "house") {
                BrowseStack { HomeView() }
            }
            #if os(macOS)
            // The sidebar reads top to bottom, so Search sits with the other places to go.
            tab("Search", systemImage: "magnifyingglass", role: .search) {
                BrowseStack { SearchView() }
            }
            #endif
            tab("My List", systemImage: "plus") {
                BrowseStack { MyListView() }
            }
            #if os(macOS)
            TabSection("Catalogs") {
                ForEach(DiscoveryCatalogs.home) { source in
                    Tab(source.title, systemImage: source.catalog.type == "series" ? "tv" : "rectangle.portrait") {
                        BrowseStack { CatalogGridView(source: source) }
                    }
                }
            }
            #endif
            tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
            #if !os(macOS)
            tab("Search", systemImage: "magnifyingglass", role: .search) {
                BrowseStack { SearchView() }
            }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    /// A tab that shows only its icon in the phone's tab bar, where the four symbols are
    /// familiar enough, and its name in a sidebar.
    private func tab(
        _ title: String, systemImage: String, role: TabRole? = nil, @ViewBuilder content: () -> some View
    ) -> some TabContent<Never> {
        Tab(role: role) {
            content()
        } label: {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                Image(systemName: systemImage).accessibilityLabel(title)
            } else {
                Label(title, systemImage: systemImage)
            }
            #else
            Label(title, systemImage: systemImage)
            #endif
        }
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
                .navigationDestination(for: PersonRoute.self) { PersonView(route: $0) }
        }
    }
}
