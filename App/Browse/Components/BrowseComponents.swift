import LogeCore
import SwiftUI

extension Color {
    /// Charcoal rather than black, so dark posters and backdrop edges stay visible.
    static let canvas = Color(red: 0.08, green: 0.08, blue: 0.09)
}

@MainActor
enum Metrics {
    #if os(tvOS)
    static let isTV = true
    static let isPhone = false
    static let posterWidth: CGFloat = 210
    /// Continue Watching stills.
    static let cardWidth: CGFloat = 354
    static let episodeWidth: CGFloat = 390
    // tvOS already insets content by its own safe area margins.
    static let gutter: CGFloat = 0
    static let rowSpacing: CGFloat = 40
    /// Between a row's title and its artwork, which the focus lift already pushes apart.
    static let headerSpacing: CGFloat = 16
    static let cardRadius: CGFloat = 24
    static let posterRadius: CGFloat = 21
    /// Cast & Crew circles.
    static let personSize: CGFloat = 150
    static let personTileWidth: CGFloat = 195
    /// The narrowest column of the details' Information grid.
    static let infoColumnWidth: CGFloat = 300
    /// Under portrait artwork that lifts on focus: at 8 the lifted image covered the name's first line.
    static let liftedCaptionSpacing: CGFloat = 16
    #elseif os(macOS)
    static let isTV = false
    static let isPhone = false
    static let posterWidth: CGFloat = 132
    static let cardWidth: CGFloat = 232
    static let episodeWidth: CGFloat = 232
    static let gutter: CGFloat = 32
    static let rowSpacing: CGFloat = 16
    static let headerSpacing: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let posterRadius: CGFloat = 10
    static let personSize: CGFloat = 76
    static let personTileWidth: CGFloat = 99
    static let infoColumnWidth: CGFloat = 180
    static let liftedCaptionSpacing: CGFloat = 8
    #else
    // The idiom never changes while running, so these can stay constants.
    private static let isPad = UIDevice.current.userInterfaceIdiom == .pad
    static let isTV = false
    /// The device rather than the size class: a narrow iPad window is compact too, and keeps its tabs.
    static let isPhone = UIDevice.current.userInterfaceIdiom == .phone
    static let posterWidth: CGFloat = isPad ? 160 : 112
    static let cardWidth: CGFloat = isPad ? 320 : 270
    static let episodeWidth: CGFloat = isPad ? 320 : 240
    static let gutter: CGFloat = isPad ? 40 : 20
    static let rowSpacing: CGFloat = 12
    static let headerSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 14
    static let posterRadius: CGFloat = 12
    static let personSize: CGFloat = isPad ? 96 : 92
    /// A phone shows three portraits and the edge of a fourth, which says the row scrolls.
    static let personTileWidth: CGFloat = isPad ? 125 : 106
    static let infoColumnWidth: CGFloat = isPad ? 200 : 150
    static let liftedCaptionSpacing: CGFloat = 8
    #endif

    /// See All, My Lists, search results and filmographies. Three posters across any phone:
    /// columns of at least `posterWidth` fit only two on a 393 pt one; seven across a
    /// landscape iPad; as many as fit a Mac window.
    static var posterGridColumns: [GridItem] {
        #if os(iOS)
        isPhone
            ? Array(repeating: GridItem(.flexible(), spacing: rowSpacing, alignment: .top), count: 3)
            : [GridItem(.adaptive(minimum: 132), spacing: 18, alignment: .top)]
        #else
        [GridItem(.adaptive(minimum: posterWidth), spacing: rowSpacing, alignment: .top)]
        #endif
    }
}

extension View {
    /// For a title's pages on iPhone: details, sources, and the people reached from them,
    /// so the bar doesn't come and go on the way through. It would cover their last actions.
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
    static let sectionTitle = Font.system(size: 31, weight: .semibold)
    static let metaLine = Font.system(size: 23, weight: .medium)
    static let synopsis = Font.system(size: 24)
    static let cardTitle = Font.system(size: 25, weight: .bold)
    static let episodeCaption = Font.system(size: 17, weight: .semibold)
    static let episodeTitle = Font.system(size: 21, weight: .semibold)
    #elseif os(macOS)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    static let metaLine = Font.system(size: 13, weight: .medium)
    static let synopsis = Font.system(size: 14)
    static let cardTitle = Font.system(size: 14, weight: .bold)
    static let episodeCaption = Font.caption.weight(.semibold)
    static let episodeTitle = Font.headline
    #else
    static let sectionTitle = Font.title3.weight(.semibold)
    static let metaLine = Font.footnote.weight(.medium)
    /// Further from the screen than a phone, an iPad reads long text at the system's body size.
    @MainActor static let synopsis = Metrics.isPhone ? Font.subheadline : Font.body
    static let cardTitle = Font.subheadline.bold()
    /// Episode and Continue Watching cards share these, so both read as one kind of card.
    static let episodeCaption = Font.caption.weight(.semibold)
    static let episodeTitle = Font.headline
    #endif
}

