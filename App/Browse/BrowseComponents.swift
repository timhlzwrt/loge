import ImageIO
import MediaCore
import SwiftUI

extension Color {
    /// Charcoal rather than black, so dark posters and backdrop edges stay visible.
    static let canvas = Color(red: 0.08, green: 0.08, blue: 0.09)
}

@MainActor
enum Metrics {
    #if os(tvOS)
    static let posterWidth: CGFloat = 210
    /// Continue Watching stills.
    static let cardWidth: CGFloat = 354
    static let episodeWidth: CGFloat = 375
    /// History cards: their width in My Lists' row, the narrowest column of History's grid.
    static let historyCardWidth: CGFloat = 375
    // tvOS already insets content by its own safe area margins.
    static let gutter: CGFloat = 0
    static let rowSpacing: CGFloat = 40
    /// Between a row's title and its artwork, which the focus lift already pushes apart.
    static let headerSpacing: CGFloat = 16
    static let cardRadius: CGFloat = 24
    static let posterRadius: CGFloat = 21
    /// Cast & Crew circles.
    static let personSize: CGFloat = 150
    /// The narrowest column of the details' Information grid.
    static let infoColumnWidth: CGFloat = 300
    #elseif os(macOS)
    static let posterWidth: CGFloat = 132
    static let cardWidth: CGFloat = 232
    static let episodeWidth: CGFloat = 232
    static let historyCardWidth: CGFloat = 232
    static let gutter: CGFloat = 32
    static let rowSpacing: CGFloat = 16
    static let headerSpacing: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let posterRadius: CGFloat = 10
    static let personSize: CGFloat = 76
    static let infoColumnWidth: CGFloat = 180
    #else
    // The idiom never changes while running, so these can stay constants.
    private static let isPad = UIDevice.current.userInterfaceIdiom == .pad
    static let posterWidth: CGFloat = isPad ? 160 : 112
    static let cardWidth: CGFloat = isPad ? 320 : 270
    static let episodeWidth: CGFloat = isPad ? 320 : 240
    static let historyCardWidth: CGFloat = isPad ? 240 : 170
    static let gutter: CGFloat = isPad ? 32 : 20
    static let rowSpacing: CGFloat = 12
    static let headerSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 14
    static let posterRadius: CGFloat = 12
    static let personSize: CGFloat = isPad ? 96 : 76
    static let infoColumnWidth: CGFloat = isPad ? 200 : 150
    #endif
}

extension Font {
    #if os(tvOS)
    static let sectionTitle = Font.system(size: 33, weight: .bold)
    static let metaLine = Font.system(size: 23, weight: .medium)
    static let synopsis = Font.system(size: 24)
    static let cardTitle = Font.system(size: 25, weight: .bold)
    #elseif os(macOS)
    static let sectionTitle = Font.system(size: 19, weight: .bold)
    static let metaLine = Font.system(size: 13, weight: .medium)
    static let synopsis = Font.system(size: 14)
    static let cardTitle = Font.system(size: 14, weight: .bold)
    #else
    static let sectionTitle = Font.title2.bold()
    static let metaLine = Font.footnote.weight(.medium)
    static let synopsis = Font.subheadline
    static let cardTitle = Font.subheadline.bold()
    #endif
}

/// The one accent-coloured call to action on a screen: Play or Resume.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
        #endif

        var body: some View {
            configuration.label
                .font(font)
                .labelStyle(PlayLabelStyle())
                .foregroundStyle(.black)
                .padding(.leading, height * 0.44)
                .padding(.trailing, height * 0.56)
                .frame(minHeight: height)
                .background(.tint, in: .capsule)
                .opacity(configuration.isPressed ? 0.8 : 1)
                #if os(tvOS)
                .scaleEffect(isFocused ? 1.06 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 24, y: 14)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                #endif
        }

        #if os(tvOS)
        private let height: CGFloat = 78
        private let font = Font.system(size: 27, weight: .semibold)
        #elseif os(macOS)
        private let height: CGFloat = 36
        private let font = Font.system(size: 14, weight: .semibold)
        #else
        private let height: CGFloat = 50
        private let font = Font.headline
        #endif
    }

    /// A smaller glyph than the text, as in the TV app.
    private struct PlayLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 8) {
                configuration.icon.imageScale(.small)
                configuration.title
            }
        }
    }
}

