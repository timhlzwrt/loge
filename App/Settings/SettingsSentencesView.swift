import LogeCore
import SwiftUI

/// Settings as one sentence about the app; each value in it is the control that changes it,
/// so the page needs no title or captions. The list form is a menu away. On a wide iPad the
/// page a value opens shows beside the sentence, with that value marked.
struct SettingsSentencesView: View {
    @Environment(AddonStore.self) private var store
    @Environment(TMDBAccount.self) private var tmdb
    @Environment(AccountSync.self) private var sync
    @AppStorage(SettingsView.showsListKey) private var showsList = false
    @AppStorage(SyncedSettings.Key.audioLanguage) private var audioLanguage = SyncedSettings().audioLanguage
    @AppStorage(SyncedSettings.Key.subtitleLanguage) private var subtitleLanguage = SyncedSettings().subtitleLanguage
    @AppStorage(SyncedSettings.Key.maximumBitrate) private var maximumBitrate = SyncedSettings().maximumBitrate
    @AppStorage(SyncedSettings.Key.combinesAddonSources) private var combinesAddonSources = false
    @AppStorage(HomeLayout.storageKey) private var homeLayout: Data?
    @State private var isConnectingTMDB = false
    #if os(iOS)
    @State private var isSharing = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Beside the sentence on a wide iPad; Addons until another value is chosen.
    @State private var opened = Destination.addons
    #endif
    #if os(macOS)
    @EnvironmentObject private var appUpdater: AppUpdater
    #endif

    /// The pages the sentence's values open.
    enum Destination: Hashable {
        case about, addons, shelves, tmdb, sync

        var title: String {
            switch self {
            case .about: "About"
            case .addons: "Addons"
            case .shelves: "Home Shelves"
            case .tmdb: "TMDB"
            case .sync: "Sync"
            }
        }

        @MainActor @ViewBuilder var page: some View {
            switch self {
            case .about: SettingsPage("About") { AboutSection() }
            case .addons: AddonsSettingsView()
            case .shelves: HomeSettingsView()
            case .tmdb: SettingsPage("TMDB") { TMDBSection() }
            case .sync: SyncSettingsView()
            }
        }
    }

    var body: some View {
        Group {
            #if os(iOS)
            if splitsPages {
                HStack(alignment: .top, spacing: 40) {
                    sentencePage
                        .frame(width: 520)
                    // Pages pushed from here (an addon shelf, a sync step) still take the whole screen.
                    VStack(alignment: .leading, spacing: 0) {
                        Text(opened.title)
                            .font(.title2.bold())
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                        opened.page
                    }
                    .id(opened)
                    .background(.white.opacity(0.04), in: .rect(cornerRadius: 24))
                    .padding(.vertical, 24)
                }
                .padding(.horizontal, Metrics.gutter)
                // The page names itself in the panel; the bar keeps only its buttons.
                .toolbar { ToolbarItem(placement: .principal) { Text(verbatim: "") } }
            } else {
                sentencePage
            }
            #else
            sentencePage
            #endif
        }
        // Plain charcoal, as on every page without a title's room.
        .background(Color.canvas.ignoresSafeArea())
        #if !os(tvOS)
        // Names the page for the back button and the Mac's window; the tab bar already says where this is.
        .navigationTitle("Settings")
        #endif
        #if os(iOS)
        // Kept beside the split, where the page on the right puts its Edit and Reset in it.
        .toolbar(splitsPages ? .automatic : .hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $isConnectingTMDB) { TMDBSetupView() }
    }

