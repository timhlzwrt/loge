import LogeCore
import SwiftUI

/// A title's IMDb rating from the addon, behind IMDb's mark. It opens the title on IMDb, which
/// the Apple TV, having no browser, can't.
struct ScoresLine: View {
    let id: String
    let imdbRating: String?
    #if os(iOS)
    @ScaledMetric(relativeTo: .footnote) private var markHeight: CGFloat = 12
    #elseif os(tvOS)
    private let markHeight: CGFloat = 21
    #else
    private let markHeight: CGFloat = 11
    #endif

    private var rating: String? {
        guard let imdbRating, let score = Double(imdbRating), score.isFinite, score > 0, score <= 10 else { return nil }
        return imdbRating
    }

    var body: some View {
        if let rating {
            Group {
                #if os(tvOS)
                label(rating)
                #else
                if let destination = ReviewLinks.imdb(imdbID: id) {
                    Link(destination: destination) { label(rating).titleTapTarget() }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens IMDb in your browser")
                        .help("Open on IMDb")
                } else {
                    label(rating)
                }
                #endif
            }
            // The wide layouts draw this over artwork, like the line of facts beside it.
            .shadow(color: .black.opacity(0.5), radius: 6)
        }
    }

    private func label(_ rating: String) -> some View {
        HStack(spacing: markHeight * 0.4) {
            Image(decorative: "ScoreIMDb")
                .resizable()
                .scaledToFit()
                // IMDb's plate is wide and low; this matches the size it had beside the other marks.
                .frame(height: markHeight * 0.95)
            Text(rating)
                .font(.metaLine.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("IMDb \(rating) out of 10")
    }
}
