import LogeCore
import SwiftUI

#if os(iOS)
/// The top of a phone's Home while something is being watched: the latest of Continue
/// Watching over its backdrop with Resume, and the others a swipe away.
struct ResumeHero: View {
    let entries: [ContinueWatchingRow.Entry]
    /// The room tone of the page showing, for Home's background.
    @Binding var tone: Color
    @State private var currentID: ContinueWatchingRow.Entry.ID?

    var body: some View {
        let current = entries.first { $0.id == currentID } ?? entries.first
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(entries) { entry in
                    ResumePage(entry: entry, tone: tone)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .frame(height: 480)
        .roomTone(of: current?.item.background, into: $tone)
        .task(id: entries.map(\.id)) {
            // Swiping never shows an empty backdrop or a logo arriving late.
            prefetch(entries.prefix(4).flatMap { [$0.item.background, MetaPreview.cinemetaLogo(for: $0.item.metaID)] })
        }
    }
}

/// One title being watched: its backdrop and logo, which open its page, where it stands,
/// and Resume, which starts it as Continue Watching does.
private struct ResumePage: View {
    let entry: ContinueWatchingRow.Entry
    let tone: Color

    var body: some View {
        let item = entry.item
        let title = MetaPreview(id: item.metaID, type: item.type, name: item.title,
                                poster: item.poster, background: item.background)
        ZStack(alignment: .bottomLeading) {
            NavigationLink(value: title) {
                Artwork(url: item.background, fallbacks: [item.thumbnail].compactMap { $0 }, alignment: .top)
                    .overlay { fade }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The logo opens the same page; one stop is enough.
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink(value: title) {
                    TitleLogo(logo: MetaPreview.cinemetaLogo(for: item.metaID), name: item.title, maxHeight: 90, isWhite: true)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 250, alignment: .leading)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    if let episode = [item.episodeCode, item.episodeTitle].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                        Text(episode)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Text(entry.timeLeft ?? "New episode")
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 14)
                if let progress = entry.progress {
                    WatchProgressBar(progress: progress, inset: 0)
                        .frame(height: 4)
                        .padding(.top, 12)
                }
                NavigationLink(value: entry.route) {
                    Label(entry.progress == nil ? "Play" : "Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityHint(item.accessibilityTitle)
                .padding(.top, 16)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 8)
        }
        .contextMenu { ContinueWatchingActions(item: item) }
    }

    /// Dark under the status bar, then clear, then into the room's tone under the text.
    private var fade: some View {
        LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.22),
                               .init(color: tone.opacity(0), location: 0.45), .init(color: tone, location: 0.97)],
                       startPoint: .top, endPoint: .bottom)
            .animation(.easeOut(duration: 0.6), value: tone)
    }
}

/// Under Home's hero when no addon provides streams: browsing works without one, so this
/// says what one adds and offers the two ways to get one.
struct PlaybackAddonCard: View {
    @State private var isAddingAddon = false
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add a playback addon to watch")
                .font(.headline)
            Text("Films, series, search and IMDb ratings are built in. Streams come from the addons you install.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { isAddingAddon = true } label: { Text("Add Addon").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle())
                Button { isImporting = true } label: { Text("Import Setup").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle(isTranslucent: true))
            }
            .controlSize(.small)
            .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 14))
        .padding(.horizontal, Metrics.gutter)
        .sheet(isPresented: $isAddingAddon) { closable(AddonsSettingsView(), isPresented: $isAddingAddon) }
        .sheet(isPresented: $isImporting) { closable(ImportSetupView(), isPresented: $isImporting) }
    }

    private func closable(_ page: some View, isPresented: Binding<Bool>) -> some View {
        NavigationStack {
            page.toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented.wrappedValue = false }
                }
            }
        }
    }
}
#endif
