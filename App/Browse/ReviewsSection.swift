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
                VStack(spacing: 0) {
                    reviewLink("Critic reviews", source: "IMDb", destination: critics)
                    if let letterboxd = ReviewLinks.letterboxd(imdbID: preview.id, type: preview.type) {
                        Divider()
                        reviewLink("Member reviews", source: "Letterboxd", destination: letterboxd)
                    }
                }
                #endif
            }
            .padding(.horizontal, Metrics.gutter)
        }
    }

    #if !os(tvOS)
    /// A row whose arrow says it leaves the app, in place of an underlined link and a note.
    private func reviewLink(_ title: String, source: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack {
                Text(title)
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text(source)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.synopsis)
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(source) in your browser")
    }
    #endif
}
