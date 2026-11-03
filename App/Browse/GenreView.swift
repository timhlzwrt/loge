import LogeCore
import SwiftUI

/// Movie genres on Home, each a still from a defining film with the genre's name over it.
struct GenreRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text("Genres")
                .font(.sectionTitle)
                .padding(.horizontal, Metrics.gutter)
            ScrollView(.horizontal) {
                LazyHStack(spacing: Metrics.rowSpacing) {
                    ForEach(DiscoveryCatalogs.genres) { genre in
                        NavigationLink(value: genre) {
                            GenreTile(genre: genre)
                        }
                        #if os(tvOS)
                        .buttonStyle(.card)
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                #if os(tvOS)
                // Room for the focus lift, which would otherwise be clipped.
                .padding(.vertical, 20)
                #endif
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

private struct GenreTile: View {
    let genre: DiscoveryCatalogs.Genre

    var body: some View {
        Artwork(url: genre.still)
            // The small still arrives almost at once; the sharp one covers it when it lands.
            .background { Artwork(url: genre.stillPreview) }
            .overlay {
                // Keeps the name legible over bright stills.
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                Text(genre.name)
                    .font(.cardTitle)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 1)
                    .padding(WatchProgressBar.inset)
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(.rect(cornerRadius: Metrics.cardRadius))
            .accessibilityElement()
            .accessibilityLabel(genre.name)
    }

    private var width: CGFloat { Metrics.posterWidth * 1.6 }
}

/// One genre's movies: what's popular now and the best of all time. Each row's title opens it as a grid.
struct GenreView: View {
    let genre: DiscoveryCatalogs.Genre

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                CatalogRow(source: genre.popular, isPrimary: true)
                CatalogRow(source: genre.bestOfAllTime)
            }
            .padding(.vertical, 16)
        }
        .background(Color.canvas)
        .navigationTitle(genre.name)
    }
}