/// Round, icon-only Liquid Glass buttons beside the primary one: Watch Later, Choose a Source.
/// Drawn rather than using the `.glass` button style, which pads the circle beyond the
/// primary button's height.
struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
        #endif

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(font)
                .frame(width: size, height: size)
                .contentShape(.circle)
                #if os(tvOS)
                // Focus fills the circle, as the system's glass buttons do, in the accent.
                .foregroundStyle(isFocused ? .black : .white)
                .background(.tint.opacity(isFocused ? 1 : 0), in: .circle)
                .glassEffect(.regular, in: .circle)
                .scaleEffect(isFocused ? 1.06 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 24, y: 14)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                #else
                .foregroundStyle(.white)
                .glassEffect(.regular.interactive(), in: .circle)
                #endif
        }

        #if os(tvOS)
        private let size: CGFloat = 78
        private let font = Font.system(size: 27, weight: .semibold)
        #elseif os(macOS)
        private let size: CGFloat = 36
        private let font = Font.system(size: 14, weight: .semibold)
        #else
        private let size: CGFloat = 50
        private let font = Font.title3.weight(.semibold)
        #endif
    }
}

/// Remote artwork that fills whatever frame it's given, cropping rather than
/// growing to the image's own size, with a quiet placeholder while loading or missing.
struct Artwork: View {
    let url: String?
    /// Tried in order when `url` is missing or fails to load.
    var fallbacks: [String] = []

    var body: some View {
        Color.white.opacity(0.06)
            .overlay {
                // RemoteImage reports a missing URL as a failure, so both move on to the next fallback.
                RemoteImage(url: url) { phase in
                    switch phase {
                    case .success(let image): Image(decorative: image, scale: 1).resizable().scaledToFill()
                    case .failure: next
                    case .loading: EmptyView()
                    }
                }
            }
            .clipped()
    }

    @ViewBuilder
    private var next: some View {
        let remaining = fallbacks.drop { $0 == url }
        if let first = remaining.first {
            Artwork(url: first, fallbacks: Array(remaining.dropFirst()))
        }
    }
}

/// Artwork decoded once and kept in memory, so posters that scroll back into view or
/// reappear on another screen draw at once instead of after a placeholder. Downloads go
/// through the shared session and its disk cache. Decoding happens off the main thread;
/// `AsyncImage` left it to the first draw.
@MainActor
enum ArtworkCache {
    private static let images: NSCache<NSURL, CGImage> = {
        let cache = NSCache<NSURL, CGImage>()
        // Decoded bytes: about 250 posters, or a dozen full-screen backdrops.
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()
    /// Lets a poster shown in two places at once download only once.
    private static var loads: [URL: Task<CGImage?, Never>] = [:]

    static func cached(_ url: URL) -> CGImage? {
        images.object(forKey: url as NSURL)
    }

    static func image(for url: URL) async -> CGImage? {
        if let image = cached(url) { return image }
        if let load = loads[url] { return await load.value }
        let load = Task.detached(priority: .userInitiated) { () -> CGImage? in
            // A missing image draws the placeholder, as `AsyncImage` did; there's nothing to retry.
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let source = CGImageSourceCreateWithData(data as CFData, nil)
            else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        loads[url] = load
        let image = await load.value
        loads[url] = nil
        if let image {
            images.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        }
        return image
    }
}

private enum ArtworkPhase {
    case loading
    case success(CGImage)
    case failure
}

/// Like `AsyncImage`, but drawn from `ArtworkCache` without a loading phase when it's there.
private struct RemoteImage<Content: View>: View {
    typealias Phase = ArtworkPhase

    let url: URL?
    @ViewBuilder let content: (Phase) -> Content
    @State private var loaded: (url: URL, image: CGImage?)?

    init(url: String?, @ViewBuilder content: @escaping (Phase) -> Content) {
        self.url = url.flatMap(URL.init(string:))
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url, ArtworkCache.cached(url) == nil else { return }
                let image = await ArtworkCache.image(for: url)
                loaded = (url, image)
            }
    }

    private var phase: Phase {
        guard let url else { return .failure }
        if let image = ArtworkCache.cached(url) { return .success(image) }
        guard let loaded, loaded.url == url else { return .loading }
        return loaded.image.map(Phase.success) ?? .failure
    }
}

/// An inset bar along the bottom of artwork showing how much has been watched,
/// or a checkmark in the corner once it's finished.
struct WatchProgressBar: View {
    let progress: WatchProgress

