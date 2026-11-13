import LogeCore
import SwiftUI

/// A title's scores, each behind its site's mark: IMDb's from the addon, Letterboxd's and the
/// Tomatometer from MDBList once that's connected. Each opens the title on its site, which
/// the Apple TV, having no browser, can't.
struct ScoresLine: View {
    let id: String
    let type: String
    let imdbRating: String?
    let scores: TitleScores?
    #if os(iOS)
    @ScaledMetric(relativeTo: .footnote) private var markHeight: CGFloat = 12
    #elseif os(tvOS)
    private let markHeight: CGFloat = 21
    #else
    private let markHeight: CGFloat = 11
    #endif

    private struct Score: Identifiable {
        let id: String
        let mark: String
        /// IMDb's plate and Letterboxd's dots are wide and low; next to the tomato at full
        /// height they'd look a size larger.
        let markScale: CGFloat
        let value: String
        let spoken: String
        let site: String
        let destination: URL?
    }

    private var entries: [Score] {
        var entries: [Score] = []
        if let imdbRating, let score = Double(imdbRating), score.isFinite, score > 0, score <= 10 {
            entries.append(Score(id: "imdb", mark: "ScoreIMDb", markScale: 0.95, value: imdbRating,
                                 spoken: "IMDb \(imdbRating) out of 10", site: "IMDb",
                                 destination: ReviewLinks.imdb(imdbID: id)))
        }
        if let letterboxd = scores?.letterboxd {
            let value = letterboxd.formatted(.number.precision(.fractionLength(1)).locale(.interface))
            entries.append(Score(id: "letterboxd", mark: "ScoreLetterboxd", markScale: 0.75, value: value,
                                 spoken: "Letterboxd \(value) out of 5", site: "Letterboxd",
                                 destination: ReviewLinks.letterboxd(imdbID: id, type: type)))
        }
        if let tomatometer = scores?.tomatometer {
            entries.append(Score(id: "tomatometer", mark: "ScoreRottenTomatoes", markScale: 1.15, value: "\(tomatometer)%",
                                 spoken: "Tomatometer \(tomatometer) percent", site: "Rotten Tomatoes",
                                 destination: scores?.rottenTomatoesURL))
        }
        return entries
    }

    var body: some View {
        let entries = entries
        if !entries.isEmpty {
            HStack(spacing: markHeight) {
                ForEach(entries) { score in
                    #if os(tvOS)
                    label(score)
                    #else
                    if let destination = score.destination {
                        Link(destination: destination) { label(score).titleTapTarget() }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens \(score.site) in your browser")
                            .help("Open on \(score.site)")
                    } else {
                        label(score)
                    }
                    #endif
                }
            }
            // The wide layouts draw this over artwork, like the line of facts beside it.
            .shadow(color: .black.opacity(0.5), radius: 6)
        }
    }

    private func label(_ score: Score) -> some View {
        HStack(spacing: markHeight * 0.4) {
            Image(decorative: score.mark)
                .resizable()
                .scaledToFit()
                .frame(height: markHeight * score.markScale)
            Text(score.value)
                .font(.metaLine.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.spoken)
    }
}
