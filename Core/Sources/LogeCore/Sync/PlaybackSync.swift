import Foundation

/// Only playback state travels here. Remembered source URLs and account credentials stay local.
public struct PlaybackSyncSnapshot: Codable, Equatable, Sendable {
    public var entries: [String: WatchProgress]
    public var removals: [String: Date]
    public var titleRemovals: [String: Date]

    public init(entries: [String: WatchProgress] = [:], removals: [String: Date] = [:], titleRemovals: [String: Date] = [:]) {
        self.entries = entries
        self.removals = removals
        self.titleRemovals = titleRemovals
    }

    public func validated() throws -> Self {
        func validID(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 4096 }
        guard entries.allSatisfy({ id, entry in
            validID(id) && id == entry.item.id && validID(entry.item.metaID)
                && !entry.item.type.isEmpty && entry.item.type.utf8.count <= 128
                && entry.item.title.utf8.count <= 32_768
                && entry.position.isFinite && entry.position >= 0
                && entry.duration.isFinite && entry.duration > 0
                && entry.updatedAt.timeIntervalSince1970.isFinite
                && (entry.item.season.map { $0 >= 0 } ?? true)
                && (entry.item.episode.map { $0 >= 0 } ?? true)
        }), removals.allSatisfy({ validID($0.key) && $0.value.timeIntervalSince1970.isFinite }),
        titleRemovals.allSatisfy({ validID($0.key) && $0.value.timeIntervalSince1970.isFinite }),
        Set(entries.keys).isDisjoint(with: removals.keys)
        else { throw SyncError.invalidData }
        guard try JSONEncoder().encode(self).count <= AccountSyncClient.maximumBytes else {
            throw SyncError.tooLarge
        }
        return self
    }

    /// Absence is not deletion: local history retention must never erase another device's history.
    public static func merged(base: Self, local: Self, remote: Self) -> PlaybackSyncMerge {
        var merged = Self()
        for id in Set(base.titleRemovals.keys).union(local.titleRemovals.keys).union(remote.titleRemovals.keys) {
            let original = base.titleRemovals[id]
            let lhs = local.titleRemovals[id] ?? original
            let rhs = remote.titleRemovals[id] ?? original
            if lhs == original { merged.titleRemovals[id] = rhs }
            else if rhs == original { merged.titleRemovals[id] = lhs }
            else { merged.titleRemovals[id] = [lhs, rhs].compactMap { $0 }.max() }
        }
        let ids = Set(base.entries.keys).union(local.entries.keys).union(remote.entries.keys)
            .union(base.removals.keys).union(local.removals.keys).union(remote.removals.keys)
        var conflicts = Set<String>()
        var localChoices: [String: PlaybackSyncState] = [:]
        var remoteChoices: [String: PlaybackSyncState] = [:]
        for id in ids {
            let metaID = local.entries[id]?.item.metaID ?? remote.entries[id]?.item.metaID ?? base.entries[id]?.item.metaID
            let original = base.state(for: id, metaID: metaID)
            let lhs = local.state(for: id, metaID: metaID, baseline: base) ?? original
            let rhs = remote.state(for: id, metaID: metaID, baseline: base) ?? original
            let selected: PlaybackSyncState?
            if case .progress(let left) = lhs, case .progress(var right) = rhs, PlaybackSyncState.equivalent(lhs, rhs) {
                // Artwork looked up on one device stays, rather than the next sync dropping it.
                right.item = right.item.fillingArtwork(from: left.item)
                selected = .progress(right)
            } else if PlaybackSyncState.equivalent(lhs, original) {
                selected = rhs
            } else if PlaybackSyncState.equivalent(rhs, original) || PlaybackSyncState.equivalent(lhs, rhs) {
                selected = lhs
            } else if case .removed(let leftDate) = lhs, case .removed(let rightDate) = rhs {
                selected = .removed(max(leftDate, rightDate))
            } else {
                conflicts.insert(id)
                localChoices[id] = lhs
                remoteChoices[id] = rhs
                selected = lhs
            }
            merged.set(selected, for: id)
        }
        return PlaybackSyncMerge(snapshot: merged, conflictingIDs: conflicts,
                                 localChoices: localChoices, remoteChoices: remoteChoices)
    }

    fileprivate func state(for id: String, metaID: String?, baseline: Self? = nil) -> PlaybackSyncState? {
        if let entry = entries[id] { return .progress(entry) }
        if let metaID, let removal = titleRemovals[metaID], baseline == nil || baseline?.titleRemovals[metaID] != removal {
            return .removed(removal)
        }
        return removals[id].map(PlaybackSyncState.removed)
    }

    fileprivate mutating func set(_ state: PlaybackSyncState?, for id: String) {
        entries[id] = nil
        removals[id] = nil
        switch state {
        case .progress(let entry): entries[id] = entry
        case .removed(let date): removals[id] = date
        case nil: break
        }
    }
}

public struct PlaybackSyncMerge: Sendable {
    public let snapshot: PlaybackSyncSnapshot
    public let conflictingIDs: Set<String>
    fileprivate let localChoices: [String: PlaybackSyncState]
    fileprivate let remoteChoices: [String: PlaybackSyncState]

    /// Resolving one playback conflict never discards updates to unrelated titles.
    public func resolving(useLocal: Bool) -> PlaybackSyncSnapshot {
        var result = snapshot
        let choices = useLocal ? localChoices : remoteChoices
        for id in conflictingIDs { result.set(choices[id], for: id) }
        return result
    }
}

private enum PlaybackSyncState: Sendable {
    case progress(WatchProgress)
    case removed(Date)

    static func equivalent(_ lhs: Self?, _ rhs: Self?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.removed(let lhs), .removed(let rhs)): lhs == rhs
        case (.progress(let lhs), .progress(let rhs)):
            // Artwork can be filled independently without changing the viewer's playback intent.
            lhs.item.id == rhs.item.id && lhs.item.type == rhs.item.type && lhs.item.metaID == rhs.item.metaID
                && lhs.position == rhs.position && lhs.duration == rhs.duration
                && lhs.updatedAt == rhs.updatedAt && lhs.isEstimated == rhs.isEstimated
        default: false
        }
    }
}
