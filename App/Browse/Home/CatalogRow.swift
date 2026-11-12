import LogeCore
import SwiftUI

/// A titled, horizontally scrolling row of posters from one addon catalog.
/// Rows with no results hide themselves, so search shows only catalogs that matched.
struct CatalogRow: View {
    let source: CatalogSource
    var search: String?
    /// The page's rows, on Home, whose leads this row's should differ from.
    var page: [CatalogSource] = []
    /// Takes the page's default focus on tvOS.
    var isPrimary = false
    /// Moves focus to the first poster once loaded, on tvOS: Search's genre rows replace the
    /// tile that had focus, and the engine otherwise picked whatever was nearest.
    var takesFocusWhenLoaded = false
    /// Called with whichever poster has focus; drives the tvOS home header.
    var onFocus: (MetaPreview) -> Void = { _ in }
    /// Called with the first item once loaded, for the tvOS home header before anything has focus.
    var onFirstLoaded: (MetaPreview) -> Void = { _ in }
    /// Called with the number of results once loading finishes, or -1 on failure.
    var onLoaded: (Int) -> Void = { _ in }

    @State private var items: Result<[MetaPreview], Error>?
    /// Only the first poster is bound to focus state, for Home's default focus: binding every
    /// poster to one value made each focus move update the whole row.
    @FocusState private var isFirstFocused: Bool
    #if os(tvOS)
    /// Once per row, so coming back from a title doesn't move focus off the poster it was opened from.
    @State private var hasTakenFocus = false
    #endif

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
                let metas: [MetaPreview]
                if let search {
                    metas = try await source.items(search: search)
                } else {
                    metas = try await source.items(varyingFrom: page)
                }
                try Task.checkCancellation()
                items = .success(metas)
                onLoaded(metas.count)
                if let first = metas.first {
                    onFirstLoaded(first)
                }
            } catch is CancellationError {
                // Scrolled away or the query changed; the next task reloads.
            } catch {
                guard !Task.isCancelled else { return }
                items = .failure(error)
                onLoaded(-1)
            }
        }
        .onChange(of: search) { items = nil }
    }

    /// Restarts loading when the query changes or Retry clears the result.
    private struct TaskKey: Equatable {
        let search: String?
        let isLoading: Bool
    }

    private func row(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Group {
                #if os(tvOS)
                // On tvOS the row ends in a "See All" tile instead, which focus reaches naturally.
                Text(source.title)
                #else
                if search == nil {
                    NavigationLink(value: source) {
                        HStack(spacing: 4) {
                            Text(source.title)
                            Image(systemName: "chevron.right")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .titleTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the whole catalog")
                } else {
                    Text(source.title)
                }
                #endif
            }
            .font(.sectionTitle)
            .padding(.horizontal, Metrics.gutter)
            content()
        }
    }

    private func posters(_ metas: [MetaPreview]) -> some View {
        HorizontalShelf(source.title) {
            LazyHStack(spacing: Metrics.rowSpacing) {
                ForEach(metas) { meta in
                    if meta.id == metas.first?.id {
                        poster(meta).focused($isFirstFocused)
                            #if os(tvOS)
                            // After the poster is on screen; a request made as the row loads is dropped.
                            .task {
                                guard takesFocusWhenLoaded, !hasTakenFocus else { return }
                                hasTakenFocus = true
                                isFirstFocused = true
                            }
                            #endif
                    } else {
                        poster(meta)
                    }
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
        .scrollClipDisabled()
        #if os(tvOS)
        // Home opens on its first row rather than on the sidebar.
        .defaultFocus($isFirstFocused, isPrimary)
        #endif
    }

    private func poster(_ meta: MetaPreview) -> some View {
        NavigationLink(value: meta) {
            PosterTile(meta: meta)
                #if os(tvOS)
                .modifier(ReportsFocus { onFocus(meta) })
                #endif
        }
        .tileButtonStyle()
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
        .accessibilityLabel("Loading \(source.title)")
    }
}

/// Stands in for missing artwork: a title in the poster's place, rather than a
/// blank tile. Filenames, as debrid libraries list them, are tidied into words.
struct TitleCard: View {
    let name: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "film")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            let readable = Self.readable(name)
            Text(readable.title)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            if let year = readable.year {
                Text(year)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
    }

    /// "Obsession.2026.2160p.UHD.BluRay.Remux" → ("Obsession", "2026"). Release names put the
    /// title first and then the year or quality, so everything from there on is dropped.
    static func readable(_ name: String) -> (title: String, year: String?) {
        // Most catalog names have nothing to tidy, and the patterns below cost more than the
        // rest of a poster tile: a release name has a separator, a digit or a quality word.
        let lowered = name.lowercased()
        guard name.contains(where: { $0.isNumber || $0 == "." || $0 == "_" })
                || ["uhd", "bluray", "remux", "web"].contains(where: lowered.contains) else { return (name, nil) }
        var name = name
        if let dot = name.lastIndex(of: "."), name.distance(from: dot, to: name.endIndex) <= 5,
           name[name.index(after: dot)...].allSatisfy(\.isLetter) {
            name = String(name[..<dot])
        }
        // Separators between words; a dot followed by a space ("Mr. Robot") is punctuation.
        name = name.replacing(#/[._](?=\S)/#, with: " ")

        let quality = name.firstMatch(of: #/(?i)\b(2160p|1080p|720p|480p|4k|uhd|web[ -]?dl|bluray|remux)\b/#)
        // The release year is the last one before the quality, which skips years that are
        // part of the title ("Blade Runner 2049") or are the title ("1917").
        let year = name.matches(of: #/[(\[]?\b((?:19|20)\d{2})\b[)\]]?/#)
            .filter { $0.range.lowerBound > name.startIndex && $0.range.lowerBound < (quality?.range.lowerBound ?? name.endIndex) }
            .last
        guard let cut = year?.range.lowerBound ?? quality?.range.lowerBound, cut > name.startIndex else { return (name, nil) }
        let title = name[..<cut].trimmingCharacters(in: CharacterSet(charactersIn: " -(["))
        guard !title.isEmpty else { return (name, nil) }
        return (title, year.map { String($0.1) })
    }
}

#if os(tvOS)
/// Calls `action` when the button this sits in gains focus. Each poster watches only its own
/// focus, so a move updates the two posters involved rather than the whole row.
struct ReportsFocus: ViewModifier {
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.onChange(of: isFocused) { _, focused in
            if focused { action() }
        }
    }
}
#endif

struct PosterTile: View {
    let meta: MetaPreview
    /// Nil fills the width offered, as in a grid, keeping the 2:3 shape.
    var width: CGFloat? = Metrics.posterWidth
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let progress = library.progress[meta.id]
        ZStack {
            Color.white.opacity(0.06)
            // Shown underneath, so titles whose artwork is missing or fails still read.
            TitleCard(name: meta.name)
            if meta.poster != nil {
                Artwork(url: meta.poster)
            }
        }
        .overlay(alignment: .bottom) {
            // Movies only: a series' progress belongs to its episodes.
            if let progress {
                WatchProgressBar(progress: progress)
            }
        }
        .frame(width: width, height: width.map { $0 * 1.5 })
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Metrics.posterRadius))
        .accessibilityElement()
        .accessibilityLabel(meta.name)
        // The element replaces the progress bar's own label.
        .accessibilityValue(progress.map { $0.isFinished ? "Watched" : "\(Int($0.fraction * 100)) percent watched" } ?? "")
        .contextMenu { SaveToMenu(title: meta) }
    }
}
