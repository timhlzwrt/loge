import LogeCore
import SwiftUI

#if os(tvOS)
/// What has focus on Home. It lives outside `TVHome`'s own state so a focus move redraws
/// only the backdrop and header that read it, not every row beneath them.
@MainActor @Observable
final class HomeFocus {
    var title: MetaPreview?
    var genre: DiscoveryCatalogs.Genre?

    func show(_ title: MetaPreview) {
        self.title = title
        genre = nil
    }

    /// Genres name themselves over their still, rather than leave the last title on screen.
    func show(_ genre: DiscoveryCatalogs.Genre) {
        self.genre = genre
    }
}

/// Like the TV app: the focused poster's backdrop fills the screen and its
/// details sit above the rows, so browsing doesn't require opening anything.
struct TVHome: View {
    let rows: [HomeLayout.Row]
    @State private var focus = HomeFocus()
    /// Returning to Home runs `.task` again; its artwork is already cached by then.
    @State private var prefetched = false

    var body: some View {
        let sources = rows.catalogs
        ZStack(alignment: .topLeading) {
            TVHomeBackdrop(focus: focus)

            // The header stays put while only the rows scroll beneath it, so the focused
            // title's details remain visible whichever row it's in.
            VStack(alignment: .leading, spacing: 0) {
                TVHomeHeader(focus: focus)
                    .frame(height: 400, alignment: .bottomLeading)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 40)
                ScrollView {
                    // Lazy: building every row at once made each focus move dirty all of them.
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(rows) { row in
                            switch row {
                            case .catalog(let source):
                                CatalogRow(source: source, page: sources, isPrimary: source == sources.first,
                                           onFocus: focus.show)
                            case .genres: GenreRow(onFocus: focus.show)
                            case .continueWatching: ContinueWatchingRow(onFocus: focus.show)
                            case .watchLater: MyListRow(onFocus: focus.show)
                            case .recommended: RecommendedRow(onFocus: focus.show)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 60)
                }
                // Moving focus down a row scrolls by whole rows, so the focused row keeps its title.
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .task {
            // Fills the header before anything has focus. Not from the row: the lazy stack may
            // not build it until focus moves down. Catalog requests are shared, so this loads once.
            // A failed catalog shows its error in its own row.
            if focus.title == nil, let first = try? await sources.first?.items(varyingFrom: sources).first,
               focus.title == nil { // Focus may have reached Continue Watching meanwhile.
                focus.show(first)
            }
            guard !prefetched else { return }
            prefetched = true
            await prefetchArtwork(of: sources)
        }
    }
}

/// The focused title's or genre's room: its backdrop in the upper right, fading left and
/// down into its tone, which fills the rest of the screen.
struct TVHomeBackdrop: View {
    let focus: HomeFocus
    /// The backdrop on screen, which changes only once the next one has been decoded, so
    /// the crossfade goes from image to image rather than through the empty placeholder.
    @State private var shown: String?
    @State private var tone = Color.canvas

    var body: some View {
        let url = focus.genre?.still ?? focus.title?.featuredBackground
        ZStack(alignment: .topTrailing) {
            Room(tone: tone)
            ZStack {
                // Each backdrop is its own view, so the crossfade blends two layers on the GPU.
                // Animating one image view's content instead redrew both images on the CPU every frame.
                Artwork(url: shown)
                    .id(shown)
                    .transition(.opacity)
            }
            .overlay { BackdropFade(tone: tone) }
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.35)],
                               startPoint: .leading, endPoint: .trailing)
            }
            .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                length * (axis == .horizontal ? 0.78 : 0.68)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: shown)
        .task(id: url) {
            // A failed image still replaces the old one, as the placeholder, in the plain canvas.
            let found = await RoomTone.tone(for: url)
            guard !Task.isCancelled else { return }
            tone = found ?? .canvas
            shown = url
        }
    }
}

/// The focused title's logo, info line and synopsis, or the focused genre.
struct TVHomeHeader: View {
    let focus: HomeFocus
    @Environment(TMDBAccount.self) private var tmdb
    @Environment(AddonStore.self) private var store
    /// Library entries keep little beyond artwork; the rest is looked up when they get focus.
    @State private var filled: [MetaPreview.ID: MetaPreview] = [:]

    var body: some View {
        // The clear base keeps the header's height while nothing is focused yet.
        ZStack(alignment: .bottomLeading) {
            Color.clear
            if let genre = focus.genre {
                VStack(alignment: .leading, spacing: 14) {
                    Text(genre.name).font(.system(size: 64, weight: .bold))
                    Text("Popular now and the best of all time").font(.metaLine).foregroundStyle(.secondary)
                }
            } else if let title = focus.title {
                details(filled[title.id] ?? title)
            }
        }
        .task(id: focus.title?.id) { await fillFocusedTitle() }
        .task(id: "\(tmdb.revision):\(focus.title?.id ?? "")") {
            guard tmdb.isConfigured, let title = focus.title else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            // Opening the focused title reuses this response; its page owns retry/error UI.
            _ = try? await tmdb.details(imdbID: title.id, type: title.type)
        }
    }

    private func fillFocusedTitle() async {
        guard let title = focus.title, filled[title.id] == nil,
              title.logo == nil || title.description == nil || title.background == nil,
              let client = store.addons.metaClient(type: title.type, id: title.id) else { return }
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        // The header is a preview: without the details it shows what the entry has, and its page reports errors.
        guard let meta = try? await client.meta(type: title.type, id: title.id), !Task.isCancelled else { return }
        let complete = title.fillingDetails(from: meta)
        filled[title.id] = complete
        // The backdrop reads the focus, and Watch Later entries are saved without one.
        if focus.title?.id == title.id { focus.title = complete }
    }

    private func details(_ focused: MetaPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TitleLogo(logo: focused.logo, name: focused.name, maxHeight: 140, isWhite: true)
                .frame(maxWidth: 600, alignment: .leading)
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
#endif
