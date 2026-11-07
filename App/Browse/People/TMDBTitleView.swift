import LogeCore
import SwiftUI

/// "Movie · 2014" and the person's roles on it, under a credit's name.
struct CreditMetaLines: View {
    let title: TMDBCreditTitle
    var roleLineLimit: Int?

    var body: some View {
        Text([title.type == MediaType.series ? "Series" : "Movie", title.releaseDate.map { String($0.prefix(4)) }]
            .compactMap { $0 }.joined(separator: " · "))
            .font(.metaLine)
            .foregroundStyle(.secondary)
        if !title.roles.isEmpty {
            Text(title.roles.joined(separator: ", "))
                .font(.metaLine)
                .foregroundStyle(.secondary)
                .lineLimit(roleLineLimit)
        }
    }
}

/// Resolve one selected credit; numeric TMDB identities never enter playback or saved lists.
struct TMDBTitleView: View {
    let title: TMDBCreditTitle
    @Environment(TMDBAccount.self) private var tmdb
    @State private var state = LoadState.loading
    @State private var attempt = 0

    private enum LoadState {
        case loading
        case loaded(MetaPreview)
        case unavailable
        case failed(String)
    }

    private struct LoadKey: Hashable {
        let revision: Int
        let attempt: Int
    }

    var body: some View {
        Group {
            if case .loaded(let preview) = state {
                MetaDetailView(preview: preview)
                    .accessibilityIdentifier("title-resolved-detail")
            } else {
                metadata
            }
        }
        .background(Color.canvas)
        // The resolved page names the title in its own hero, like any other details page.
        .navigationTitle(isResolved ? "" : title.name)
        .task(id: LoadKey(revision: tmdb.revision, attempt: attempt)) {
            state = .loading
            do {
                let imdbID = try await tmdb.imdbID(tmdbID: title.tmdbID, type: title.type)
                try Task.checkCancellation()
                if let imdbID, imdbID.wholeMatch(of: /tt\d+/) != nil {
                    state = .loaded(MetaPreview(
                        id: imdbID, type: title.type, name: title.name, poster: title.posterURL,
                        releaseInfo: title.releaseDate.map { String($0.prefix(4)) },
                        background: title.backgroundURL, description: title.overview))
                } else {
                    state = .unavailable
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = switch error as? TMDBError {
                case .unauthorized: "Connect TMDB in Settings to load this title's details."
                case .rateLimited: "TMDB is busy. Try again in a few minutes."
                default: "Couldn't load this title's details."
                }
                state = .failed(message)
            }
        }
    }

    private var metadata: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    Artwork(url: title.posterURL)
                        .frame(width: Metrics.posterWidth, height: Metrics.posterWidth * 1.5)
                        .clipShape(.rect(cornerRadius: Metrics.posterRadius))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title.name).font(.sectionTitle)
                        CreditMetaLines(title: title)
                    }
                }
                if let overview = title.overview {
                    Text(overview).font(.synopsis).foregroundStyle(.secondary)
                }
                switch state {
                case .loading:
                    ProgressView("Loading title…")
                case .unavailable:
                    Text("TMDB has no IMDb ID for this title. Playback and saving are unavailable.")
                        .font(.metaLine)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 12) {
                        Text(message).font(.metaLine).foregroundStyle(.secondary)
                        Button("Retry") { attempt += 1 }
                    }
                case .loaded:
                    EmptyView()
                }
                #if !os(tvOS)
                Link("View title on TMDB", destination: profileURL)
                    .font(.metaLine)
                    .frame(minHeight: 44)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 32)
        }
        .accessibilityIdentifier("title-metadata")
    }

    private var isResolved: Bool {
        if case .loaded = state { true } else { false }
    }

    private var profileURL: URL {
        let resource = title.type == MediaType.series ? "tv" : "movie"
        return URL(string: "https://www.themoviedb.org/\(resource)/\(title.tmdbID)")!
    }
}
