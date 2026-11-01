import MediaCore
import SwiftUI

struct HomeView: View {
    /// Replaced on pull-to-refresh, which rebuilds the rows so they load again.
    @State private var refreshID = UUID()

    var body: some View {
        let sources = DiscoveryCatalogs.home
        #if os(tvOS)
        TVHome(sources: sources)
        #else
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                FeaturedCarousel(movies: sources[0], series: sources[1])
                ContinueWatchingRow()
                MyListRow()
                // Genres follow the popular shelves, ahead of the narrower ones.
                ForEach(sources.prefix(3)) { CatalogRow(source: $0) }
                GenreRow()
                ForEach(sources.dropFirst(3)) { CatalogRow(source: $0) }
            }
            .padding(.bottom, 32)
            .id(refreshID)
        }
        .task(id: refreshID) {
            await prefetchArtwork(of: sources)
        }
        .refreshable {
            refreshID = UUID()
        }
        // The hero starts at the top edge of the screen, under the status bar or toolbar.
        .ignoresSafeArea(edges: .top)
        .background(Color.canvas)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #elseif os(macOS)
        // The hero names what's on screen; the window needs no title over it.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        #endif
    }
}

/// Downloads artwork into the shared URL cache that `Artwork` and `TitleLogo` load from,
/// so it's already there when a row scrolls in or the carousel pages.
private func prefetch(_ urls: [String?]) async {
    await withTaskGroup(of: Void.self) { group in
        for url in Set(urls.compactMap { $0 }).compactMap(URL.init(string:)) {
            group.addTask {
                // Only warms the cache: the view that shows the image handles a failure.
                _ = try? await URLSession.shared.data(from: url)
            }
        }
    }
}

/// The first posters of every Home row, one row at a time in screen order, so rows further
/// down have theirs before they scroll in. Their catalog responses are cached too, so the
/// rows don't download them again.
private func prefetchArtwork(of sources: [CatalogSource]) async {
    for source in sources {
        guard !Task.isCancelled else { return }
        // A row that fails shows its own error and retry.
        guard let metas = try? await source.items() else { continue }
        var urls = metas.prefix(12).map(\.poster)
        #if os(tvOS)
        // Focus usually enters a row at its start, which fills the screen with its backdrop.
        urls += metas.prefix(2).map(\.featuredBackground)
        #endif
        await prefetch(urls)
    }
}

#if os(tvOS)
/// Like the TV app: the focused poster's backdrop fills the screen and its
/// details sit above the rows, so browsing doesn't require opening anything.
private struct TVHome: View {
    let sources: [CatalogSource]
    @State private var focused: MetaPreview?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Artwork(url: focused?.featuredBackground)
                .ignoresSafeArea()
                .overlay {
                    // Darken the left and bottom, where the text and rows sit.
                    LinearGradient(colors: [.canvas.opacity(0.85), .canvas.opacity(0)], startPoint: .leading, endPoint: .center)
                        .ignoresSafeArea()
                    BackdropFade().ignoresSafeArea()
                }
                .animation(.easeInOut(duration: 0.4), value: focused?.id)

