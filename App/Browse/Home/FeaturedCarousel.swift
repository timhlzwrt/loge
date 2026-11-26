import LogeCore
import SwiftUI

#if !os(tvOS)
/// Swipeable highlights from Home's first movie and series shelves, edge to edge, with page dots underneath.
struct FeaturedCarousel: View {
    @Environment(TMDBAccount.self) private var tmdb
    let movies: CatalogSource?
    let series: CatalogSource?
    @Binding var playing: SourcesRoute?
    @Binding var opening: MetaPreview?
    /// The room tone of the page showing, for Home's background.
    @Binding var tone: Color
    @State private var items: [MetaPreview] = []
    @State private var currentID: MetaPreview.ID?
    #if os(macOS)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items) { meta in
                    FeaturedPage(meta: meta, isNarrow: isNarrow, bottomInset: items.count > 1 ? 38 : 18, tone: tone,
                                 playing: $playing, opening: $opening)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        #if os(macOS)
        .scrollIndicators(.never)
        #else
        .scrollIndicators(.hidden)
        #endif
        .frame(height: height)
        // Landscape safe areas must not expose the neighboring page's content.
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if items.count > 1 {
                pageDots
                    .padding(.leading, Metrics.gutter - dotInset)
                    .padding(.bottom, 16 - dotInset)
            }
        }
        .roomTone(of: (items.first { $0.id == currentID } ?? items.first)?.featuredBackground, into: $tone)
        .task {
            // Returning to Home runs this again; the pages and the one showing stay.
            guard items.isEmpty else { return }
            // The carousel is decoration on top of the rows below, which show
            // their own error, so a failure here just leaves it out.
            async let movieItems = try? movies?.items()
            async let seriesItems = try? series?.items()
            // Each awaited on its own line, as Release builds have mishandled child task
            // results awaited inside a larger expression.
            let loadedMovies = await movieItems
            let loadedSeries = await seriesItems
            items = DiscoveryCatalogs.featured(movies: loadedMovies ?? [], series: loadedSeries ?? [])
            prefetchPages(after: nil)
        }
        .onChange(of: currentID) { _, id in
            prefetchPages(after: id)
        }
        .task(id: "\(tmdb.revision):\(currentID ?? items.first?.id ?? "")") {
            guard tmdb.isConfigured else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            let index = items.firstIndex { $0.id == currentID } ?? 0
            for title in items.dropFirst(index).prefix(2) {
                guard !Task.isCancelled else { return }
                // Keep speculative work small; opening the page retries failed requests.
                _ = try? await tmdb.details(imdbID: title.id, type: title.type)
            }
        }
    }

    /// The next two pages' artwork, so paging never shows an empty backdrop.
    private func prefetchPages(after id: MetaPreview.ID?) {
        let index = items.firstIndex { $0.id == id } ?? 0
        let upcoming = items.dropFirst(index + 1).prefix(2)
        prefetch(upcoming.flatMap { [$0.featuredBackground, $0.logo] })
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(items) { meta in
                #if os(macOS)
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        currentID = meta.id
                    }
                } label: {
                    Circle()
                        .fill(meta.id == (currentID ?? items.first?.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.35)))
                        .frame(width: 7, height: 7)
                        .padding(6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(meta.name)")
                .help(meta.name)
                #else
                Circle()
                    .fill(meta.id == (currentID ?? items.first?.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.35)))
                    .frame(width: 7, height: 7)
                #endif
            }
        }
        #if !os(macOS)
        .accessibilityHidden(true)
        #endif
    }

    /// The Mac's dots are buttons with room around them; the dot itself lines up with the text.
    #if os(macOS)
    private let dotInset: CGFloat = 6
    #else
    private let dotInset: CGFloat = 0
    #endif

    #if os(iOS)
    /// A phone's column, without the description; the full layout where there's width to spare.
    private var isNarrow: Bool { horizontalSizeClass == .compact }
    private var height: CGFloat { isNarrow ? 500 : 560 }
    #else
    private let isNarrow = false
    private let height: CGFloat = 480
    #endif
}

/// One title in the carousel: its backdrop, logo, meta line and buttons.
struct FeaturedPage: View {
    let meta: MetaPreview
    let isNarrow: Bool
    /// Room for the page dots.
    let bottomInset: CGFloat
    /// What the backdrop fades into.
    let tone: Color
    /// Set once a series' episodes are known, which opens its sources.
    @Binding var playing: SourcesRoute?
    /// Set when a series' episodes couldn't be loaded; its details say why.
    @Binding var opening: MetaPreview?

