import LogeCore
import SwiftUI

@main
struct LogeApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #endif
    #if os(macOS)
    @StateObject private var appUpdater: AppUpdater
    #endif
    @State private var addonStore: AddonStore
    @State private var library: LibraryStore
    @State private var trakt: TraktAccount
    @State private var tmdb: TMDBAccount
    @State private var playback: PlaybackSession
    @State private var accountSync: AccountSync
    /// Here rather than in `RootView`, so the Mac's menu commands can switch tabs.
    @State private var selectedTab = RootTab.home
    /// Coming back from Control Center or a system sheet isn't a return to the app.
    @State private var leftForeground = false
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
        #if os(macOS)
        _appUpdater = StateObject(wrappedValue: AppUpdater(beforeRelaunch: { [weak playback] in playback?.end() }))
        #endif

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
                // A visible toolbar keeps its own strip in full screen, which cuts the artwork off under it.
                .windowToolbarFullScreenVisibility(.onHover)
                .environmentObject(appUpdater)
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
                    trakt.sendPendingOnReconnect()
                    // Alongside, so an unreachable sync server doesn't hold up the addons; a sync
                    // that changes them refreshes them itself.
                    let addons = addonStore
                    async let manifests: Void = addons.refreshManifests()
                    await accountSync.sync()
                    await manifests
                    // Needs the addons to look up titles started on other devices.
                    await trakt.pullProgress()
                    await library.fillMissingArtwork(from: addonStore)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        playback.sceneDidEnterBackground()
                        finishSyncingBeforeSuspension()
                        leftForeground = true
                    }
                    #if os(macOS)
                    // The Mac reports another app in front as inactive, and rarely as background.
                    if newPhase == .inactive { leftForeground = true }
                    #endif
                    guard newPhase == .active else { return }
                    playback.sceneDidBecomeActive()
                    guard leftForeground else { return }
                    leftForeground = false
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
        .commands {
            PlaybackCommands(playback: playback)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: appUpdater.checkForUpdates)
                    .disabled(!appUpdater.canCheckForUpdates)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { selectedTab = .settings }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .textEditing) {
                Button("Search") { selectedTab = .search }
                    .keyboardShortcut("f")
            }
            // Every window would rerun the launch work and react to playback on its own, over shared stores.
            CommandGroup(replacing: .newItem) {}
        }
        #endif
        #if os(macOS)
        // A window of its own, so playback can go full screen and sit beside the browser.
        Window("Player", id: PlayerView.windowID) {
            PlayerView()
                .environment(playback)
                // The sources sheet opened from the player needs them, and can add an addon.
                .environment(addonStore)
                .environment(library)
                .environment(trakt)
                .environment(tmdb)
                .environment(accountSync)
                .frame(minWidth: 640, minHeight: 360)
                .tint(accent.color)
                .preferredColorScheme(.dark)
                .navigationTitle(playback.current?.title ?? "")
        }
        // Beside a WindowGroup, a Window is an associated window, which can't go full screen.
        .windowManagerRole(.principal)
        // As a principal window it would otherwise reopen empty at launch.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        // Opened from the Window menu with nothing playing, it would be an empty black window.
        .commandsRemoved()
        #endif
    }

    /// What leaving just saved would otherwise wait for the next launch: the system can suspend
    /// the app before these requests finish. The Mac doesn't suspend.
    private func finishSyncingBeforeSuspension() {
        #if !os(macOS)
        let time = BackgroundTime()
        Task {
            // A sync already running may have started before the last save, so one follows it.
            while accountSync.isSyncing {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
            }
            await accountSync.sync()
            await trakt.sendPending()
            time.end()
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
            RootView(selection: $selectedTab)
        }
        #else
        RootView(selection: $selectedTab)
        #endif
    }

}

#if !os(macOS)
/// Asks the system for the moments the last sync needs before the app is suspended.
@MainActor
private final class BackgroundTime {
    private var id = UIBackgroundTaskIdentifier.invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "Last sync") { [weak self] in self?.end() }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif

#if DEBUG
private struct SyncUITestCode: Decodable { let code: String }
#endif

enum RootTab: Hashable {
    case home, search, myLists, settings
    case catalog(CatalogSource)
}

struct RootView: View {
    @Binding var selection: RootTab
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
        TabView(selection: $selection) {
            tab("Home", systemImage: "house", value: .home) {
                BrowseStack { HomeView() }
            }
            #if os(macOS)
            // The sidebar reads top to bottom, so Search sits with the other places to go.
            tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                BrowseStack { SearchView() }
            }
            #endif
            tab("My Lists", systemImage: "bookmark", value: .myLists) {
                BrowseStack { MyListView() }
            }
            #if os(macOS)
            TabSection("Catalogs") {
                ForEach(DiscoveryCatalogs.home) { source in
                    Tab(source.shortTitle, systemImage: source.catalog.type == MediaType.series ? "tv" : "rectangle.portrait",
                        value: RootTab.catalog(source)) {
                        BrowseStack { CatalogGridView(source: source) }
                    }
                }
            }
            #endif
            // iPhone opens Settings from a gear on Home.
            if !Metrics.isPhone {
                tab("Settings", systemImage: "gearshape", value: .settings) {
                    NavigationStack { SettingsView() }
                }
            }
            #if !os(macOS)
            tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                BrowseStack { SearchView() }
            }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    /// A tab that shows only its icon in the phone's tab bar, where the symbols are
    /// familiar enough, and its name in a sidebar.
    private func tab(
        _ title: String, systemImage: String, value: RootTab, role: TabRole? = nil,
        @ViewBuilder content: () -> some View
    ) -> some TabContent<RootTab> {
        Tab(value: value, role: role) {
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
                .navigationDestination(for: TMDBCreditTitle.self) { TMDBTitleView(title: $0) }
                .navigationDestination(for: HistoryRoute.self) { _ in HistoryView() }
                .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
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
