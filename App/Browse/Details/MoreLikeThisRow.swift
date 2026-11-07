import LogeCore
import SwiftUI

/// TMDB's recommendations for the title on screen. They carry TMDB IDs, so each opens
/// through `TMDBTitleView`, which finds the IMDb ID the addons and library need.
/// Hidden while TMDB details load, without a token, and when TMDB has nothing to suggest.
struct MoreLikeThisRow: View {
    let titles: [TMDBCreditTitle]

    var body: some View {
        if !titles.isEmpty {
            row
        }
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text("More Like This")
                .font(.sectionTitle)
                .padding(.horizontal, Metrics.gutter)
            HorizontalShelf("More Like This") {
                LazyHStack(alignment: .top, spacing: Metrics.rowSpacing) {
                    ForEach(titles) { title in
                        NavigationLink(value: title) {
                            TMDBCreditTile(title: title)
                                .frame(width: Metrics.posterWidth)
                                // A two-line title would otherwise shrink its poster to share the row's height.
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        #if os(tvOS)
                        .buttonStyle(.borderless)
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                #if os(tvOS)
                .padding(.vertical, 20)
                #endif
            }
            .scrollClipDisabled()
        }
        .accessibilityIdentifier("more-like-this")
    }
}
