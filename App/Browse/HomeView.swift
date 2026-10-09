import MediaCore
import SwiftUI

struct HomeView: View {
    @Environment(AddonStore.self) private var store

    var body: some View {
        let sources = store.addons.homeCatalogs
        if sources.isEmpty {
            ContentUnavailableView(
                "No catalogs yet",
                systemImage: "square.stack",
                description: Text("Install an addon with catalogs, such as Cinemeta, in Addons.")
            )
        } else {
            #if os(tvOS)
            TVHome(sources: sources)
            #else
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    FeaturedCarousel(source: sources[0])
                    ForEach(sources) { CatalogRow(source: $0) }
                }
                .padding(.bottom, 32)
            }
            .background(Color.canvas)
            #endif
        }
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
            Artwork(url: focused?.background)
                .ignoresSafeArea()
                .overlay {
                    // Darken the left and bottom, where the text and rows sit.
                    LinearGradient(colors: [.canvas, .canvas.opacity(0)], startPoint: .leading, endPoint: .center)
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
                    .padding(.bottom, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(sources) { source in
                            CatalogRow(source: source, isPrimary: source == sources.first) { focused = $0 }
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .background(Color.canvas)
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
        VStack(alignment: .leading, spacing: 16) {
            TitleLogo(logo: focused.logo, name: focused.name, maxHeight: 140)
                .frame(maxWidth: 600, alignment: .leading)
                .id(focused.id)
            focused.infoLine
            if let description = focused.description {
                Text(description)
                    .font(.callout)
                    .lineLimit(3)
                    .frame(maxWidth: 1000, alignment: .leading)
            }
        }
    }
}
#else
/// Swipeable highlights from the first catalog, with page dots underneath.
private struct FeaturedCarousel: View {
    let source: CatalogSource
    @State private var items: [MetaPreview] = []
    @State private var currentID: MetaPreview.ID?

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { meta in
                        NavigationLink(value: meta) {
                            FeaturedCard(meta: meta)
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.hidden)

            if items.count > 1 {
                pageDots
            }
        }
        .task {
            // The carousel is decoration on top of the rows below, which show
            // their own error, so a failure here just leaves it out.
            let metas = (try? await source.items()) ?? []
            items = Array(metas.filter { $0.background != nil }.prefix(10))
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(items) { meta in
                Circle()
                    .fill(meta.id == (currentID ?? items.first?.id) ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FeaturedCard: View {
    let meta: MetaPreview

    var body: some View {
        Artwork(url: meta.background)
            .overlay { BackdropFade() }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    TitleLogo(logo: meta.logo, name: meta.name, maxHeight: 72)
                        .frame(maxWidth: 280, alignment: .leading)
                    meta.infoLine
                    if let description = meta.description {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(Metrics.gutter)
            }
            #if os(macOS)
            .aspectRatio(2.4, contentMode: .fit)
            #else
            .aspectRatio(0.8, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 16))
            .padding(.horizontal, Metrics.gutter)
            #endif
            .clipped()
            .contentShape(.rect)
    }
}
#endif
