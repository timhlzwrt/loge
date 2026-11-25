import LogeCore
import SwiftUI

/// Settings as one sentence about the app, a line per setting; each value in it is the control
/// that changes it, so the page needs no title or captions. The list form is a menu away.
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
    #endif

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    NavigationLink { SettingsPage("About") { AboutSection() } } label: {
                        TokenLabel("loge", isUnderlined: false)
                            .font(Self.wordmarkFont)
                            .tracking(Self.wordmarkTracking)
                    }
                    .accessibilityLabel("About loge, version \(AboutSection.version)")
                    Spacer().frame(height: Self.lineSpacing * 2)
                    settings
                }
                .frame(maxWidth: Self.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Self.lineSpacing)
                // A phone reads it from the top, like its other pages; larger screens centre it.
                .frame(minHeight: proxy.size.height, alignment: Metrics.isPhone ? .top : .center)
                .buttonStyle(TokenButtonStyle())
                .menuStyle(.button)
            }
        }
        // Plain charcoal, as on every page without a title's room.
        .background(Color.canvas.ignoresSafeArea())
        #if !os(tvOS)
        // Names the page for the back button and the Mac's window; the tab bar already says where this is.
        .navigationTitle("Settings")
        #endif
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $isConnectingTMDB) { TMDBSetupView() }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: Self.lineSpacing) {
            playback
            sources
            Sentence {
                Words("shows")
                NavigationLink { HomeSettingsView() } label: { TokenLabel(shelfCount) }
                    .accessibilityLabel("Home Shelves, \(shelfCount)")
                Words("on Home,")
            }
            cast
            syncing
            #if os(iOS)
            setupButtons
            #endif
            styleChoice
        }
    }

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

    private var playback: some View {
        Sentence {
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
    }

    private var sources: some View {
        let addons = store.streamAddons
        let names = switch addons.count {
        case 0: "no addon yet"
        case 1: addons[0].displayName
        case let count where combinesAddonSources: "all \(count) addons"
        case let count: "\(addons[0].displayName) and \(count - 1) more"
        }
        return Sentence {
            Words("takes sources from")
            NavigationLink { AddonsSettingsView() } label: { TokenLabel(names, isWarning: addons.isEmpty) }
                .accessibilityLabel("Addons, \(names)")
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
        Sentence {
            if tmdb.storageError != nil {
                Words("has cast and recommendations")
                NavigationLink { SettingsPage("TMDB") { TMDBSection() } } label: {
                    TokenLabel("unavailable", isWarning: true)
                }
                .accessibilityLabel("Cast and Recommendations, Unavailable")
            } else if tmdb.isConfigured {
                Words("gets cast and recommendations from")
                NavigationLink { SettingsPage("TMDB") { TMDBSection() } } label: { TokenLabel("TMDB") }
                    .accessibilityLabel("Cast and Recommendations, TMDB")
            } else {
                // Off, the TMDB page would only say so; this goes straight to entering a token.
                Words("has cast and recommendations")
                Button { isConnectingTMDB = true } label: { TokenLabel("off") }
                    .accessibilityLabel("Cast and Recommendations, Off")
            }
        }
    }

    private var syncing: some View {
        Sentence {
            if sync.isConnected {
                let name = sync.displayName ?? "your account"
                Words("and syncs as")
                NavigationLink { SyncSettingsView() } label: { TokenLabel(name) }
                    .accessibilityLabel("Sync, \(name)")
                if let problem = sync.problem {
                    Words(", but")
                    NavigationLink { SyncSettingsView() } label: { TokenLabel(problem.lowercased(), isWarning: true) }
                        .accessibilityLabel("Sync, \(problem)")
                }
            } else {
                Words("and syncs with")
                NavigationLink { SyncSettingsView() } label: { TokenLabel("no other devices") }
                    .accessibilityLabel("Sync, Off")
            }
            Words(".")
        }
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