    var body: some View {
        if progress.isFinished {
            Image(systemName: "checkmark.circle.fill")
                .font(Self.checkmarkFont)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .tint)
                .padding(Self.inset * 0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .accessibilityLabel("Watched")
        } else {
            Capsule()
                .fill(.white.opacity(0.32))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(.tint).frame(width: proxy.size.width * progress.fraction)
                    }
                }
                .frame(height: Self.height)
                .padding(.horizontal, Self.inset)
                .padding(.bottom, Self.inset * 0.75)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .accessibilityLabel("\(Int(progress.fraction * 100)) percent watched")
        }
    }

    #if os(tvOS)
    static let height: CGFloat = 4
    static let inset: CGFloat = 21
    private static let checkmarkFont = Font.system(size: 30)
    #else
    static let height: CGFloat = 3
    static let inset: CGFloat = 12
    private static let checkmarkFont = Font.title3
    #endif
}

/// Fades a backdrop into the canvas so text placed over its lower part stays legible.
struct BackdropFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .canvas.opacity(0), location: 0.25),
                .init(color: .canvas.opacity(0.85), location: 0.6),
                .init(color: .canvas, location: 0.85),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// The addon's logo image for a title, falling back to the name as text.
struct TitleLogo: View {
    let logo: String?
    let name: String
    let maxHeight: CGFloat

    var body: some View {
        RemoteImage(url: logo) { phase in
            switch phase {
            case .success(let image):
                Image(image, scale: 1, label: Text(name)).resizable().scaledToFit()
                    .frame(maxHeight: maxHeight)
            case .failure:
                nameText
            default:
                // Reserve the space so the layout doesn't jump when the logo arrives.
                Color.clear.frame(height: maxHeight)
            }
        }
        .frame(maxHeight: maxHeight)
    }

    private var nameText: some View {
        Text(name)
            .font(.largeTitle.bold())
            .lineLimit(2)
            .minimumScaleFactor(0.6)
    }
}

/// "Crime · 2008–2013 · 49 min · IMDb 9.5/10"
struct InfoLine: View {
    let releaseInfo: String?
    let genres: [String]?
    let runtime: String?
    let rating: String?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        let parts = [genres?.prefix(genreCount).joined(separator: ", "), releaseInfo, runtime]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let details = parts.joined(separator: " · ")
        let line: Text
        if let rating, let score = Double(rating), score.isFinite, score > 0, score <= 10 {
            line = Text("\(details)\(parts.isEmpty ? "" : " · ")IMDb \(rating)/10")
        } else {
            line = Text(details)
        }
        // Wraps rather than truncates at large text sizes.
        return line
            .font(.metaLine)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    /// One genre on a phone, where the line has to fit under a centred title.
    private var genreCount: Int {
        #if os(iOS)
        horizontalSizeClass == .compact ? 1 : 2
        #else
        2
        #endif
    }
}

extension MetaPreview {
    var infoLine: InfoLine {
        InfoLine(releaseInfo: releaseInfo, genres: genres, runtime: runtime, rating: imdbRating)
    }
}

extension Meta {
    var infoLine: InfoLine {
        InfoLine(releaseInfo: releaseInfo, genres: genres, runtime: runtime, rating: imdbRating)
    }
}
