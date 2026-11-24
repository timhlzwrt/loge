import SwiftUI

/// The canvas with light falling into one corner: amber on pages without artwork, the
/// artwork's own colour on pages that lead with it.
struct PageGlow: View {
    var color: Color = PageGlow.amber
    var center = UnitPoint(x: 0.85, y: 0.06)
    var strength = 0.32

    /// The amber of the retired accent colours.
    static let amber = Color(red: 0.96, green: 0.72, blue: 0.25)

    var body: some View {
        RadialGradient(colors: [color.opacity(strength), .clear], center: center,
                       startRadius: 0, endRadius: Self.radius)
            .background(Color.canvas)
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.6), value: color)
    }

    #if os(tvOS)
    static let radius: CGFloat = 900
    #elseif os(macOS)
    static let radius: CGFloat = 420
    #else
    static let radius: CGFloat = 460
    #endif
}

/// A glow in the colour of a title's artwork, laid over the page once the artwork is loaded.
struct ArtworkGlow: View {
    let url: String?
    var center = UnitPoint(x: 0.2, y: 0.6)
    @State private var tint: Color?

    var body: some View {
        RadialGradient(colors: [(tint ?? .clear).opacity(0.3), .clear], center: center,
                       startRadius: 0, endRadius: PageGlow.radius * 1.2)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.6), value: tint)
            .task(id: url) {
                guard let url = url.flatMap(URL.init(string:)),
                      let image = await ArtworkCache.image(for: url) else { return }
                tint = Self.tint(of: image)
            }
    }

    /// The most colourful of an 8×8 thumbnail's pixels, at full brightness: an average of a
    /// whole backdrop is nearly always brown or grey.
    static func tint(of image: CGImage) -> Color? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var best: (score: Double, hue: Double, saturation: Double) = (0, 0, 0)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let (r, g, b) = (Double(pixels[index]) / 255, Double(pixels[index + 1]) / 255, Double(pixels[index + 2]) / 255)
            let high = max(r, g, b), low = min(r, g, b)
            guard high > 0.15 else { continue }
            let saturation = (high - low) / high
            let score = saturation * high
            guard score > best.score else { continue }
            let delta = high - low
            var hue = 0.0
            if delta > 0 {
                if high == r { hue = (g - b) / delta } else if high == g { hue = 2 + (b - r) / delta } else { hue = 4 + (r - g) / delta }
                hue = (hue / 6).truncatingRemainder(dividingBy: 1)
                if hue < 0 { hue += 1 }
            }
            best = (score, hue, saturation)
        }
        // A black-and-white image glows neutral rather than in a hue it doesn't have.
        guard best.score > 0.08 else { return Color.white.opacity(0.5) }
        return Color(hue: best.hue, saturation: min(max(best.saturation, 0.45), 0.8), brightness: 0.95)
    }
}
