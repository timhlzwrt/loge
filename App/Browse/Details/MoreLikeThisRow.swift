import LogeCore
import SwiftUI

/// TMDB's recommendations for the title on screen. They carry TMDB IDs, so each opens
/// through `TMDBTitleView`, which finds the IMDb ID the addons and library need.
/// Hidden while TMDB details load, without a token, and when TMDB has nothing to suggest.
struct MoreLikeThisRow: View {
    let titles: [TMDBCreditTitle]

    var body: some View {
        if !titles.isEmpty {
            TMDBTitleShelf(heading: "More Like This", titles: titles)
                .accessibilityIdentifier("more-like-this")
        }
    }
}

/// The film series a movie belongs to, in release order, so it's plain which one comes next.
struct CollectionRow: View {
    let collection: TMDBCollection
    /// The film on screen, which keeps its place in the order.
    let currentID: Int?

    var body: some View {
        // A series of one is a sequel TMDB expects but doesn't list yet.
        if collection.titles.count > 1 {
            TMDBTitleShelf(heading: collection.name, titles: collection.titles, currentID: currentID)
                .accessibilityIdentifier("collection")
        }
    }
}

private struct TMDBTitleShelf: View {
    let heading: String
    let titles: [TMDBCreditTitle]
    /// Drawn in its place but dimmed and not a link: it's the page already open.
    var currentID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text(heading)
                .font(.sectionTitle)
                .padding(.horizontal, Metrics.gutter)
            HorizontalShelf(heading) {
                LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                    ForEach(titles) { title in
                        if title.tmdbID == currentID {
                            tile(title)
                                .opacity(0.4)
                                .accessibilityValue("This film")
                        } else {
                            NavigationLink(value: title) { tile(title) }
                                #if os(tvOS)
                                .buttonStyle(.borderless)
                                #else
                                .buttonStyle(.plain)
                                #endif
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                #if os(tvOS)
                .padding(.vertical, 20)
                #endif
            }
            .scrollClipDisabled()
        }
    }

    private func tile(_ title: TMDBCreditTitle) -> some View {
        TMDBCreditTile(title: title, showsMediaType: false)
            .frame(width: Metrics.posterWidth)
            // A two-line title would otherwise shrink its poster to share the row's height.
            .fixedSize(horizontal: false, vertical: true)
    }
}
