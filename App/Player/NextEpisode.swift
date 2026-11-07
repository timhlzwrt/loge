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

    @State private var secondsLeft = 10
    @State private var cancelled = false

    var body: some View {
        if !cancelled {
            HStack(spacing: 12) {
                Artwork(url: next.item?.thumbnail ?? next.item?.background)
                    .frame(width: Self.stillWidth, height: Self.stillWidth * 9 / 16)
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasEnded ? "Up Next · in \(secondsLeft) s" : "Up Next")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(episodeTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Button("Play Now", action: play)
                            .buttonStyle(.glassProminent)
                            .foregroundStyle(.black)
                        Button("Cancel") { cancelled = true }
                            .buttonStyle(.glass)
                            #if os(macOS)
                            .tint(.clear)
                            #endif
                    }
                    #if !os(tvOS)
                    .controlSize(.small)
                    #endif
                    .padding(.top, 4)
                }
                .frame(maxWidth: Self.textWidth, alignment: .leading)
            }
            .padding(10)
            .glassEffect(in: .rect(cornerRadius: Self.radius))
            .padding(24)
            // Clears the timeline at the bottom of the controls.
            .padding(.bottom, 70)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .task(id: hasEnded) {
                guard hasEnded else { return }
                secondsLeft = 10
                while secondsLeft > 0 {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    secondsLeft -= 1
                }
                play()
            }
        }
    }

    /// "7 · The Case of the Winged Scarab", or the request's title when the episode has none.
    private var episodeTitle: String {
        guard let item = next.item, let title = item.episodeTitle else { return next.title }
        return [item.episode.map(String.init), title].compactMap { $0 }.joined(separator: " · ")
    }

    #if os(tvOS)
    private static let stillWidth: CGFloat = 240
    private static let textWidth: CGFloat = 420
    private static let radius: CGFloat = 30
    #else
    private static let stillWidth: CGFloat = 128
    private static let textWidth: CGFloat = 200
    private static let radius: CGFloat = 18
    #endif
}
