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
                // A phone keeps the text above the tab bar, in reach of the thumb, with the glow in the
                // space above; larger screens centre it.
                .frame(minHeight: proxy.size.height, alignment: Metrics.isPhone ? .bottom : .center)
                .buttonStyle(TokenButtonStyle())
                .menuStyle(.button)
            }
        }
        .background {
            // A glow in the empty corner above the name, where the app's other pages lead with artwork.
            RadialGradient(colors: [Self.glowColor.opacity(0.32), .clear], center: UnitPoint(x: 0.85, y: 0.06),
                           startRadius: 0, endRadius: Self.glowRadius)
                .background(Color.canvas)
                .ignoresSafeArea()
        }
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
            styleChoice
        }
    }

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

    /// The amber of the retired accent colours.
    private static let glowColor = Color(red: 0.96, green: 0.72, blue: 0.25)

    #if os(tvOS)
    private static let glowRadius: CGFloat = 900
    private static let lineSpacing: CGFloat = 18
    private static let readableWidth: CGFloat = 1300
    private static let wordmarkFont = Font.system(size: 110, weight: .heavy)
    private static let wordmarkTracking: CGFloat = -4
    private static let styleChoiceFont = Font.system(size: 25, weight: .medium)
    private static let styleChoiceWordSpace: CGFloat = 7
    #elseif os(macOS)
    private static let glowRadius: CGFloat = 420
    private static let lineSpacing: CGFloat = 10
    private static let readableWidth: CGFloat = 560
    private static let wordmarkFont = Font.system(size: 56, weight: .heavy)
    private static let wordmarkTracking: CGFloat = -2
    private static let styleChoiceFont = Font.callout
    private static let styleChoiceWordSpace: CGFloat = 4
    #else
    private static let glowRadius: CGFloat = 460
    private static let lineSpacing: CGFloat = 12
    private static let readableWidth: CGFloat = 600
    private static let wordmarkFont = Font.system(size: 96, weight: .heavy)
    private static let wordmarkTracking: CGFloat = -4
    private static let styleChoiceFont = Font.footnote
    private static let styleChoiceWordSpace: CGFloat = 4
    #endif
}

/// One sentence: plain words and controls, wrapping between them like running text.
private struct Sentence<Content: View>: View {
    private let content: Content
    private let font: Font
    private let fixedWordSpace: CGFloat?
    #if os(tvOS)
    static var defaultFont: Font { .system(size: 38, weight: .semibold) }
    @ScaledMetric(relativeTo: .title) private var wordSpace: CGFloat = 10
    #elseif os(macOS)
    static var defaultFont: Font { .system(size: 20, weight: .semibold) }
    @ScaledMetric(relativeTo: .title) private var wordSpace: CGFloat = 5
    #else
    static var defaultFont: Font { .title.weight(.semibold) }
    @ScaledMetric(relativeTo: .title) private var wordSpace: CGFloat = 7
    #endif

    /// A font other than the default needs its own word space, which scales with the text.
    init(font: Font = defaultFont, wordSpace: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.font = font
        fixedWordSpace = wordSpace
        self.content = content()
    }

    var body: some View {
        let space = fixedWordSpace ?? wordSpace
        SentenceLayout(wordSpace: space, lineSpacing: space * 0.4) { content }
            .font(font)
    }
}

/// Plain words, one layout item each so lines can break between them. VoiceOver skips them:
/// each control's label carries its setting's name.
private struct Words: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, word in
            Text(word)
                .layoutValue(key: FollowsWithoutSpace.self, value: word.first.map { ",.".contains($0) } ?? false)
        }
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

/// Punctuation sits against the word before it.
private struct FollowsWithoutSpace: LayoutValueKey {
    static let defaultValue = false
}

private struct SentenceLayout: Layout {
    let wordSpace: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            // A control longer than a line, such as a long addon name, wraps inside itself.
            if size.width > width { size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            let attached = subview[FollowsWithoutSpace.self]
            var gap = x == 0 || attached ? 0 : wordSpace
            if x > 0, !attached, x + gap + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
                gap = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x + gap, y: y), size: size))
            x += gap + size.width
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x)
        }
        return (frames, CGSize(width: widest, height: y + lineHeight))
    }
}

/// A value in a sentence: white and underlined among grey words; on Apple TV, black on white
/// under focus, like the app's other focused controls.
private struct TokenLabel: View {
    let text: String
    var isWarning = false
    var isUnderlined = true
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #else
    private let isFocused = false
    #endif

    init(_ text: String, isWarning: Bool = false, isUnderlined: Bool = true) {
        self.text = text
        self.isWarning = isWarning
        self.isUnderlined = isUnderlined
    }

    var body: some View {
        Text(text)
            .foregroundStyle(isFocused ? Color.black : isWarning ? Color.orange : Color.white)
            .underline(isUnderlined && !isFocused, color: (isWarning ? Color.orange : Color.white).opacity(0.35))
            .padding(.horizontal, 8)
            .background(isFocused ? Color.white : Color.clear, in: .rect(cornerRadius: 8))
            .padding(.horizontal, -8)
            .multilineTextAlignment(.leading)
    }
}

private struct TokenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.rect)
    }
}
