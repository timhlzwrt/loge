import MediaCore
import SwiftUI

/// A whole catalog as a grid, loading further pages as it scrolls and, where the
/// addon supports it, filtered by genre.
struct CatalogGridView: View {
    let source: CatalogSource

    @State private var genre: String?
    @State private var items: [MetaPreview] = []
    @State private var phase = Phase.loading
    @State private var reachedEnd = false

    private enum Phase: Equatable {
        case loading, idle, failed
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.rowSpacing)],
                      spacing: Metrics.rowSpacing) {
                ForEach(items) { meta in
                    NavigationLink(value: meta) {
                        PosterTile(meta: meta, width: nil)
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #else
                    .buttonStyle(.plain)
                    #endif
                    .onAppear {
                        // Start the next page a little before the end comes into view.
                        if meta.id == items.dropLast(6).last?.id || meta.id == items.last?.id {
                            Task { await loadNextPage() }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            footer
                .padding(.vertical, 24)
        }
        .scrollClipDisabled()
        // A new filter is a new list, so it starts from the top.
        .id(genre)
        .background(Color.canvas)
        .navigationTitle(genre.map { "\(source.title) · \($0)" } ?? source.title)
        .toolbar {
            if !source.catalog.genres.isEmpty {
                ToolbarItem {
                    genreMenu
                }
            }
        }
        .task(id: genre) {
            items = []
            reachedEnd = false
            phase = .idle
            await loadNextPage()
        }
    }

    private var genreMenu: some View {
        Menu {
            Picker("Genre", selection: $genre) {
                Text("All Genres").tag(String?.none)
                ForEach(source.catalog.genres, id: \.self) { Text($0).tag(Optional($0)) }
            }
        } label: {
            Label("Genre", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .failed:
            VStack(spacing: 8) {
                Text("Couldn't load more of \(source.title).")
                    .foregroundStyle(.secondary)
                Button("Retry") { Task { await loadNextPage() } }
            }
            .frame(maxWidth: .infinity)
        case .idle where items.isEmpty && reachedEnd:
            ContentUnavailableView("Nothing here", systemImage: "square.grid.2x2",
                                   description: Text("This catalog has no titles for this filter."))
        case .idle:
            EmptyView()
        }
    }

    private func loadNextPage() async {
        guard phase != .loading, !reachedEnd else { return }
        phase = .loading
        let requestedGenre = genre
        do {
            let page = try await source.items(genre: requestedGenre, skip: items.count)
            // The genre may have changed while this page was loading.
            guard requestedGenre == genre else { return }
            // Addons that ignore `skip` return the first page again; treat that as the end.
            let known = Set(items.map(\.id))
            let fresh = page.filter { !known.contains($0.id) }
            items += fresh
            reachedEnd = fresh.isEmpty || !source.catalog.supportsPaging
            phase = .idle
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed
        }
    }
}
