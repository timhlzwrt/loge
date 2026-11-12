import LogeCore
import SwiftUI

struct DiscoveryCollectionRow: View {
    @Environment(TMDBAccount.self) private var tmdb
    let title: String
    let collections: [FilmCollection]
    var onFocus: (FilmCollection) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text(title)
                .font(.sectionTitle)
                .padding(.horizontal, Metrics.gutter)
            HorizontalShelf(title) {
                HStack(alignment: .top, spacing: Metrics.rowSpacing) {
                    ForEach(collections) { collection in
                        Group {
                            // Value links like the rest of the stack: a view-built destination
                            // left the film links inside it dead.
                            if tmdb.isConfigured, let id = collection.tmdbPersonID {
                                NavigationLink(value: PersonRoute(person: Person(
                                    name: collection.name, roles: [.director], tmdbID: id, portraitURL: collection.artworkURL))) {
                                    tile(collection)
                                }
                            } else {
                                NavigationLink(value: collection) {
                                    tile(collection)
                                }
                            }
                        }
                        #if os(tvOS)
                        .buttonStyle(.borderless)
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                #if os(tvOS)
                .padding(.vertical, 20)
                #endif
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollClipDisabled()
            .accessibilityIdentifier(collections.first?.isFestival == true ? "festival-collections" : "director-collections")
        }
    }

    private func tile(_ collection: FilmCollection) -> some View {
        CollectionTile(collection: collection)
            #if os(tvOS)
            // Each tile watches its own focus, so a move updates the two tiles involved, not the row.
            .modifier(ReportsFocus { onFocus(collection) })
            .modifier(PrefetchesFilmography(personID: tmdb.isConfigured ? collection.tmdbPersonID : nil))
            #endif
    }
}

/// Festival marks and director portraits give the two shelves distinct visual identities.
private struct CollectionTile: View {
    let collection: FilmCollection

    private var width: CGFloat {
        collection.isFestival ? Metrics.posterWidth * 1.65 : Metrics.posterWidth * 1.15
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CollectionArtwork(collection: collection)
                .frame(width: width, height: collection.isFestival ? width * 9 / 16 : width * 1.25)
                .clipShape(.rect(cornerRadius: Metrics.posterRadius))
                #if os(tvOS)
                // Only the artwork lifts, as on credit tiles; a card around the text clipped its first letters.
                .hoverEffect(.highlight)
                #endif
                .accessibilityHidden(true)
            Text(collection.name)
                .font(.cardTitle)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if collection.isFestival {
                Text(collection.subtitle)
                    .font(.metaLine)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collection.name), \(collection.subtitle)")
    }
}

struct CollectionArtwork: View {
    let collection: FilmCollection

    var body: some View {
        Group {
            if let logo = collection.logoAssetName {
                // On the same quiet tile as missing artwork, so marks read as tappable like posters.
                Image(logo, bundle: .main)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.06))
            } else {
                Artwork(url: collection.artworkURL)
            }
        }
        .accessibilityHidden(true)
    }
}

struct FilmCollectionView: View {
    let collection: FilmCollection
    var client = FilmCollectionClient.shared

    var body: some View {
        if collection.isFestival {
            FestivalAwardsView(collection: collection, client: client)
        } else {
            RecordedCollectionView(collection: collection, client: client)
        }
    }
}

struct RecordedCollectionView: View {
    let collection: FilmCollection
    var client = FilmCollectionClient.shared
    @State private var films: [CollectionFilm] = []
    @State private var phase = Phase.loading
    @State private var failureMessage = "Couldn’t load this collection."

    private enum Phase: Equatable { case loading, loaded, failed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                switch phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                case .failed:
                    HStack {
                        Text(failureMessage).foregroundStyle(.secondary)
                        Button("Retry") { phase = .loading }
                    }
                case .loaded where films.isEmpty:
                    Text("No films are recorded for this collection yet.").foregroundStyle(.secondary)
                case .loaded:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing, alignment: .top)],
                              alignment: .leading, spacing: Metrics.rowSpacing) {
                        ForEach(films) { film in
                            NavigationLink(value: film.title) {
                                VStack(alignment: .leading, spacing: 6) {
                                    PosterTile(meta: film.title, width: nil)
                                        #if os(tvOS)
                                        .hoverEffect(.highlight)
                                        #endif
                                    Text(film.title.name)
                                        .font(.cardTitle)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    if let year = film.year {
                                        Text(String(year)).font(.metaLine).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            #if os(tvOS)
                            .buttonStyle(.borderless)
                            #else
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("collection-films")
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
        .background(Color.canvas)
        .pageTitle(collection.name)
        .task(id: phase) {
            guard phase == .loading else { return }
            do {
                let loaded = try await client.films(in: collection)
                try Task.checkCancellation()
                films = loaded
                phase = .loaded
            } catch is CancellationError {
                // The view was dismissed while loading.
            } catch {
                guard !Task.isCancelled else { return }
                failureMessage = error as? FilmCollectionClient.Failure == .rateLimited
                    ? "The film database is busy. Try again in a few minutes."
                    : "Couldn’t load this collection. Please try again."
                phase = .failed
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if collection.isFestival {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: Metrics.rowSpacing) {
                        collectionImage
                            .frame(width: Metrics.cardWidth, height: Metrics.cardWidth * 9 / 16)
                        heading.frame(minWidth: Metrics.cardWidth * 0.9, maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        // Short, so the winners start on the first screen of a phone.
                        collectionImage.frame(height: 120)
                        heading
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 20) {
                    collectionImage
                        .frame(width: Metrics.personSize * 1.4, height: Metrics.personSize * 1.75)
                    heading
                }
            }
        }
    }

    private var collectionImage: some View {
        CollectionArtwork(collection: collection)
            .clipShape(.rect(cornerRadius: Metrics.posterRadius))
            .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(collection.isFestival ? "\(collection.subtitle) winners" : collection.name)
                .font(.sectionTitle)
            Text(collection.isFestival ? "Recorded winners, newest first. Years show the award date." : "Directed films, newest first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let note = collection.awardScopeNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #if !os(tvOS)
            if let url = collection.officialResultsURL {
                Link(collection.officialResultsLabel, destination: url)
                    .foregroundStyle(.white.opacity(0.85))
                    .font(.subheadline)
                    .underline()
                    .frame(minHeight: 44)
            }
            #endif
        }
    }
}
