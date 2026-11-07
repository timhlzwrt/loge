import Foundation

public struct PlaybackSegment: Sendable, Equatable {
    public var kind: PlaybackChapter.SkipKind
    public var start: Double
    public var end: Double

    public init(kind: PlaybackChapter.SkipKind, start: Double, end: Double) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    public func skip(at position: Double, duration: Double?) -> PlaybackChapter.Skip? {
        guard position.isFinite, position >= start, position < end,
              let duration, duration.isFinite, end <= duration else { return nil }
        return PlaybackChapter.Skip(kind: kind, end: end)
    }
}

public enum SkipTimingError: Error, Equatable {
    case httpStatus(Int)
}

/// Anonymous reads from TheIntroDB v4. Only title identifiers and runtime leave the device.
public struct SkipTimingClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func segments(for item: WatchItem, duration: Double) async throws -> [PlaybackSegment] {
        guard let url = Self.requestURL(for: item, duration: duration) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 404 { return [] }
        guard (200..<300).contains(response.statusCode) else { throw SkipTimingError.httpStatus(response.statusCode) }
        return try Self.decode(data, duration: duration)
    }

    static func requestURL(for item: WatchItem, duration: Double) -> URL? {
        guard duration.isFinite, duration > 0, duration <= 86_400,
              item.metaID.range(of: #"^tt[0-9]{7,10}$"#, options: .regularExpression) != nil,
              item.type == MediaType.movie || item.type == MediaType.series else { return nil }
        var query = [URLQueryItem(name: "imdb_id", value: item.metaID)]
        if item.type == MediaType.series {
            guard let season = item.season, season >= 0,
                  let episode = item.episode, episode > 0 else { return nil }
            query += [URLQueryItem(name: "season", value: String(season)), URLQueryItem(name: "episode", value: String(episode))]
        }
        query += [URLQueryItem(name: "duration_ms", value: String(Int((duration * 1_000).rounded()))),
                  URLQueryItem(name: "details", value: "true"), URLQueryItem(name: "merge_unknown", value: "false")]
        var components = URLComponents(string: "https://api.theintrodb.org/v4/media")
        components?.queryItems = query
        return components?.url
    }

    private struct Response: Decodable {
        struct Segment: Decodable {
            var start_ms: Double?
            var end_ms: Double?
            var confidence: Double?
            var submission_count: Int?
        }
        var group_duration_ms: Double?
        var intro: [Segment]?
        var recap: [Segment]?
        var credits: [Segment]?
    }

    static func decode(_ data: Data, duration: Double) throws -> [PlaybackSegment] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        // The API chooses the closest release, which can still be a different cut.
        // Require a near-exact runtime and several agreeing submissions; manual skips
        // should not offer boundaries from sparse or mismatched community data.
        guard duration.isFinite, duration > 0, let groupDuration = response.group_duration_ms,
              groupDuration.isFinite, groupDuration > 0, abs(groupDuration / 1_000 - duration) <= 2 else { return [] }
        let groups: [(PlaybackChapter.SkipKind, [Response.Segment])] = [
            (.intro, response.intro ?? []), (.recap, response.recap ?? []), (.credits, response.credits ?? []),
        ]
        return groups.flatMap { kind, segments in
            segments.compactMap { segment -> PlaybackSegment? in
                guard let confidence = segment.confidence, confidence.isFinite, confidence >= 0.5, confidence <= 1,
                      let count = segment.submission_count, count >= 3 else { return nil }
                // Per API semantics, null starts mean 0; only credits can end at the file's end.
                let start = (segment.start_ms ?? 0) / 1_000
                let end = segment.end_ms.map { $0 / 1_000 } ?? (kind == .credits ? duration : .nan)
                guard start.isFinite, end.isFinite, start >= 0, start < end, end <= duration else { return nil }
                return PlaybackSegment(kind: kind, start: start, end: end)
            }
        }.sorted { $0.start < $1.start }
    }
}