    @Environment(AddonStore.self) private var store
    @Environment(LibraryStore.self) private var library
    /// A series' full details, which say which episode Play starts.
    @State private var details: Meta?
    /// Play on a series waits for its episodes.
    @State private var isPreparingPlay = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NavigationLink(value: meta) {
                artwork
                    .overlay { scrims }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The title link below opens the same page; one stop per page is enough.
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: meta) {
                    VStack(alignment: .leading, spacing: 12) {
                        TitleLogo(logo: meta.logo, name: meta.name, maxHeight: isNarrow ? 90 : 96, isWhite: isNarrow)
                            .frame(maxWidth: isNarrow ? 260 : 360, alignment: .leading)
                        meta.infoLine
                        if !isNarrow, let description = meta.description {
                            Text(description)
                                .font(.synopsis)
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(2)
                                .frame(maxWidth: 520, alignment: .leading)
                        }
                    }
                }
                .buttonStyle(.plain)
                // Without an addon to play from, the card under the hero says how to get one.
                if store.addons.hasStreamAddon || !isNarrow {
                    buttons
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, bottomInset)
        }
        // Only for a series being watched, so Play can say which episode it resumes.
        .task(id: meta.id) {
            guard meta.type == MediaType.series, isStarted, details == nil else { return }
            details = await loadDetails()
        }
        .task(id: isPreparingPlay) {
            guard isPreparingPlay else { return }
            await play()
            isPreparingPlay = false
        }
        // Leaving the page cancels Play, so Sources can't open later over something else.
        .onDisappear { isPreparingPlay = false }
    }

    /// Cropped from the sides on a phone and from the top and bottom on wide windows, where
    /// faces sit in the upper part.
    private var artwork: some View {
        Artwork(url: meta.featuredBackground, alignment: .top)
    }

    private var scrims: some View {
        ZStack {
            BackdropFade(tone: tone)
            if !isNarrow {
                LinearGradient(colors: [tone.opacity(0.8), tone.opacity(0)], startPoint: .leading, endPoint: .center)
                    .animation(.easeOut(duration: 0.6), value: tone)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if isNarrow {
            // Play and the title's page, side by side across the width.
            HStack(spacing: 10) {
                playButton
                NavigationLink(value: meta) { Text("Details").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle(isTranslucent: true))
            }
        } else {
            HStack(spacing: 12) {
                playButton
                Button(library.isSaved(meta.id) ? "Remove from Watch Later" : "Add to Watch Later",
                       systemImage: library.isSaved(meta.id) ? "checkmark" : "plus") {
                    library.toggleSaved(meta)
                }
                .buttonStyle(GlassIconButtonStyle())
                .contentTransition(.symbolEffect(.replace))
            }
        }
    }

    private var playButton: some View {
        Button {
            isPreparingPlay = true
        } label: {
            Label {
                Text(playLabel)
            } icon: {
                if isPreparingPlay {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.black)
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .frame(maxWidth: isNarrow ? .infinity : nil)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isPreparingPlay)
    }

    private var isStarted: Bool {
        library.isInProgress(metaID: meta.id)
    }

    /// "Resume S2 E3" once a series' episodes are known, as on its details page.
    private var playLabel: String {
        if let details, let action = PlayAction(preview: meta, meta: details, library: library) {
            return action.label
        }
        return isStarted ? "Resume" : "Play"
    }

    /// The details are a preview here: Play falls back to the details page, which reports errors.
    private func loadDetails() async -> Meta? {
        try? await store.addons.metaClient(type: meta.type, id: meta.id)?.meta(type: meta.type, id: meta.id)
    }

    /// Movies go straight to their sources. A series needs its episodes first, to know which
    /// one is up next; without them it opens the details instead.
    private func play() async {
        if meta.type != MediaType.series {
            playing = PlayAction(preview: meta, meta: nil, library: library)?.route
            return
        }
        if details == nil { details = await loadDetails() }
        guard !Task.isCancelled else { return }
        if let route = PlayAction(preview: meta, meta: details, library: library)?.route {
            playing = route
        } else {
            opening = meta
        }
    }
}
#endif
