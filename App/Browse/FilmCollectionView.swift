import MediaCore
import SwiftUI

struct DiscoveryCollectionRow: View {
    @Environment(TMDBAccount.self) private var tmdb
    let title: String
    let collections: [FilmCollection]
    var onFocus: (FilmCollection) -> Void = { _ in }
    @FocusState private var focusedCollection: FilmCollection?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text(title)
                .font(.sectionTitle)
                .padding(.horizontal, Metrics.gutter)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.rowSpacing) {
                    ForEach(collections) { collection in
                        NavigationLink {
                            if tmdb.isConfigured, let id = collection.tmdbPersonID {
                                PersonView(route: PersonRoute(person: Person(
                                    name: collection.name, roles: [.director], tmdbID: id, portraitURL: collection.artworkURL)))
                            } else {
                                FilmCollectionView(collection: collection)
                            }
                        } label: {
                            CollectionTile(collection: collection)
                        }
                        #if os(tvOS)
                        .buttonStyle(.card)
                        #else
                        .buttonStyle(.plain)
                        #endif
                        .focused($focusedCollection, equals: collection)
                    }
                }
                #if os(tvOS)
                .padding(.vertical, 20)
                #endif
            }
            .contentMargins(.horizontal, Metrics.gutter, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .accessibilityIdentifier(collections.first?.isFestival == true ? "festival-collections" : "director-collections")
        }
        .onChange(of: focusedCollection) {
            if let focusedCollection { onFocus(focusedCollection) }
        }
        .task(id: "\(tmdb.revision):\(focusedCollection?.id ?? "")") {
            guard tmdb.isConfigured, let id = focusedCollection?.tmdbPersonID else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            // Reused by the person page; a preload failure leaves its retry flow intact.
            _ = try? await tmdb.personDetails(id: id)
        }
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
                Image(logo, bundle: .main)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
            } else {
                Artwork(url: collection.artworkURL)
            }
        }
        .accessibilityHidden(true)
    }
}

struct FilmCollectionView: View {
    let collection: FilmCollection
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
                            .buttonStyle(.card)
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
        .navigationTitle(collection.name)
        .task(id: phase) {
            guard phase == .loading else { return }
            do {
                let loaded = try await FilmCollectionClient.shared.films(in: collection)
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
                        collectionImage.aspectRatio(16 / 9, contentMode: .fit)
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
            #if os(tvOS)
            Text(artworkCredit)
                .font(.caption)
                .foregroundStyle(.secondary)
            #else
            Link(artworkCredit, destination: collection.artworkCreditURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .underline()
                .frame(minHeight: 44, alignment: .leading)
            #endif
        }
    }

    private var collectionImage: some View {
        CollectionArtwork(collection: collection)
            .clipShape(.rect(cornerRadius: Metrics.posterRadius))
            .accessibilityHidden(true)
    }

    private var artworkCredit: String {
        collection.isFestival ? "Logo: \(collection.artworkCredit)" : "Photo: \(collection.artworkCredit) · Cropped"
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
            Text("Source: Wikidata · Records may be incomplete.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
