import ImageIO
import LogeCore
import SwiftUI

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

enum ArtworkPhase {
    case loading
    case success(CGImage)
    case failure
}

/// Like `AsyncImage`, but drawn from `ArtworkCache` without a loading phase when it's there.
struct RemoteImage<Content: View>: View {
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
