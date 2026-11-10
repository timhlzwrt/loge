import LogeCore
import SwiftUI

extension Color {
    /// Charcoal rather than black, so dark posters and backdrop edges stay visible.
    static let canvas = Color(red: 0.08, green: 0.08, blue: 0.09)
}

@MainActor
enum Metrics {
    #if os(tvOS)
    static let isPhone = false
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
    static let isPhone = false
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
    /// The device rather than the size class: a narrow iPad window is compact too, and keeps its tabs.
    static let isPhone = UIDevice.current.userInterfaceIdiom == .phone
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

extension View {
    /// For a title's pages on iPhone: details, sources, and the people and reviews reached from
    /// them, so the bar doesn't come and go on the way through. It would cover their last actions.
    func hidingPhoneTabBar() -> some View {
        #if os(iOS)
        toolbar(Metrics.isPhone ? .hidden : .automatic, for: .tabBar)
        #else
        self
        #endif
    }

    /// The screen's name. tvOS pins a navigation title in place and draws whatever scrolls
    /// across it, so there the same title sits on a strip of canvas that the content passes under.
    func pageTitle(_ title: String) -> some View {
        #if os(tvOS)
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 76, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
                .padding(.bottom, 10)
                .background { Color.canvas.ignoresSafeArea(edges: [.top, .horizontal]) }
                .zIndex(1)
            self
        }
        #else
        navigationTitle(title)
        #endif
    }

    /// Keeps long text at a comfortable line length on iPad, where the page runs far wider.
    func readingWidth() -> some View {
        #if os(iOS)
        frame(maxWidth: 640, alignment: .leading)
            // Still takes the full width: a scroll view around it would otherwise shrink to fit.
            .frame(maxWidth: .infinity, alignment: .leading)
        #else
        self
        #endif
    }
}

extension Font {
    #if os(tvOS)
    static let sectionTitle = Font.system(size: 33, weight: .bold)
    static let metaLine = Font.system(size: 23, weight: .medium)
    static let synopsis = Font.system(size: 24)
    static let cardTitle = Font.system(size: 25, weight: .bold)
    static let episodeCaption = Font.system(size: 17, weight: .semibold)
    static let episodeTitle = Font.system(size: 21, weight: .semibold)
    #elseif os(macOS)
    static let sectionTitle = Font.system(size: 19, weight: .bold)
    static let metaLine = Font.system(size: 13, weight: .medium)
    static let synopsis = Font.system(size: 14)
    static let cardTitle = Font.system(size: 14, weight: .bold)
    static let episodeCaption = Font.caption.weight(.semibold)
    static let episodeTitle = Font.headline
    #else
    static let sectionTitle = Font.title2.bold()
    static let metaLine = Font.footnote.weight(.medium)
    /// Further from the screen than a phone, an iPad reads long text at the system's body size.
    @MainActor static let synopsis = Metrics.isPhone ? Font.subheadline : Font.body
    static let cardTitle = Font.subheadline.bold()
    /// Episode and History cards share these, so both read as one kind of card.
    static let episodeCaption = Font.caption.weight(.semibold)
    static let episodeTitle = Font.headline
    #endif
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
                Image(image, scale: 1, label: Text(name))
                    .renderingMode(LogoTone.isDark(image, url: logo) ? .template : .original)
                    .resizable().scaledToFit()
                    .foregroundStyle(.white)
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

/// Tells apart logos with dark lettering, made for light backgrounds, which vanish on the
/// dark canvas and are drawn in white instead. Opaque images have no shape to recolour.
@MainActor
private enum LogoTone {
    private static var results: [String: Bool] = [:]

    /// Measured once per logo, as a title's logo redraws with every focus move on tvOS.
    static func isDark(_ image: CGImage, url: String?) -> Bool {
        if let url, let known = results[url] { return known }
        let dark = measure(image)
        if let url { results[url] = dark }
        return dark
    }

    private static func measure(_ image: CGImage) -> Bool {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        var solid = 0
        var luminance = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] > 128 {
            let alpha = Double(pixels[offset + 3])
            solid += 1
            luminance += (0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                + 0.0722 * Double(pixels[offset + 2])) / alpha
        }
        guard solid > 0, solid < side * side * 85 / 100 else { return false }
        return luminance / Double(solid) < 0.25
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
