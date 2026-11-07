import LogeCore
import SwiftUI

@main
struct LogeApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #endif
    @State private var addonStore: AddonStore
    @State private var library: LibraryStore
    @State private var trakt: TraktAccount
    @State private var tmdb: TMDBAccount
    @State private var playback: PlaybackSession
    @State private var accountSync: AccountSync
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Accent.storageKey) private var accent = Accent.white

    init() {
        #if DEBUG
        // UI checks use a temporary file and memory-only account; no credential enters launch logs or Keychain.
        if ProcessInfo.processInfo.arguments.contains("--discovery-ui-test") {
            _tmdb = State(initialValue: TMDBAccount(temporaryReadAccessToken: "offline-ui-fixture", session: DiscoveryFixture.session))
        } else if ProcessInfo.processInfo.arguments.contains("--tmdb-ui-test"),
           let path = ProcessInfo.processInfo.environment["TMDB_TEST_TOKEN_FILE"],
           let token = try? String(contentsOfFile: path, encoding: .utf8) {
            _tmdb = State(initialValue: TMDBAccount(temporaryReadAccessToken: token))
        } else {
            _tmdb = State(initialValue: TMDBAccount())
        }
        #else
        _tmdb = State(initialValue: TMDBAccount())
        #endif
        let defaults: UserDefaults
        #if DEBUG
        let syncUITest = ProcessInfo.processInfo.arguments.contains("--sync-ui-test")
        defaults = syncUITest ? UserDefaults(suiteName: "sync-ui-\(UUID())")! : .standard
        #else
        defaults = .standard
        #endif
        let addonStore = AddonStore(defaults: defaults)
        let library = LibraryStore(defaults: defaults)
        _addonStore = State(initialValue: addonStore)
        #if DEBUG
        let accountSync = AccountSync(addons: addonStore, library: library, defaults: defaults, temporaryConnection: syncUITest)
        #else
        let accountSync = AccountSync(addons: addonStore, library: library, defaults: defaults)
        #endif
        _accountSync = State(initialValue: accountSync)
        _library = State(initialValue: library)
        let trakt = TraktAccount(library: library, addons: addonStore)
        _trakt = State(initialValue: trakt)
        let playback = PlaybackSession(library: library, addons: addonStore, trakt: trakt, accountSync: accountSync)
        accountSync.beforeProfileChange = { [weak playback] in playback?.end() }
        _playback = State(initialValue: playback)

        // Artwork is fetched through the shared session; the default cache is too
        // small to keep a screen of posters, so scrolling back re-downloads them.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            initialBrowseView
                #if os(macOS)
                // Also corrects a too-small frame the system restored from an earlier launch.
                .frame(minWidth: 900, minHeight: 600)
                #endif
                .environment(addonStore)
                .environment(library)
                .environment(playback)
                .environment(trakt)
                .environment(tmdb)
                .environment(accountSync)
                .preferredColorScheme(.dark)
                // White unless the user picks another accent: artwork carries the colour.
                .tint(accent.color)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--sync-ui-test") {
                        if let path = ProcessInfo.processInfo.environment["SYNC_TEST_CODE_FILE"],
                           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                           let fixture = try? JSONDecoder().decode(SyncUITestCode.self, from: data) {
                            await accountSync.connect(code: fixture.code, deviceName: "UI check")
                            if accountSync.needsChoice { await accountSync.resolve(useLocal: false) }
                        }
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--discovery-ui-test")
                        || ProcessInfo.processInfo.arguments.contains("--playback-ui-test") { return }
                    #endif
                    await accountSync.sync()
                    await addonStore.refreshManifests()
                    // Needs the addons to look up titles started on other devices.
                    await trakt.pullProgress()
                    await library.fillMissingArtwork(from: addonStore)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background { playback.sceneDidEnterBackground() }
                    guard newPhase == .active else { return }
                    playback.sceneDidBecomeActive()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--sync-ui-test")
                        || ProcessInfo.processInfo.arguments.contains("--discovery-ui-test")
                        || ProcessInfo.processInfo.arguments.contains("--playback-ui-test") { return }
                    #endif
                    Task {
                        await accountSync.sync()
                        await trakt.pullProgress()
                    }
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
                .tint(accent.color)
                .preferredColorScheme(.dark)
                .navigationTitle(playback.current?.title ?? "")
        }
        #endif
    }

    @ViewBuilder
    private var initialBrowseView: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--sync-ui-test") {
            NavigationStack { SyncSettingsView() }
        } else if ProcessInfo.processInfo.arguments.contains("--playback-ui-test") {
            PlaybackFixtureView()
        } else if ProcessInfo.processInfo.arguments.contains("--discovery-ui-test") {
            BrowseStack { DiscoveryFixture.screen }
        } else if ProcessInfo.processInfo.arguments.contains("--person-role-ui-test") {
            BrowseStack {
                PersonView(route: PersonRoute(person: Person(name: "Filmography check", roles: [.director])))
            }
        } else if ProcessInfo.processInfo.arguments.contains("--tmdb-ui-test"),
           let value = ProcessInfo.processInfo.environment["TMDB_TEST_PERSON_ID"],
           let id = Int(value), id > 0 {
            BrowseStack {
                PersonView(route: PersonRoute(person: Person(
                    name: ProcessInfo.processInfo.environment["TMDB_TEST_PERSON_NAME"] ?? "Person",
                    roles: [.director], tmdbID: id)))
            }
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }

}

#if DEBUG
private struct SyncUITestCode: Decodable { let code: String }
#endif

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
            tab("My Lists", systemImage: "bookmark") {
                BrowseStack { MyListView() }
            }
            #if os(macOS)
            TabSection("Catalogs") {
                ForEach(DiscoveryCatalogs.home) { source in
                    Tab(source.title, systemImage: source.catalog.type == MediaType.series ? "tv" : "rectangle.portrait") {
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
                .navigationDestination(for: HistoryRoute.self) { _ in HistoryView() }
                .navigationDestination(for: FilmCollection.self) { FilmCollectionView(collection: $0) }
                .navigationDestination(for: DiscoveryCatalogs.Genre.self) { GenreView(genre: $0) }
                .navigationDestination(for: FestivalRoute.self) { $0.destination }
        }
    }
}

#if os(iOS)
/// iPhone browsing stays upright; only the player turns with the phone.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private static var allowsLandscape = false

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        return Self.allowsLandscape ? .allButUpsideDown : .portrait
    }

    static func setAllowsLandscape(_ allowed: Bool) {
        guard allowed != allowsLandscape else { return }
        allowsLandscape = allowed
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
#endif