            // The header stays put while only the rows scroll beneath it, so the focused
            // title's details remain visible whichever row it's in.
            VStack(alignment: .leading, spacing: 0) {
                header
                    .frame(height: 400, alignment: .bottomLeading)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 40)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ContinueWatchingRow { focused = $0 }
                        MyListRow { focused = $0 }
                        ForEach(sources.prefix(3)) { source in
                            CatalogRow(source: source, isPrimary: source == sources.first) { focused = $0 }
                        }
                        GenreRow()
                        ForEach(sources.dropFirst(3)) { source in
                            CatalogRow(source: source) { focused = $0 }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 60)
                }
                // Moving focus down a row scrolls by whole rows, so the focused row keeps its title.
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .background(Color.canvas)
        .task {
            await prefetchArtwork(of: sources)
        }
    }

    private var header: some View {
        // The clear base keeps the header's height while nothing is focused yet.
        ZStack(alignment: .bottomLeading) {
            Color.clear
            if let focused {
                details(focused)
            }
        }
    }

    private func details(_ focused: MetaPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TitleLogo(logo: focused.logo, name: focused.name, maxHeight: 140)
                .frame(maxWidth: 600, alignment: .leading)
                .id(focused.id)
            focused.infoLine
            if let description = focused.description {
                Text(description)
                    .font(.synopsis)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .frame(maxWidth: 840, alignment: .leading)
            }
        }
    }
}
#else
/// Swipeable highlights from the popular movies and series, edge to edge, with page dots underneath.
private struct FeaturedCarousel: View {
    let movies: CatalogSource
    let series: CatalogSource
    @State private var items: [MetaPreview] = []
    @State private var currentID: MetaPreview.ID?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items) { meta in
                    FeaturedPage(meta: meta, isCentred: isCentred, bottomInset: items.count > 1 ? 38 : 18)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .frame(height: height)
        // Landscape safe areas must not expose the neighboring page's content.
        .clipped()
        .overlay(alignment: .bottom) {
            if items.count > 1 {
                pageDots.padding(.bottom, 16)
            }
        }
        .task {
            // The carousel is decoration on top of the rows below, which show
            // their own error, so a failure here just leaves it out.
            async let movieItems = try? movies.items()
            async let seriesItems = try? series.items()
            items = DiscoveryCatalogs.featured(movies: await movieItems ?? [], series: await seriesItems ?? [])
            await prefetchPages(after: nil)
        }
        .task(id: currentID) {
            await prefetchPages(after: currentID)
        }
    }

    /// The next two pages' artwork, so paging never shows an empty backdrop.
    private func prefetchPages(after id: MetaPreview.ID?) async {
        let index = items.firstIndex { $0.id == id } ?? 0
        let upcoming = items.dropFirst(index + 1).prefix(2)
        await prefetch(upcoming.flatMap { [$0.featuredBackground, $0.logo] })
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(items) { meta in
                Circle()
                    .fill(meta.id == (currentID ?? items.first?.id) ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    #if os(iOS)
    /// Centred on a portrait phone; left-aligned where there's width to spare.
    private var isCentred: Bool { horizontalSizeClass == .compact && verticalSizeClass != .compact }
    private var height: CGFloat {
        verticalSizeClass == .compact ? 340 : 560
    }
    #else
    private let isCentred = false
    private let height: CGFloat = 480
    #endif
}

/// One title in the carousel: its backdrop, logo, meta line and buttons.
private struct FeaturedPage: View {
    let meta: MetaPreview
    let isCentred: Bool
    /// Room for the page dots.
    let bottomInset: CGFloat

    @Environment(AddonStore.self) private var store
    @Environment(LibraryStore.self) private var library
    /// Set once a series' episodes are known, which opens its sources.
    @State private var playing: SourcesRoute?
    /// Set when a series' episodes couldn't be loaded; its details say why.
    @State private var opening: MetaPreview?

    var body: some View {
        ZStack(alignment: isCentred ? .bottom : .bottomLeading) {
            NavigationLink(value: meta) {
                Artwork(url: meta.featuredBackground)
                    .overlay { scrims }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(meta.name)
            #if os(macOS)
            // Lets the backdrop run on under the floating sidebar.
            .backgroundExtensionEffect()
            #endif

            VStack(alignment: isCentred ? .center : .leading, spacing: 12) {
                NavigationLink(value: meta) {
                    VStack(alignment: isCentred ? .center : .leading, spacing: 12) {
                        TitleLogo(logo: meta.logo, name: meta.name, maxHeight: isCentred ? 72 : 96)
                            .frame(maxWidth: isCentred ? 280 : 360, alignment: isCentred ? .center : .leading)
                        meta.infoLine
                            .multilineTextAlignment(isCentred ? .center : .leading)
                        if !isCentred, let description = meta.description {
                            Text(description)
                                .font(.synopsis)
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(2)
                                .frame(maxWidth: 520, alignment: .leading)
                        }
                    }
                }
                .buttonStyle(.plain)
                buttons
                    .padding(.top, 4)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, bottomInset + (isCentred ? 0 : 60))
        }
        .navigationDestination(item: $playing) { SourcesView(route: $0) }
        .navigationDestination(item: $opening) { MetaDetailView(preview: $0) }
    }

    private var scrims: some View {
        ZStack {
            BackdropFade()
            if !isCentred {
                LinearGradient(colors: [.canvas.opacity(0.8), .canvas.opacity(0)], startPoint: .leading, endPoint: .center)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await play() }
            } label: {
                Label(isStarted ? "Resume" : "Play", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            Button(library.isSaved(meta.id) ? "Remove from My List" : "Add to My List",
                   systemImage: library.isSaved(meta.id) ? "checkmark" : "plus") {
                library.toggleSaved(meta)
            }
            .buttonStyle(GlassIconButtonStyle())
            .contentTransition(.symbolEffect(.replace))
        }
    }

    private var isStarted: Bool {
        library.isInProgress(metaID: meta.id)
    }

    /// Movies go straight to their sources. A series needs its episodes first, to know which
    /// one is up next; without them it opens the details instead.
    private func play() async {
        if meta.type != "series" {
            playing = PlayAction(preview: meta, meta: nil, library: library)?.route
            return
        }
        let details = try? await store.addons.metaClient(type: meta.type, id: meta.id)?.meta(type: meta.type, id: meta.id)
        if let route = PlayAction(preview: meta, meta: details, library: library)?.route {
            playing = route
        } else {
            opening = meta
        }
    }
}
#endif
