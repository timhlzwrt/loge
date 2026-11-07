import LogeCore
import SwiftUI

struct PopularDirectorsRow: View {
    @Environment(TMDBAccount.self) private var tmdb
    @State private var directors: [TMDBPopularDirector] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var attempt = 0
    @FocusState private var focusedID: Int?
    var onFocus: (TMDBPopularDirector) -> Void = { _ in }
    var onFallbackFocus: (FilmCollection) -> Void = { _ in }

    var body: some View {
        if !tmdb.isConfigured {
            DiscoveryCollectionRow(title: "Selected Directors", collections: FilmCollection.directors, onFocus: onFallbackFocus)
        } else {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Popular Directors").font(.sectionTitle).padding(.horizontal, Metrics.gutter)
                if loading {
                    ProgressView("Loading directors…").padding(.horizontal, Metrics.gutter)
                } else if let failure {
                    HStack {
                        Text(failure).foregroundStyle(.secondary)
                        Button("Retry") { attempt += 1 }
                    }
                    .padding(.horizontal, Metrics.gutter)
                } else if directors.isEmpty {
                    Text("No directors in TMDB's current popular people results.")
                        .foregroundStyle(.secondary).padding(.horizontal, Metrics.gutter)
                } else {
                    HorizontalShelf("directors") {
                        HStack(alignment: .top, spacing: Metrics.rowSpacing) {
                            ForEach(directors) { director in
                                NavigationLink(value: PersonRoute(person: Person(name: director.name, roles: [.director],
                                    tmdbID: director.id, portraitURL: director.portraitURL))) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Artwork(url: director.portraitURL)
                                            .frame(width: Metrics.posterWidth * 1.15, height: Metrics.posterWidth * 1.44)
                                            .clipShape(.rect(cornerRadius: Metrics.posterRadius))
                                        Text(director.name).font(.cardTitle).lineLimit(2)
                                    }
                                    .frame(width: Metrics.posterWidth * 1.15, alignment: .leading)
                                    .accessibilityElement(children: .combine)
                                }
                                .tileButtonStyle()
                                .focused($focusedID, equals: director.id)
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
            .task(id: "\(tmdb.revision):\(attempt)") {
                loading = true
                failure = nil
                do {
                    let result = try await tmdb.popularDirectors()
                    try Task.checkCancellation()
                    directors = result
                    loading = false
                } catch {
                    guard !Task.isCancelled else { return }
                    loading = false
                    failure = error as? TMDBError == .unauthorized
                        ? "TMDB didn't accept the saved token. Check Settings."
                        : "Couldn't load popular directors. Try again."
                }
            }
            .task(id: "\(tmdb.revision):\(focusedID ?? 0)") {
                guard let focusedID else { return }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                // Opening the focused person reuses the same bounded filmography cache.
                _ = try? await tmdb.personDetails(id: focusedID)
            }
            .onChange(of: focusedID) {
                if let person = directors.first(where: { $0.id == focusedID }) { onFocus(person) }
            }
        }
    }
}
