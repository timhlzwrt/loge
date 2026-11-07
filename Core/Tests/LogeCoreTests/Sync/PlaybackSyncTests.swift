import Foundation
import Testing
@testable import LogeCore

@MainActor
struct PlaybackSyncTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "PlaybackSyncTests-\(UUID())")! }
    private func item(_ id: String = "movie", metaID: String? = nil) -> WatchItem {
        WatchItem(id: id, type: "movie", metaID: metaID ?? id, title: id)
    }
    private func entry(_ id: String = "movie", position: Double = 300, time: TimeInterval = 0) -> WatchProgress {
        WatchProgress(item: item(id), position: position, duration: 600, updatedAt: t0 + time)
    }

    @Test func independentItemsMergeAndIntentionalRewatchIsNotReplacedByFurthestPosition() {
        let completed = entry(position: 600)
        let base = PlaybackSyncSnapshot(entries: ["movie": completed])
        let local = PlaybackSyncSnapshot(entries: ["movie": entry(position: 35, time: -60)])
        let remote = PlaybackSyncSnapshot(entries: ["movie": completed, "other": entry("other")])
        let result = PlaybackSyncSnapshot.merged(base: base, local: local, remote: remote)
        #expect(result.conflictingIDs.isEmpty)
        #expect(result.snapshot.entries["movie"]?.position == 35)
        #expect(result.snapshot.entries["other"] != nil)
    }

    @Test func concurrentProgressNeedsChoiceAndResolvingKeepsUnrelatedItems() {
        let base = PlaybackSyncSnapshot(entries: ["movie": entry()])
        let local = PlaybackSyncSnapshot(entries: ["movie": entry(position: 50, time: 1), "local": entry("local")])
        let remote = PlaybackSyncSnapshot(entries: ["movie": entry(position: 500, time: 2), "remote": entry("remote")])
        let result = PlaybackSyncSnapshot.merged(base: base, local: local, remote: remote)
        #expect(result.conflictingIDs == ["movie"])
        let chosen = result.resolving(useLocal: false)
        #expect(chosen.entries["movie"]?.position == 500)
        #expect(chosen.entries["local"] != nil)
        #expect(chosen.entries["remote"] != nil)
    }

    @Test func explicitRemovalSurvivesRelaunchAndRemoteMergeButMissingEntriesAreNotDeletion() throws {
        let defaults = defaults()
        let store = LibraryStore(defaults: defaults)
        store.activateProfile(id: "account")
        store.record(item(), position: 300, duration: 600, at: t0)
        let base = store.playbackSyncSnapshot
        store.markUnwatched(["movie"], at: t0 + 1)
        let restored = LibraryStore(defaults: defaults)
        #expect(restored.playbackSyncSnapshot.removals["movie"] == t0 + 1)
        let merged = PlaybackSyncSnapshot.merged(base: base, local: restored.playbackSyncSnapshot, remote: base)
        #expect(merged.conflictingIDs.isEmpty)
        #expect(merged.snapshot.entries["movie"] == nil)
        #expect(merged.snapshot.removals["movie"] != nil)
        let retained = PlaybackSyncSnapshot.merged(base: base, local: .init(), remote: base)
        #expect(retained.snapshot.entries["movie"] != nil)
        try restored.applyPlaybackSyncSnapshot(merged.snapshot)
        #expect(restored.progress.isEmpty)
    }

    @Test func titleRemovalCoversUnseenRemoteEpisodesAndConcurrentPlaybackRequiresChoice() {
        let episode = WatchProgress(item: item("episode", metaID: "show"), position: 300, duration: 600, updatedAt: t0)
        let base = PlaybackSyncSnapshot(entries: ["episode": episode])
        let removed = PlaybackSyncSnapshot(titleRemovals: ["show": t0 + 1])
        let result = PlaybackSyncSnapshot.merged(base: base, local: removed, remote: base)
        #expect(result.snapshot.entries["episode"] == nil)
        #expect(result.conflictingIDs.isEmpty)
        var playing = base
        playing.entries["episode"]?.position = 450
        playing.entries["episode"]?.updatedAt = t0 + 2
        let conflict = PlaybackSyncSnapshot.merged(base: base, local: removed, remote: playing)
        #expect(conflict.conflictingIDs == ["episode"])
        #expect(conflict.resolving(useLocal: true).entries["episode"] == nil)
        #expect(conflict.resolving(useLocal: false).entries["episode"]?.position == 450)
    }

    @Test func rewatchAfterTitleRemovalSurvivesEvenWithAnEarlierClock() {
        let removed = PlaybackSyncSnapshot(removals: ["movie": t0 + 100], titleRemovals: ["movie": t0 + 100])
        let rewatch = PlaybackSyncSnapshot(entries: ["movie": entry(position: 40, time: -100)], titleRemovals: removed.titleRemovals)
        let result = PlaybackSyncSnapshot.merged(base: removed, local: rewatch, remote: removed)
        #expect(result.conflictingIDs.isEmpty)
        #expect(result.snapshot.entries["movie"]?.position == 40)
        #expect(result.snapshot.removals["movie"] == nil)
    }

    @Test func retentionArchivesSyncedEntriesWithoutCreatingRemovalIntent() {
        let defaults = defaults()
        let store = LibraryStore(defaults: defaults)
        store.activateProfile(id: "account")
        for index in 0...LibraryStore.maximumEntries {
            store.record(item("item-\(index)"), position: 300, duration: 600, at: t0 + Double(index))
        }
        #expect(store.progress.count == LibraryStore.maximumEntries)
        #expect(store.progress["item-0"] == nil)
        #expect(store.playbackSyncSnapshot.entries["item-0"] != nil)
        #expect(store.playbackSyncSnapshot.removals.isEmpty)
        #expect(store.resumePosition(for: "item-0") == 295)
        #expect(store.isInProgress(metaID: "item-0"))
        #expect(store.upNext(metaID: "item-0", videos: [Video(id: "item-0", season: 1, episode: 1)])?.resumeAt == 295)
        let restored = LibraryStore(defaults: defaults)
        #expect(restored.playbackSyncSnapshot.entries.count == LibraryStore.maximumEntries + 1)
        #expect(restored.resumePosition(for: "item-0") == 295)
        restored.markWatched([item("item-0")], at: t0)
        #expect(restored.progress["item-0"] == nil)
        #expect(restored.isWatched("item-0"))
    }

    @Test func profilesPreservePrivateLocalStateAndRestoreAcrossRelaunch() throws {
        let defaults = defaults()
        let store = LibraryStore(defaults: defaults)
        store.record(item("legacy"), position: 60, duration: 600, at: t0)
        let list = store.createList(named: "Local list")
        let source = RememberedSource(itemID: "legacy", providerURL: "https://addon.example/manifest.json",
                                      url: URL(string: "https://stream.example/private")!, headers: ["Authorization": "fixture"], bingeGroup: nil)
        store.rememberSource(source, metaID: "legacy")
        store.activateProfile(id: "account-a")
        #expect(store.progress.isEmpty && store.sources.isEmpty && store.lists.isEmpty)
        store.record(item("a"), position: 100, duration: 600, at: t0)
        _ = store.createList(named: "A list")
        store.activateProfile(id: "account-b")
        #expect(store.progress.isEmpty && store.lists.isEmpty)
        store.record(item("b"), position: 200, duration: 600, at: t0)
        let restored = LibraryStore(defaults: defaults)
        #expect(restored.activeProfileID == "account-b")
        #expect(restored.progress["b"] != nil)
        restored.activateProfile(id: "account-a")
        #expect(restored.progress["a"] != nil && restored.progress["b"] == nil)
        #expect(restored.lists.first?.name == "A list")
        restored.activateProfile(id: nil)
        #expect(restored.progress["legacy"] != nil && restored.progress["a"] == nil)
        #expect(restored.lists.first?.id == list)
        #expect(restored.sources["legacy"] == source)
        try restored.applyPlaybackSyncSnapshot(.init(entries: ["other": entry("other")]))
        #expect(restored.sources["legacy"] == source && restored.lists.first?.id == list)
    }

    @Test func importedExactProgressUsesLocalOnlyFractionUntilTheNewFileHasSeeked() throws {
        let defaults = defaults()
        let store = LibraryStore(defaults: defaults)
        store.activateProfile(id: "account")
        let snapshot = PlaybackSyncSnapshot(entries: ["movie": entry(position: 300)])
        try store.applyPlaybackSyncSnapshot(snapshot)
        #expect(store.estimatedFraction(for: "movie") == 0.5)
        #expect(store.playbackSyncSnapshot == snapshot)
        let restored = LibraryStore(defaults: defaults)
        #expect(restored.estimatedFraction(for: "movie") == 0.5)
        #expect(restored.playbackSyncSnapshot == snapshot)
        restored.record(item(), position: 450, duration: 900, at: t0 + 1)
        #expect(restored.estimatedFraction(for: "movie") == nil)
        #expect(restored.progress["movie"]?.duration == 900)
        restored.markUnwatched(["movie"])
        #expect(restored.estimatedFraction(for: "movie") == nil)
    }

    @Test func invalidIncomingSnapshotIsRejectedBeforeChangingLibrary() {
        let store = LibraryStore(defaults: defaults())
        store.record(item(), position: 300, duration: 600, at: t0)
        var invalid = entry()
        invalid.position = .infinity
        #expect(throws: SyncError.self) {
            try store.applyPlaybackSyncSnapshot(.init(entries: ["movie": invalid]))
        }
        #expect(store.progress["movie"]?.position == 300)
        #expect(throws: SyncError.self) {
            try store.applyPlaybackSyncSnapshot(.init(entries: ["wrong-id": entry()]))
        }
    }
}
