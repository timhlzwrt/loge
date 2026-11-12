import Accessibility
import LogeCore
import SwiftUI

/// Finds what to play after the current episode: the next released episode, from the
/// same addon, preferring the same release and quality (its binge group).
enum NextEpisode {
    static func request(after current: PlaybackRequest, episodes: [Video]) async throws -> PlaybackRequest? {
        guard let item = current.item, let providerURL = current.providerURL,
              let video = LibraryStore.episode(after: item.id, in: episodes), video.isReleased()
        else { return nil }

        let streams = try await AddonClient(manifestURL: providerURL).streams(type: item.type, id: video.id)
            .filter {
                StreamDetails($0).permitsAutomaticPlayback(
                    type: item.type, maximumFileSize: PlaybackPreferences.maximumAutomaticFileSize)
            }
        guard let stream = StreamSource.continuing(bingeGroup: current.bingeGroup, in: streams)
            ?? streams.first(where: { $0.playbackURL != nil }),
            let url = stream.playbackURL
        else { return nil }

        let next = item.episode(video)
        return PlaybackRequest(
            title: [next.title, next.episodeCode].compactMap { $0 }.joined(separator: " · "),
            url: url,
            headers: stream.requestHeaders,
            item: next,
            providerURL: providerURL,
            bingeGroup: stream.behaviorHints?.bingeGroup,
            subtitles: stream.subtitles ?? [],
            filename: stream.behaviorHints?.filename
        )
    }

    /// When the "Next Episode" button appears: where the credits usually start.
    static func offerTime(duration: Double) -> Double {
        max(duration * 0.9, duration - min(max(duration * 0.04, 30), 150))
    }
}

/// A glass card in the corner near the end of an episode: the next one's still and title,
/// with Play Now and Cancel. Once the episode has ended, a countdown plays it unless cancelled.
struct NextEpisodeOverlay: View {
    let next: PlaybackRequest
    let hasEnded: Bool
    let play: () -> Void
    /// The player keeps what was cancelled: on tvOS it decides where focus can go, and a card
    /// that only hid itself left focus aimed at buttons that were gone.
    let cancel: () -> Void
    #if os(tvOS)
    /// Which button has focus. The card sits on the remote's surface, so the player moves focus
    /// here itself, as the focus engine can't.
    let focus: FocusState<Focus?>.Binding

    /// Also used by the end card: `play` is its first button and `cancel` its second.
    enum Focus: Hashable { case play, cancel }
    #endif

    @State private var secondsLeft = 10

    var body: some View {
        PlayerCard(still: next.item?.thumbnail ?? next.item?.background,
                   caption: hasEnded ? "Up Next · in \(secondsLeft) s" : "Up Next",
                   title: episodeTitle) {
            Button("Play Now", action: play)
                .buttonStyle(.glassProminent)
                .foregroundStyle(.black)
                #if os(tvOS)
                .focused(focus, equals: .play)
                #endif
            Button("Cancel", action: cancel)
                .buttonStyle(.glass)
                #if os(macOS)
                .tint(.clear)
                #endif
                #if os(tvOS)
                .focused(focus, equals: .cancel)
                #endif
        }
        .task(id: hasEnded) {
            guard hasEnded else { return }
            secondsLeft = 10
            AccessibilityNotification.Announcement("Next episode in 10 seconds").post()
            while secondsLeft > 0 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                secondsLeft -= 1
            }
            play()
        }
    }

    /// "7 · The Case of the Winged Scarab", or the request's title when the episode has none.
    private var episodeTitle: String {
        guard let item = next.item, let title = item.episodeTitle else { return next.title }
        return [item.episode.map(String.init), title].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Where Up Next would be, once something with nothing after it has ended: what finished, with
/// Start Over, rather than a still frame that says nothing. Apple TV adds Close, which elsewhere
/// is already on screen (the player's close button, the Mac's window).
struct FinishedOverlay: View {
    let request: PlaybackRequest
    let startOver: () -> Void
    #if os(tvOS)
    let close: () -> Void
    let focus: FocusState<NextEpisodeOverlay.Focus?>.Binding
    #endif

    var body: some View {
        PlayerCard(still: request.item?.thumbnail ?? request.item?.background,
                   caption: "Finished",
                   title: request.item?.title ?? request.title) {
            Button("Start Over", action: startOver)
                .buttonStyle(.glassProminent)
                .foregroundStyle(.black)
                #if os(tvOS)
                .focused(focus, equals: .play)
                #endif
            #if os(tvOS)
            Button("Close", action: close)
                .buttonStyle(.glass)
                .focused(focus, equals: .cancel)
            #endif
        }
    }
}

/// The glass card both of those use: a still when there is one, a caption over a title, and
/// two buttons, in the corner the controls leave free.
private struct PlayerCard<Buttons: View>: View {
    let still: String?
    let caption: String
    let title: String
    @ViewBuilder let buttons: Buttons
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isPortraitPhone: Bool { horizontalSizeClass == .compact && verticalSizeClass == .regular }
    #endif

    var body: some View {
        HStack(spacing: 12) {
            // Without a still the card is just its text, rather than an empty frame.
            if let still {
                Artwork(url: still)
                    .frame(width: Self.stillWidth, height: Self.stillWidth * 9 / 16)
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(caption)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 8) { buttons }
                    #if !os(tvOS)
                    .controlSize(.small)
                    #endif
                    .padding(.top, 4)
            }
            .frame(maxWidth: Self.textWidth, alignment: .leading)
        }
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: Self.radius))
        #if os(iOS)
        // The top corner is the one the controls leave free; at the bottom the card would
        // cover the play button on a phone in landscape. A portrait phone is too narrow
        // to share the row with the close button, so it goes below it.
        .padding(.horizontal, 20)
        .padding(.top, isPortraitPhone ? 68 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        #else
        .padding(24)
        // Clears the timeline at the bottom of the controls.
        .padding(.bottom, Self.controlsClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        #endif
    }

    #if os(tvOS)
    private static var stillWidth: CGFloat { 240 }
    private static var textWidth: CGFloat { 420 }
    private static var radius: CGFloat { 30 }
    private static var controlsClearance: CGFloat { 70 }
    #else
    private static var stillWidth: CGFloat { 128 }
    private static var textWidth: CGFloat { 200 }
    private static var radius: CGFloat { 18 }
    #if os(macOS)
    private static var controlsClearance: CGFloat { 70 }
    #endif
    #endif
}
