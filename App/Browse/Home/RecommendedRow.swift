import LogeCore
import SwiftUI

/// Titles TMDB recommends for what was recently watched or saved, ranked on the device
/// (`Recommendations`). Hidden without a TMDB token or before anything was watched or saved.
struct RecommendedRow: View {
    var onFocus: (MetaPreview) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library
    @Environment(TMDBAccount.self) private var tmdb
    @State private var titles: Result<[MetaPreview], Error>?
    @State private var attempt = 0

    private struct LoadKey: Hashable {
        let revision: Int
        let seeds: [Recommendations.Seed]
        let attempt: Int
    }

    var body: some View {
        let seeds = tmdb.isConfigured ? Recommendations.seeds(history: library.history, saved: library.saved) : []
        Group {
            if !seeds.isEmpty {
                switch titles {
                case .success(let metas) where metas.isEmpty:
                    EmptyView()
                case .success(let metas):
                    row(seeds: seeds) { posters(metas) }
                case .failure:
                    row(seeds: seeds) {
                        HStack {
                            Text("Couldn't load recommendations.")
                                .foregroundStyle(.secondary)
                            Button("Retry") { attempt += 1 }
                        }
                        .padding(.horizontal, Metrics.gutter)
                    }
                case nil:
                    row(seeds: seeds) { placeholders }
                }
            }
        }
        .task(id: LoadKey(revision: tmdb.revision, seeds: seeds, attempt: attempt)) {
            guard !seeds.isEmpty else { return }
            // Anything already watched, started or saved is known to the viewer.
            let known = Set(library.progress.values.map(\.item.metaID))
                .union(library.saved.map(\.id))
                .union(library.lists.flatMap(\.titles).map(\.id))
            do {
                let metas = try await tmdb.recommendations(for: seeds, excluding: known)
                try Task.checkCancellation()
                // The previous row stays up while a changed history reloads it.
                titles = .success(metas)
            } catch {
                guard !Task.isCancelled else { return }
                titles = .failure(error)
            }
        }
    }

    private func row(seeds: [Recommendations.Seed], @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recommended")
                    .font(.sectionTitle)
                // Says which of the viewer's own titles these come from.
                if let basis = basis(of: seeds) {
                    Text(basis)
                        .font(.metaLine)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            content()
        }
    }

    /// "Based on Interstellar, Arrival and 3 more"
    private func basis(of seeds: [Recommendations.Seed]) -> String? {
        let names = seeds.compactMap { seed in
            library.progress.values.first { $0.item.metaID == seed.imdbID }?.item.title
                ?? library.saved.first { $0.id == seed.imdbID }?.name
        }
        guard !names.isEmpty else { return nil }
        let shown = names.count > 3 ? Array(names.prefix(2)) + ["\(names.count - 2) more"] : names
        return "Based on " + shown.formatted(.list(type: .and).locale(.interface))
    }

    private func posters(_ metas: [MetaPreview]) -> some View {
        HorizontalShelf("Recommended") {
            LazyHStack(spacing: Metrics.rowSpacing) {
                ForEach(metas) { meta in
                    NavigationLink(value: meta) {
                        PosterTile(meta: meta)
                            #if os(tvOS)
                            .modifier(ReportsFocus { onFocus(meta) })
                            #endif
                    }
                    .tileButtonStyle()
                }
            }
            .padding(.horizontal, Metrics.gutter)
            #if os(tvOS)
            .padding(.vertical, 20)
            #endif
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("recommended-row")
    }

    private var placeholders: some View {
        HStack(spacing: Metrics.rowSpacing) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Metrics.posterRadius)
                    .fill(.white.opacity(0.06))
                    .frame(width: Metrics.posterWidth, height: Metrics.posterWidth * 1.5)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .accessibilityLabel("Loading recommendations")
    }
}