    private var sentencePage: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    link(.about, accessibility: "About loge, version \(AboutSection.version)") { isMarked in
                        TokenLabel("loge", isUnderlined: false, isMarked: isMarked)
                            .font(Self.wordmarkFont)
                            .tracking(Self.wordmarkTracking)
                    }
                    Spacer().frame(height: Self.lineSpacing * 2)
                    settings
                }
                .frame(maxWidth: Self.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, splitsPages ? 0 : Metrics.gutter)
                .padding(.vertical, Self.lineSpacing)
                // Read from the top, like every other page.
                .frame(minHeight: proxy.size.height, alignment: .top)
                .buttonStyle(TokenButtonStyle())
                .menuStyle(.button)
            }
        }
    }

    /// Opens a value's page: beside the sentence on a wide iPad, pushed elsewhere.
    @ViewBuilder
    private func link(_ destination: Destination, accessibility: String,
                      @ViewBuilder label: @escaping (_ isMarked: Bool) -> some View) -> some View {
        #if os(iOS)
        if splitsPages {
            Button { opened = destination } label: { label(opened == destination) }
                .accessibilityLabel(accessibility)
                .accessibilityAddTraits(opened == destination ? .isSelected : [])
        } else {
            NavigationLink { destination.page } label: { label(false) }
                .accessibilityLabel(accessibility)
        }
        #else
        NavigationLink { destination.page } label: { label(false) }
            .accessibilityLabel(accessibility)
        #endif
    }

    private var splitsPages: Bool {
        #if os(iOS)
        !Metrics.isPhone && horizontalSizeClass == .regular
        #else
        false
        #endif
    }

    /// One paragraph, wrapping between its words and values like running text.
    private var settings: some View {
        VStack(alignment: .leading, spacing: Self.lineSpacing) {
            Sentence {
                Words("shows")
                link(.shelves, accessibility: "Home Shelves, \(shelfCount)") { TokenLabel(shelfCount, isMarked: $0) }
                Words("on Home,")
                playback
                sources
                cast
                syncing
            }
            #if os(iOS)
            setupButtons
            #elseif os(macOS)
            updates
            #endif
            styleChoice
        }
    }

    #if os(macOS)
    /// Sparkle's switch and check, which only the Mac has.
    private var updates: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Toggle("Check for updates automatically", isOn: $appUpdater.automaticallyChecksForUpdates)
                Spacer()
                Button("Check Now", action: appUpdater.checkForUpdates)
                    .disabled(!appUpdater.canCheckForUpdates)
            }
            Text("Version \(AboutSection.version)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.automatic)
        .padding(.top, Self.lineSpacing * 2)
    }
    #endif

    #if os(iOS)
    /// A copy of the addons for someone else, or theirs for this device.
    private var setupButtons: some View {
        HStack(spacing: 10) {
            Button { isSharing = true } label: { Text("Share Setup").frame(maxWidth: .infinity) }
                .disabled(store.addons.isEmpty)
            NavigationLink { ImportSetupView() } label: { Text("Import Setup").frame(maxWidth: .infinity) }
        }
        .buttonStyle(PrimaryButtonStyle(isTranslucent: true))
        .controlSize(.small)
        .padding(.top, Self.lineSpacing * 2)
        .sheet(isPresented: $isSharing) { NavigationStack { ShareSetupView() } }
    }
    #endif

    @ViewBuilder private var playback: some View {
        Words("plays in")
        Menu {
            Picker("Audio", selection: $audioLanguage) {
                Text("File default").tag("")
                ForEach(PlaybackPreferences.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
        } label: {
            TokenLabel(audioLanguage.isEmpty ? "the file's language" : languageName(audioLanguage))
        }
        .accessibilityLabel("Audio, \(audioLanguage.isEmpty ? "File default" : languageName(audioLanguage))")
        Words("with")
        Menu {
            Picker("Subtitles", selection: $subtitleLanguage) {
                Text("Off").tag("")
                ForEach(PlaybackPreferences.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
        } label: {
            TokenLabel(subtitleLanguage.isEmpty ? "no" : languageName(subtitleLanguage))
        }
        .accessibilityLabel("Subtitles, \(subtitleLanguage.isEmpty ? "Off" : languageName(subtitleLanguage))")
        Words(maximumBitrate == 0 ? "subtitles, at" : "subtitles, up to")
        Menu {
            Picker("Maximum bitrate", selection: $maximumBitrate) {
                Text("No limit").tag(0)
                ForEach(SyncedSettings.maximumBitrateOptions.filter { $0 > 0 }, id: \.self) {
                    Text(PlaybackSettingsSection.bitrateOption($0)).tag($0)
                }
            }
        } label: {
            TokenLabel(maximumBitrate == 0 ? "any bitrate" : "\(maximumBitrate) Mbps")
        }
        .accessibilityLabel("Maximum bitrate, \(maximumBitrate == 0 ? "No limit" : "\(maximumBitrate) Mbps")")
        Words(",")
    }

    private var sources: some View {
        let addons = store.streamAddons
        let names = switch addons.count {
        case 0: "no addon yet"
        case 1: addons[0].displayName
        case let count where combinesAddonSources: "all \(count) addons"
        case let count: "\(addons[0].displayName) and \(count - 1) more"
        }
        return Group {
            Words("takes sources from")
            link(.addons, accessibility: "Addons, \(names)") { TokenLabel(names, isWarning: addons.isEmpty, isMarked: $0) }
            // Only a choice with more than one addon to take sources from.
            if addons.count > 1 {
                Words(",")
                Menu {
                    Picker("Sources", selection: $combinesAddonSources) {
                        Text("One addon at a time").tag(false)
                        Text("Combined").tag(true)
                    }
                } label: {
                    TokenLabel(combinesAddonSources ? "combined" : "one at a time")
                }
                .accessibilityLabel("Sources, \(combinesAddonSources ? "Combined" : "One addon at a time")")
            }
            Words(",")
        }
    }

    @ViewBuilder private var cast: some View {
        if tmdb.storageError != nil {
            Words("has cast and recommendations")
            link(.tmdb, accessibility: "Cast and Recommendations, Unavailable") {
                TokenLabel("unavailable", isWarning: true, isMarked: $0)
            }
        } else if tmdb.isConfigured {
            Words("gets cast and recommendations from")
            link(.tmdb, accessibility: "Cast and Recommendations, TMDB") { TokenLabel("TMDB", isMarked: $0) }
        } else {
            // Off, the TMDB page would only say so; this goes straight to entering a token.
            Words("has cast and recommendations")
            Button { isConnectingTMDB = true } label: { TokenLabel("off") }
                .accessibilityLabel("Cast and Recommendations, Off")
        }
    }

    @ViewBuilder private var syncing: some View {
        if sync.isConnected {
            let name = sync.displayName ?? "your account"
            Words("and syncs as")
            link(.sync, accessibility: "Sync, \(name)") { TokenLabel(name, isMarked: $0) }
            if let problem = sync.problem {
                Words(", but")
                link(.sync, accessibility: "Sync, \(problem)") {
                    TokenLabel(problem.lowercased(), isWarning: true, isMarked: $0)
                }
            }
        } else {
            Words("and syncs with")
            link(.sync, accessibility: "Sync, Off") { TokenLabel("no other devices", isMarked: $0) }
        }
        Words(".")
    }

    private var styleChoice: some View {
        Sentence(font: Self.styleChoiceFont, wordSpace: Self.styleChoiceWordSpace) {
            Words("Settings read as")
            Menu {
                Picker("Settings", selection: $showsList) {
                    Text("Sentences").tag(false)
                    Text("List").tag(true)
                }
            } label: {
                TokenLabel("sentences")
            }
            .accessibilityLabel("Show Settings as, Sentences")
            Words(".")
        }
        .padding(.top, Self.lineSpacing * 1.5)
    }

    private var shelfCount: String {
        let count = HomeLayout(storedData: homeLayout).entries.filter { !$0.isHidden }.count
        return count == 1 ? "1 shelf" : "\(count) shelves"
    }

    private func languageName(_ code: String) -> String {
        PlaybackPreferences.languages.first { $0.code == code }?.name ?? code
    }

    #if os(tvOS)
    private static let lineSpacing: CGFloat = 18
    private static let readableWidth: CGFloat = 1300
    private static let wordmarkFont = Font.system(size: 110, weight: .heavy)
    private static let wordmarkTracking: CGFloat = -4
    private static let styleChoiceFont = Font.system(size: 25, weight: .medium)
    private static let styleChoiceWordSpace: CGFloat = 7
    #elseif os(macOS)
    private static let lineSpacing: CGFloat = 10
    private static let readableWidth: CGFloat = 560
    private static let wordmarkFont = Font.system(size: 56, weight: .heavy)
    private static let wordmarkTracking: CGFloat = -2
    private static let styleChoiceFont = Font.callout
    private static let styleChoiceWordSpace: CGFloat = 4
    #else
    private static let lineSpacing: CGFloat = 12
    private static let readableWidth: CGFloat = 600
    private static let wordmarkFont = Font.system(size: 64, weight: .heavy)
    private static let wordmarkTracking: CGFloat = -3
    private static let styleChoiceFont = Font.footnote
    private static let styleChoiceWordSpace: CGFloat = 4
    #endif
}
