import Foundation

/// Watch Later as it syncs: each title with when it was added, and when titles were taken off.
/// Per title the later of the two wins, so devices converge without asking.
public struct WatchLaterSyncSnapshot: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var title: MetaPreview
        public var addedAt: Date
    }

    /// Newest added first.
    public private(set) var entries: [Entry]
    public private(set) var removals: [String: Date]

    /// Long enough for a device left offline to come back without restoring what was removed,
    /// short enough that the document doesn't grow with every title ever taken off.
    static let removalLifetime: TimeInterval = 90 * 24 * 60 * 60

    public init(entries: [Entry] = [], removals: [String: Date] = [:]) {
        // Only what My Lists draws travels; the rest of a catalog's preview stays on the device.
        self.entries = entries
            .map { Entry(title: MetaPreview(id: $0.title.id, type: $0.title.type, name: $0.title.name,
                                            poster: $0.title.poster, posterShape: $0.title.posterShape),
                         addedAt: $0.addedAt) }
            .sorted { ($0.addedAt, $0.title.id) > ($1.addedAt, $1.title.id) }
        self.removals = removals
    }

    private enum CodingKeys: String, CodingKey { case entries, removals }

    /// Through `init`, so a document from another device reads in the same order and form.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(entries: try container.decode([Entry].self, forKey: .entries),
                  removals: try container.decode([String: Date].self, forKey: .removals))
    }

    public func validated() throws -> Self {
        func valid(_ value: String?, maximum: Int = 4096) -> Bool {
            value.map { !$0.isEmpty && $0.utf8.count <= maximum } ?? true
        }
        let ids = entries.map(\.title.id)
        guard Set(ids).count == ids.count, Set(ids).isDisjoint(with: removals.keys),
              entries.allSatisfy({ entry in
                  valid(entry.title.id) && valid(entry.title.type, maximum: 128)
                      && entry.title.name.utf8.count <= 32_768
                      && valid(entry.title.poster, maximum: 32_768) && valid(entry.title.posterShape, maximum: 128)
                      && entry.addedAt.timeIntervalSince1970.isFinite
              }),
              removals.allSatisfy({ valid($0.key) && $0.value.timeIntervalSince1970.isFinite })
        else { throw SyncError.invalidData }
        guard try JSONEncoder().encode(self).count <= AccountSyncClient.maximumBytes else {
            throw SyncError.tooLarge
        }
        return self
    }

    /// The later action wins per title; a tie keeps the removal. Removals older than
    /// `removalLifetime` are dropped. Local titles keep their own preview, gaining a poster
    /// only where they had none.
    public static func merged(local: Self, remote: Self, now: Date = .now) -> Self {
        var added: [String: Entry] = [:]
        for entry in remote.entries + local.entries {
            guard let existing = added[entry.title.id] else { added[entry.title.id] = entry; continue }
            var title = entry.title
            if title.poster == nil { title.poster = existing.title.poster; title.posterShape = existing.title.posterShape }
            added[entry.title.id] = Entry(title: title, addedAt: max(entry.addedAt, existing.addedAt))
        }
        let removed = local.removals.merging(remote.removals, uniquingKeysWith: max)
        let entries = added.values.filter { entry in removed[entry.title.id].map { entry.addedAt > $0 } ?? true }
        let kept = Set(entries.map(\.title.id))
        let cutoff = now.addingTimeInterval(-removalLifetime)
        return Self(entries: Array(entries),
                    removals: removed.filter { !kept.contains($0.key) && $0.value >= cutoff })
    }
}
