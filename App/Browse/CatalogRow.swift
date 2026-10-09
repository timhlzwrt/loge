import MediaCore
import SwiftUI

/// A titled, horizontally scrolling row of posters from one addon catalog.
/// Rows with no results hide themselves, so search shows only catalogs that matched.
struct CatalogRow: View {
    let source: CatalogSource
    var search: String?
    /// Fills the tvOS home header with its first item before anything has focus.
    var isPrimary = false
    /// Called with whichever poster has focus; drives the tvOS home header.
    var onFocus: (MetaPreview) -> Void = { _ in }

    @State private var items: Result<[MetaPreview], Error>?
    @FocusState private var focusedID: MetaPreview.ID?

    var body: some View {
        Group {
            switch items {
            case .success(let metas) where metas.isEmpty:
                EmptyView()
            case .success(let metas):
                row { posters(metas) }
            case .failure:
                row {
                    HStack {
                        Text("Couldn't load \(source.title).")
                            .foregroundStyle(.secondary)
                        Button("Retry") { items = nil }
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
            case nil:
                row { placeholders }
            }
        }
        .task(id: TaskKey(search: search, isLoading: items == nil)) {
            guard items == nil else { return }
            do {
                let metas = try await source.items(search: search)
                items = .success(metas)
                if isPrimary, let first = metas.first {
                    onFocus(first)
                }
            } catch is CancellationError {
                // Scrolled away or the query changed; the next task reloads.
            } catch {
                items = .failure(error)
            }
        }
        .onChange(of: search) { items = nil }
        .onChange(of: focusedID) {
            if case .success(let metas) = items, let meta = metas.first(where: { $0.id == focusedID }) {
                onFocus(meta)
            }
        }
    }

    /// Restarts loading when the query changes or Retry clears the result.
    private struct TaskKey: Equatable {
        let search: String?
        let isLoading: Bool
    }

    private func row(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(source.title)
                    .font(.headline)
                Spacer()
                #if !os(tvOS)
                // On tvOS the row ends in a "See All" tile instead, which focus reaches naturally.
                if search == nil {
                    NavigationLink(value: source) {
                        HStack(spacing: 4) {
                            Text("See All")
                            Image(systemName: "chevron.right").imageScale(.small)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
            .padding(.horizontal, Metrics.gutter)
            content()
        }
    }

    private func posters(_ metas: [MetaPreview]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Metrics.rowSpacing) {
                ForEach(metas) { meta in
                    NavigationLink(value: meta) {
                        PosterTile(meta: meta)
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #else
                    .buttonStyle(.plain)
                    #endif
                    .focused($focusedID, equals: meta.id)
                }
                #if os(tvOS)
                if search == nil {
                    NavigationLink(value: source) {
                        Label("See All", systemImage: "square.grid.2x2")
                            .font(.headline)
                            .frame(width: Metrics.posterWidth, height: Metrics.posterWidth * 1.5)
                            .background(.white.opacity(0.06))
                    }
                    .buttonStyle(.card)
                }
                #endif
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

    private var placeholders: some View {
        HStack(spacing: Metrics.rowSpacing) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.06))
                    .frame(width: Metrics.posterWidth, height: Metrics.posterWidth * 1.5)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .accessibilityLabel("Loading \(source.title)")
    }
}

struct PosterTile: View {
    let meta: MetaPreview
    /// Nil fills the width offered, as in a grid, keeping the 2:3 shape.
    var width: CGFloat? = Metrics.posterWidth
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            // Shown underneath, so titles without artwork are still identifiable.
            Text(meta.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(8)
            Artwork(url: meta.poster)
        }
        .overlay(alignment: .bottom) {
            // Movies only: a series' progress belongs to its episodes.
            if let progress = library.progress[meta.id] {
                WatchProgressBar(progress: progress)
            }
        }
        .frame(width: width, height: width.map { $0 * 1.5 })
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement()
        .accessibilityLabel(meta.name)
    }
}