/// An inset bar along the bottom of artwork showing how much has been watched,
/// or a checkmark in the corner once it's finished.
struct WatchProgressBar: View {
    let progress: WatchProgress
    /// From the artwork's sides; smaller artwork sets it in less.
    var inset = WatchProgressBar.inset

    var body: some View {
        if progress.isFinished {
            Image(systemName: "checkmark.circle.fill")
                .font(Self.checkmarkFont)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .tint)
                .padding(inset * 0.8)
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
                .padding(.horizontal, inset)
                .padding(.bottom, inset * 0.75)
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

/// Fades a backdrop into the canvas, or a title's room tone, so text placed over its lower
/// part stays legible.
struct BackdropFade: View {
    var tone = Color.canvas

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: tone.opacity(0), location: 0.25),
                .init(color: tone.opacity(0.85), location: 0.6),
                .init(color: tone, location: 0.85),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .animation(.easeOut(duration: 0.6), value: tone)
    }
}

/// The addon's logo image for a title, falling back to the name as text.
struct TitleLogo: View {
    let logo: String?
    let name: String
    let maxHeight: CGFloat
    /// Lets sparkle or glow under the lettering hang into the space below, so what follows
    /// keeps its distance from the letters rather than from the faintest pixel.
    var restsOnLettering = false
    /// Drawn in white and greys whatever its own colours, as the redesigned heroes show every
    /// title. Not flattened to one white: logos with solid panels or brush strokes lose their
    /// lettering that way.
    var isWhite = false
    @State private var height: CGFloat = 0
    @State private var prepared: (url: String, trimmed: LogoTrim.Trimmed)?

    var body: some View {
        RemoteImage(url: logo) { phase in
            switch phase {
            case .success(let image):
                if let logo, let trimmed = prepared?.url == logo ? prepared?.trimmed : LogoTrim.cached(logo) {
                    let drawn = Image(trimmed.image, scale: 1, label: Text(name))
                        .renderingMode(trimmed.isDark ? .template : .original)
                        .resizable().scaledToFit()
                        .foregroundStyle(.white)
                        .saturation(isWhite ? 0 : 1)
                        // A soft shade around the letters, so white reads on bright artwork too.
                        .shadow(color: .black.opacity(isWhite ? 0.6 : 0), radius: 18)
                        .shadow(color: .black.opacity(isWhite ? 0.45 : 0), radius: 4)
                        // No wider than the height allows: a tall logo given more width
                        // would sit centred in it, away from the text it leads.
                        .frame(maxWidth: maxHeight * CGFloat(trimmed.image.width) / CGFloat(max(trimmed.image.height, 1)),
                               maxHeight: maxHeight)
                    if restsOnLettering {
                        drawn
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                            .padding(.bottom, -trimmed.faintBottom * height)
                    } else {
                        drawn
                    }
                } else {
                    // Measured off the main thread: on tvOS each focus move can bring a new logo.
                    placeholder.task(id: logo) {
                        guard let logo else { return }
                        prepared = (logo, await LogoTrim.prepare(image, url: logo))
                    }
                }
            case .failure:
                nameText
            default:
                placeholder
            }
        }
        .frame(maxHeight: maxHeight)
    }

