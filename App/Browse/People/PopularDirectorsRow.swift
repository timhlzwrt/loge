import LogeCore
import SwiftUI

struct PopularDirectorsRow: View {
    @Environment(TMDBAccount.self) private var tmdb
    @State private var directors: [TMDBPopularDirector] = []
    @State private var phase = Phase.loading
    @State private var attempt = 0
    var onFocus: (TMDBPopularDirector) -> Void = { _ in }
    var onFallbackFocus: (FilmCollection) -> Void = { _ in }

    private enum Phase { case loading, loaded, unauthorized, unavailable }

    var body: some View {
        if !tmdb.isConfigured {
            selectedDirectors
        } else {
            Group {
                switch phase {
                // An optional shelf: when TMDB can't fill it, the curated directors stand in
                // rather than an error line on Home. Only a rejected token is the user's to fix.
                case .unavailable:
                    selectedDirectors
                case .loaded where directors.isEmpty:
                    selectedDirectors
                default:
                    shelf
                }
            }
            .task(id: "\(tmdb.revision):\(attempt)") {
                phase = .loading
                do {
                    let result = try await tmdb.popularDirectors()
                    try Task.checkCancellation()
                    directors = result
                    phase = .loaded
                } catch {
                    guard !Task.isCancelled else { return }
                    phase = error as? TMDBError == .unauthorized ? .unauthorized : .unavailable
                }
            }
        }
    }

    private var selectedDirectors: some View {
        DiscoveryCollectionRow(title: "Selected Directors", collections: FilmCollection.directors, onFocus: onFallbackFocus)
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text("Popular Directors").font(.sectionTitle).padding(.horizontal, Metrics.gutter)
            if phase == .unauthorized {
                HStack {
                    Text("TMDB didn't accept the saved token. Check Settings.").foregroundStyle(.secondary)
                    Button("Retry") { attempt += 1 }
                }
                .padding(.horizontal, Metrics.gutter)
            } else {
                HorizontalShelf("directors") {
                    HStack(alignment: .top, spacing: Metrics.rowSpacing) {
                        if phase == .loading {
                            placeholders
                        } else {
                            ForEach(directors) { director in
                                NavigationLink(value: PersonRoute(person: Person(name: director.name, roles: [.director],
                                    tmdbID: director.id, portraitURL: director.portraitURL))) {
                                    tile(director)
                                }
                                #if os(tvOS)
                                .buttonStyle(.borderless)
                                #else
                                .buttonStyle(.plain)
                                #endif
                            }
                        }
                    }
                    #if os(tvOS)
                    .padding(.vertical, 20)
                    #endif
                    .padding(.horizontal, Metrics.gutter)
                }
                .scrollClipDisabled()
                .accessibilityIdentifier("popular-directors")
            }
        }
    }

    private func tile(_ director: TMDBPopularDirector) -> some View {
        VStack(alignment: .leading, spacing: Metrics.liftedCaptionSpacing) {
            Artwork(url: director.portraitURL)
                .frame(width: Self.width, height: Self.height)
                .clipShape(.rect(cornerRadius: Metrics.posterRadius))
                #if os(tvOS)
                // Only the portrait lifts, as on credit tiles; a card around the text clipped its first letters.
                .hoverEffect(.highlight)
                #endif
            Text(director.name).font(.cardTitle).lineLimit(2)
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        #if os(tvOS)
        // Each tile watches its own focus, so a move updates the two tiles involved, not the row.
        .modifier(ReportsFocus { onFocus(director) })
        .modifier(PrefetchesFilmography(personID: director.id))
        #endif
    }

    /// The tiles' size while loading, so Home doesn't jump when the portraits arrive.
    private var placeholders: some View {
        ForEach(0..<8, id: \.self) { _ in
            VStack(alignment: .leading, spacing: Metrics.liftedCaptionSpacing) {
                RoundedRectangle(cornerRadius: Metrics.posterRadius)
                    .fill(.white.opacity(0.06))
                    .frame(width: Self.width, height: Self.height)
                Text(" ").font(.cardTitle)
            }
        }
        .accessibilityHidden(true)
    }

    private static var width: CGFloat { Metrics.posterWidth * 1.15 }
    #if os(tvOS)
    /// A little shorter than elsewhere, so the room the focus lift needs under the portrait doesn't
    /// make the row taller: at the end of Home, that scrolled the row's title under the header.
    private static var height: CGFloat { Metrics.posterWidth * 1.4 }
    #else
    private static var height: CGFloat { Metrics.posterWidth * 1.44 }
    #endif
}

#if os(tvOS)
/// Loads a person's filmography once their tile has kept focus for a moment, so opening
/// it is quick. The person page reuses the same bounded cache, and a failure here leaves
/// its retry intact.
struct PrefetchesFilmography: ViewModifier {
    let personID: Int?
    @Environment(TMDBAccount.self) private var tmdb
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.task(id: isFocused) {
            guard isFocused, let personID else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            _ = try? await tmdb.personDetails(id: personID)
        }
    }
}
#endif
