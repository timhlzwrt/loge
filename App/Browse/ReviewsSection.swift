import LogeCore
import SwiftUI

/// Provider links rather than unlicensed review excerpts or inferred critic scores.
struct ReviewsSection: View {
    let preview: MetaPreview

    var body: some View {
        if let critics = ReviewLinks.critics(imdbID: preview.id) {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Reviews").font(.sectionTitle)
                #if os(tvOS)
                Text("Read reviews on your phone or computer.")
                    .foregroundStyle(.secondary)
                Text("Critics · imdb.com/title/\(preview.id)/externalreviews")
                    .font(.subheadline)
                if ReviewLinks.letterboxd(imdbID: preview.id, type: preview.type) != nil {
                    Text("Letterboxd · letterboxd.com/imdb/\(preview.id)")
                        .font(.subheadline)
                }
                #else
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { links(critics: critics) }
                    VStack(alignment: .leading, spacing: 8) { links(critics: critics) }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                Text("Opens the review provider in your browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
            .padding(.horizontal, Metrics.gutter)
        }
    }

    #if !os(tvOS)
    @ViewBuilder
    private func links(critics: URL) -> some View {
        Link("Critic reviews · IMDb", destination: critics)
            .frame(minHeight: 44)
            .underline()
        if let letterboxd = ReviewLinks.letterboxd(imdbID: preview.id, type: preview.type) {
            Link("Letterboxd reviews", destination: letterboxd)
                .frame(minHeight: 44)
                .underline()
        }
    }
    #endif
}