    /// Reserves the space so the layout doesn't jump when the logo arrives.
    private var placeholder: some View {
        Color.clear.frame(height: maxHeight)
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
private enum LogoTone {
    static func isDark(_ image: CGImage) -> Bool {
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

/// Logos often come with transparent margins, which set the wordmark in from the text
/// under it; drawn without them, the logo lines up with the info line.
@MainActor
private enum LogoTrim {
    /// A logo without its transparent margins, how much of its height at the bottom is
    /// only faint decoration under the lettering, and whether it's drawn in white.
    final class Trimmed: Sendable {
        let image: CGImage
        let faintBottom: CGFloat
        let isDark: Bool

        init(image: CGImage, faintBottom: CGFloat, isDark: Bool) {
            self.image = image
            self.faintBottom = faintBottom
            self.isDark = isDark
        }
    }

    /// A crop keeps the whole original alive, so these are let go like the artwork they came from.
    private static let results: NSCache<NSString, Trimmed> = {
        let cache = NSCache<NSString, Trimmed>()
        cache.countLimit = 100
        return cache
    }()

    static func cached(_ url: String) -> Trimmed? {
        results.object(forKey: url as NSString)
    }

    /// Measured once per logo, as a title's logo redraws with every focus move on tvOS.
    static func prepare(_ image: CGImage, url: String) async -> Trimmed {
        if let known = cached(url) { return known }
        let trimmed = await Task.detached(priority: .userInitiated) {
            let isDark = LogoTone.isDark(image)
            return crop(image, isDark: isDark) ?? Trimmed(image: image, faintBottom: 0, isDark: isDark)
        }.value
        results.setObject(trimmed, forKey: url as NSString)
        return trimmed
    }

    /// Finds the visible part on a small copy, then crops the full image to it, a little wider
    /// so antialiased edges aren't cut.
    nonisolated private static func crop(_ image: CGImage, isDark: Bool) -> Trimmed? {
        let width = 96
        let height = Int((Double(image.height) / Double(image.width) * Double(width)).rounded())
        guard image.width > 0, (1...1_000).contains(height) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, maxX = -1, minY = height, maxY = -1
        // Rows with something solid in them: lettering, as opposed to sparkle and glow, which
        // this small copy averages down to faint pixels.
        var solidRows = IndexSet()
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[(y * width + x) * 4 + 3]
                if alpha > 8 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
                if alpha > 128 { solidRows.insert(y) }
            }
        }
        guard maxX >= 0 else { return nil }
        let faintBottom = faintBottom(solidRows: solidRows, visibleRows: minY...maxY)
        // Already tight: nothing to crop.
        guard minX > 1 || maxX < width - 2 || minY > 1 || maxY < height - 2 else {
            return faintBottom > 0 ? Trimmed(image: image, faintBottom: faintBottom, isDark: isDark) : nil
        }
        let scale = Double(image.width) / Double(width)
        let rect = CGRect(
            x: Double(minX - 1) * scale, y: Double(minY - 1) * scale,
            width: Double(maxX - minX + 3) * scale, height: Double(maxY - minY + 3) * scale
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return image.cropping(to: rect).map { Trimmed(image: $0, faintBottom: faintBottom, isDark: isDark) }
    }

    /// The share of the visible height below the last solid row. Nothing for a logo that is
    /// faint throughout, such as hairline lettering, which has no solid part to rest on; and
    /// never more than a third, so a wrong reading can't push a logo far into what follows.
    nonisolated private static func faintBottom(solidRows: IndexSet, visibleRows: ClosedRange<Int>) -> CGFloat {
        guard let first = solidRows.first, let last = solidRows.last else { return 0 }
        let visible = CGFloat(visibleRows.count)
        guard CGFloat(last - first + 1) >= visible * 0.3 else { return 0 }
        return min(CGFloat(visibleRows.upperBound - last) / visible, 1 / 3)
    }
}

/// "Crime · 2008–2013 · 49 min · IMDb 9.5/10"
struct InfoLine: View {
    let releaseInfo: String?
    let genres: [String]?
    let runtime: String?
    let rating: String?
    /// Under a description rather than over artwork: secondary, and without the rating.
    var isQuiet = false
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
        // Always over artwork: brighter than secondary text, with a soft shadow, so it reads
        // over busy backdrops too.
        return line
            .font(.metaLine)
            .foregroundStyle(.white.opacity(isQuiet ? 0.6 : 0.78))
            .shadow(color: .black.opacity(0.5), radius: 6)
            .lineLimit(2)
    }

    /// The same facts with the rating left to a `ScoresLine` beside them.
    var quiet: InfoLine {
        InfoLine(releaseInfo: releaseInfo, genres: genres, runtime: runtime, rating: nil, isQuiet: true)
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
