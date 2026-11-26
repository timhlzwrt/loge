import SwiftUI

/// A title's room: a deep tone taken from its artwork, which its backdrop fades into and
/// which fades to the canvas further down. Pages without a title stay on the canvas.
struct Room: View {
    let tone: Color

    var body: some View {
        LinearGradient(stops: [.init(color: tone, location: 0), .init(color: tone, location: 0.55),
                               .init(color: .canvas, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.6), value: tone)
    }
}

/// The tones of artwork already shown, by URL, so a page opens in its room straight away
/// the second time.
@MainActor
enum RoomTone {
    private static var tones: [URL: Color] = [:]

    static func cached(_ url: String?) -> Color? {
        url.flatMap(URL.init(string:)).flatMap { tones[$0] }
    }

    /// Nil until the image has loaded, or when it can't be.
    static func tone(for url: String?) async -> Color? {
        guard let url = url.flatMap(URL.init(string:)) else { return nil }
        if let known = tones[url] { return known }
        guard let image = await ArtworkCache.image(for: url),
              // Off the main thread: on Apple TV each focus move can bring a new backdrop.
              let tone = await Task.detached(priority: .userInitiated, operation: { tone(of: image) }).value
        else { return nil }
        tones[url] = tone
        return tone
    }

    /// The average of the image's lower half, which is the part that fades into the room,
    /// kept to its hue and some of its colour and darkened far enough that white text
    /// always reads on it.
    nonisolated static func tone(of image: CGImage) -> Color? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        // Core Graphics' rows run bottom up, so the first half of the buffer is the image's top.
        let lower = pixels[(pixels.count / 2)...]
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        for index in stride(from: lower.startIndex, to: lower.endIndex, by: 4) {
            sum.r += Double(lower[index]); sum.g += Double(lower[index + 1]); sum.b += Double(lower[index + 2])
        }
        let count = Double(lower.count / 4) * 255
        let (r, g, b) = (sum.r / count, sum.g / count, sum.b / count)
        let high = max(r, g, b), low = min(r, g, b)
        guard high > 0 else { return .canvas }
        var hue = 0.0
        if high > low {
            let delta = high - low
            hue = high == r ? (g - b) / delta : high == g ? 2 + (b - r) / delta : 4 + (r - g) / delta
            hue = (hue / 6).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
        }
        let saturation = (high - low) / high
        return Color(hue: hue, saturation: min(saturation, 0.6), brightness: 0.16)
    }
}

extension View {
    /// Fills `tone` with the room tone of `artwork` once it's known, gently.
    func roomTone(of artwork: String?, into tone: Binding<Color>) -> some View {
        task(id: artwork) {
            if let known = RoomTone.cached(artwork) {
                tone.wrappedValue = known
                return
            }
            guard let found = await RoomTone.tone(for: artwork), !Task.isCancelled else { return }
            tone.wrappedValue = found
        }
    }
}
