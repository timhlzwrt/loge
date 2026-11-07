import CryptoKit
import Foundation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "catalogs")

/// Recent catalog pages, so Home paints from the last launch's results and screens that
/// show the same catalog (the featured carousel and its row, See All, the Mac sidebar)
/// share one request.
///
/// A page younger than `freshLifetime` is used as is. An older one, up to `staleLimit`,
/// is shown at once while a refresh runs in the background for the next time it's asked
/// for. Pages are kept as files in Caches: the system may purge them, which only costs a
/// network request.
actor CatalogCache {
    static let shared = CatalogCache(
        directory: URL.cachesDirectory.appending(path: "Catalogs", directoryHint: .isDirectory)
    )

    typealias Load = @Sendable () async throws -> Data
    typealias Decode = @Sendable (Data) throws -> [MetaPreview]

    private struct Entry {
        let task: Task<[MetaPreview], Error>
        let started: Date
    }
    private var entries: [URL: Entry] = [:]
    private var refreshing: Set<URL> = []

    private let directory: URL?
    private let freshLifetime: TimeInterval
    private let staleLimit: TimeInterval
    private let now: @Sendable () -> Date

    /// - Parameter directory: Where pages outlive the process; nil keeps them in memory only.
    init(
        directory: URL?,
        freshLifetime: TimeInterval = 15 * 60,
        staleLimit: TimeInterval = 7 * 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.directory = directory
        self.freshLifetime = freshLifetime
        self.staleLimit = staleLimit
        self.now = now
    }

    /// - Parameter persist: Whether the page is worth keeping across launches; searches aren't.
    func metas(for url: URL, persist: Bool, load: @escaping Load, decode: @escaping Decode) async throws -> [MetaPreview] {
        if let entry = entries[url], now().timeIntervalSince(entry.started) < freshLifetime {
            return try await result(of: entry, for: url)
        }
        if persist, let stored = read(url), case let age = now().timeIntervalSince(stored.saved),
           age < staleLimit, let metas = try? decode(stored.data) {
            remember(Task<[MetaPreview], any Error> { metas }, for: url, started: age < freshLifetime ? stored.saved : now())
            if age >= freshLifetime { refresh(url, load: load, decode: decode) }
            return metas
        }
        let entry = remember(Task {
            let data = try await load()
            let metas = try decode(data)
            if persist { write(data, for: url) }
            return metas
        }, for: url, started: now())
        return try await result(of: entry, for: url)
    }

    @discardableResult
    private func remember(_ task: Task<[MetaPreview], any Error>, for url: URL, started: Date) -> Entry {
        let entry = Entry(task: task, started: started)
        entries[url] = entry
        entries = entries.filter { now().timeIntervalSince($0.value.started) < freshLifetime }
        return entry
    }

    private func result(of entry: Entry, for url: URL) async throws -> [MetaPreview] {
        do {
            return try await entry.task.value
        } catch {
            // Failures aren't kept, so Retry asks the addon again.
            if entries[url]?.started == entry.started { entries[url] = nil }
            throw error
        }
    }

    /// Replaces a stale page once the addon answers; on failure the stale page stays.
    private func refresh(_ url: URL, load: @escaping Load, decode: @escaping Decode) {
        guard refreshing.insert(url).inserted else { return }
        Task {
            defer { refreshing.remove(url) }
            do {
                let data = try await load()
                let metas = try decode(data)
                write(data, for: url)
                remember(Task<[MetaPreview], any Error> { metas }, for: url, started: now())
            } catch {
                log.error("""
                Couldn't refresh a catalog from \(url.host() ?? "addon", privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
            }
        }
    }

    // MARK: Files

    /// Named by a hash, since a configured addon's URL can carry its keys.
    private func file(for url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory?.appending(path: name + ".json")
    }

    private func read(_ url: URL) -> (data: Data, saved: Date)? {
        guard let file = file(for: url),
              let data = try? Data(contentsOf: file),
              let saved = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return nil }
        return (data, saved)
    }

    private func write(_ data: Data, for url: URL) {
        guard let directory, let file = file(for: url) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            // Stamped with the cache's clock rather than the file system's, so age checks agree.
            try FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: file.path)
        } catch {
            log.error("Couldn't keep a catalog page: \(error.localizedDescription, privacy: .public)")
        }
        removeExpiredFiles(in: directory)
    }

    private func removeExpiredFiles(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            guard let saved = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now().timeIntervalSince(saved) >= staleLimit
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
