import LogeCore
import SwiftUI

#if os(tvOS)
/// What has focus on Home. It lives outside `TVHome`'s own state so a focus move redraws
/// only the backdrop and header that read it, not every row beneath them.
@MainActor @Observable
final class HomeFocus {
    var title: MetaPreview?
    var collection: FilmCollection?
    var director: TMDBPopularDirector?

    func show(_ title: MetaPreview) {
        self.title = title
        collection = nil
        director = nil
    }
}

/// Like the TV app: the focused poster's backdrop fills the screen and its
/// details sit above the rows, so browsing doesn't require opening anything.
struct TVHome: View {
    let sources: [CatalogSource]
    @State private var focus = HomeFocus()

    var body: some View {
        ZStack(alignment: .topLeading) {
            TVHomeBackdrop(focus: focus)

            // The header stays put while only the rows scroll beneath it, so the focused
            // title's details remain visible whichever row it's in.
            VStack(alignment: .leading, spacing: 0) {
                TVHomeHeader(focus: focus)
                    .frame(height: 400, alignment: .bottomLeading)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 40)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ContinueWatchingRow(onFocus: focus.show)
                            MyListRow(onFocus: focus.show)
                            ForEach(sources.prefix(3)) { source in
                                CatalogRow(source: source, isPrimary: source == sources.first, onFocus: focus.show)
                            }
                            GenreRow()
                            ForEach(sources.dropFirst(3)) { source in
                                CatalogRow(source: source, onFocus: focus.show)
                            }
                            DiscoveryCollectionRow(title: "Film Festivals", collections: FilmCollection.festivals) {
                                focus.director = nil
                                focus.collection = $0
                                proxy.scrollTo("festival-row", anchor: .top)
                            }
                            .id("festival-row")
                            PopularDirectorsRow(onFocus: { director in
                                focus.collection = nil
                                focus.director = director
                                proxy.scrollTo("director-row", anchor: .top)
                            }, onFallbackFocus: { collection in
                                focus.director = nil
                                focus.collection = collection
                                proxy.scrollTo("director-row", anchor: .top)
                            })
                            .id("director-row")
                        }
                        .scrollTargetLayout()
                        .padding(.bottom, 60)
                    }
                    // Moving focus down a row scrolls by whole rows, so the focused row keeps its title.
                    .scrollTargetBehavior(.viewAligned)
                }
            }
        }
        .background(Color.canvas)
        .task {
            await prefetchArtwork(of: sources)
        }
    }
}

/// The focused title's backdrop, hidden while a festival or director has focus.
struct TVHomeBackdrop: View {
    let focus: HomeFocus

    var body: some View {
        let url = focus.collection == nil && focus.director == nil ? focus.title?.featuredBackground : nil
        ZStack {
            // Each backdrop is its own view, so the crossfade blends two layers on the GPU.
            // Animating one image view's content instead redrew both images on the CPU every frame.
            Artwork(url: url)
                .id(url)
                .transition(.opacity)
        }
        .opacity(focus.collection == nil && focus.director == nil ? 1 : 0)
        .ignoresSafeArea()
        .overlay {
            // Darken the left and bottom, where the text and rows sit.
            LinearGradient(colors: [.canvas.opacity(0.85), .canvas.opacity(0)], startPoint: .leading, endPoint: .center)
                .ignoresSafeArea()
            BackdropFade().ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.4), value: url)
    }
}

/// The focused title's logo, info line and synopsis, or the focused festival or director.
struct TVHomeHeader: View {
    let focus: HomeFocus
    @Environment(TMDBAccount.self) private var tmdb

    var body: some View {
        // The clear base keeps the header's height while nothing is focused yet.
        ZStack(alignment: .bottomLeading) {
            Color.clear
            if let director = focus.director {
                HStack(spacing: 32) {
                    Artwork(url: director.portraitURL)
                        .frame(width: Metrics.personSize, height: Metrics.personSize * 1.25)
                        .clipShape(.rect(cornerRadius: Metrics.posterRadius))
                    VStack(alignment: .leading, spacing: 14) {
                        Text(director.name).font(.system(size: 64, weight: .bold))
                        Text("Director").font(.metaLine).foregroundStyle(.secondary)
                    }
                }
            } else if let collection = focus.collection {
                HStack(spacing: 32) {
                    CollectionArtwork(collection: collection)
                        .frame(width: collection.isFestival ? Metrics.posterWidth * 1.4 : Metrics.personSize,
                               height: Metrics.personSize * 1.25)
                        .clipShape(.rect(cornerRadius: Metrics.posterRadius))
                    VStack(alignment: .leading, spacing: 14) {
                        Text(collection.name).font(.system(size: 64, weight: .bold))
                        Text(collection.isFestival ? "\(collection.subtitle) winners" : "Directed films")
                            .font(.metaLine)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let title = focus.title {
                details(title)
            }
        }
        .task(id: "\(tmdb.revision):\(focus.title?.id ?? "")") {
            guard tmdb.isConfigured, let title = focus.title else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            // Opening the focused title reuses this response; its page owns retry/error UI.
            _ = try? await tmdb.details(imdbID: title.id, type: title.type)
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
#endif
