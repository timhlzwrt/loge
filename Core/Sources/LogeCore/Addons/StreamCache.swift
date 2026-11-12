import Foundation

/// Recent stream lists by addon and item. Aggregating addons such as AIOStreams take
/// seconds to answer, so the details screen asks ahead and the sources screen joins
/// that request, finished or not, instead of starting another.
actor StreamCache {
    static let shared = StreamCache()

    private struct Key: Hashable {
        let manifestURL: String
        let type: String
        let id: String
    }
    private struct Entry {
        let task: Task<[StreamSource], Error>
        let started: Date
    }
    private var entries: [Key: Entry] = [:]
    /// Debrid links stay valid much longer, but a list this old may miss newly cached releases.
    private let lifetime: TimeInterval

    init(lifetime: TimeInterval = 10 * 60) {
        self.lifetime = lifetime
    }

    func streams(
        manifestURL: String, type: String, id: String,
        fetch: @escaping @Sendable () async throws -> [StreamSource]
    ) async throws -> [StreamSource] {
        let key = Key(manifestURL: manifestURL, type: type, id: id)
        if let entry = entries[key], Date.now.timeIntervalSince(entry.started) < lifetime {
            return try await result(of: entry, for: key)
        }
        let entry = Entry(task: Task(operation: fetch), started: .now)
        entries[key] = entry
        entries = entries.filter { Date.now.timeIntervalSince($0.value.started) < lifetime }
        return try await result(of: entry, for: key)
    }

    private func result(of entry: Entry, for key: Key) async throws -> [StreamSource] {
        let streams: [StreamSource]
        do {
            streams = try await entry.task.value
        } catch {
            // Failures aren't kept, so Retry asks the addon again.
            forget(entry, for: key)
            throw error
        }
        // Nor are empty lists: aggregators answer with none when their upstream times out.
        if streams.isEmpty { forget(entry, for: key) }
        return streams
    }

    private func forget(_ entry: Entry, for key: Key) {
        if entries[key]?.started == entry.started { entries[key] = nil }
    }
}
