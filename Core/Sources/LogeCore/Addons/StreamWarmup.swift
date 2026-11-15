import Foundation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "addons")

/// Asks for the link Play is about to open before Play is pressed. Debrid addons such as
/// Comet resolve their playback link on its first request, which takes most of the time to
/// the first frame, then keep the resolved link for an hour and answer with a redirect.
/// Only the request is made early: the player still opens the addon's own URL, never a
/// resolved one, since debrid links expire.
public actor StreamWarmup {
    public static let shared = StreamWarmup()

    private var asked: [URL: Date] = [:]
    /// Well inside the addon's hour, so focus and navigation churn ask once.
    private let interval: TimeInterval

    init(interval: TimeInterval = 30 * 60) {
        self.interval = interval
    }

    /// Never for a source the addon marks as not cached: asking for that link starts a real
    /// download on the debrid account.
    public nonisolated func warm(_ stream: StreamSource) {
        Task { await self.run(stream) }
    }

    /// The URL to ask, recorded as asked, or nil when `stream` isn't to be warmed now.
    func claim(_ stream: StreamSource, now: Date = .now) -> URL? {
        guard let url = stream.playbackURL, StreamDetails(stream).isCached != false else { return nil }
        if let last = asked[url], now.timeIntervalSince(last) < interval { return nil }
        asked = asked.filter { now.timeIntervalSince($0.value) < interval }
        asked[url] = now
        return url
    }

    private func run(_ stream: StreamSource) async {
        guard let url = claim(stream) else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        // The same request the player makes, so the addon resolves the same link.
        for (name, value) in stream.requestHeaders { request.setValue(value, forHTTPHeaderField: name) }
        do {
            // Returns once the headers arrive. The redirect itself is the answer: following it
            // would start downloading the video.
            let (bytes, response) = try await URLSession.shared.bytes(for: request, delegate: RedirectRefusal())
            bytes.task.cancel()
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            log.debug("Warmed a stream link on \(url.host() ?? "?", privacy: .public): \(status)")
        } catch {
            log.debug("Warming a stream link on \(url.host() ?? "?", privacy: .public) failed")
        }
    }
}

private final class RedirectRefusal: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
