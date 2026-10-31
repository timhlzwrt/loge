import MediaCore
import SwiftUI

/// Finds what to play after the current episode: the next released episode, from the
/// same addon, preferring the same release and quality (its binge group).
enum NextEpisode {
    static func request(after current: PlaybackRequest, episodes: [Video]) async throws -> PlaybackRequest? {
        guard let item = current.item, let providerURL = current.providerURL,
              let video = LibraryStore.episode(after: item.id, in: episodes), video.isReleased()
        else { return nil }

        let streams = try await AddonClient(manifestURL: providerURL).streams(type: item.type, id: video.id)
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
        duration - min(max(duration * 0.04, 30), 150)
    }
}

/// "Next Episode" in the corner near the end of an episode; once it has ended,
/// a countdown that starts the next one unless cancelled.
struct NextEpisodeOverlay: View {
    let nextTitle: String
    let hasEnded: Bool
    let play: () -> Void

    @State private var secondsLeft = 10
    @State private var cancelled = false

    var body: some View {
        if !cancelled {
            VStack(alignment: .trailing, spacing: 10) {
                Text(nextTitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                HStack(spacing: 12) {
                    if hasEnded {
                        Button("Cancel") { cancelled = true }
                            #if !os(tvOS)
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            #endif
                    }
                    Button(action: play) {
                        Label(hasEnded ? "Next Episode in \(secondsLeft)" : "Next Episode", systemImage: "forward.end.fill")
                            .font(.headline)
                            .monospacedDigit()
                            #if !os(tvOS)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.white, in: .capsule)
                            .foregroundStyle(.black)
                            #endif
                    }
                    #if !os(tvOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
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
}
