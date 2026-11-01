import Foundation
import Observation
import os

private let log = Logger(subsystem: "li.tjh.MediaApp", category: "addons")

public struct InstalledAddon: Codable, Sendable, Equatable, Identifiable {
    public let manifestURL: String
    /// Nil until the manifest has been fetched once, e.g. for the preinstalled default.
    public var manifest: AddonManifest?

    public var id: String { manifestURL }

    /// Safe to show: unlike the full URL, the host never carries configuration secrets.
    public var host: String {
        URL(string: manifestURL)?.host() ?? "Unknown host"
    }

    public var displayName: String {
        manifest?.name ?? host
    }
}

/// The user's installed addons, in their chosen order.
///
/// Persisted in `UserDefaults` because tvOS offers no durable file storage;
/// the system may purge an app's files there at any time.
@MainActor @Observable
public final class AddonStore {
    public enum InstallError: Error, Equatable {
        case invalidURL
        case alreadyInstalled
        case unreachable(String)
        case invalidManifest
    }

    public typealias ManifestLoader = @Sendable (AddonClient) async throws -> AddonManifest

    public nonisolated static let cinemetaURL = "https://v3-cinemeta.strem.io/manifest.json"
    private static let defaultsKey = "installedAddons"

    public private(set) var addons: [InstalledAddon]
    /// Addons whose manifest couldn't be refreshed this session. They keep
    /// their last known manifest so browsing still works from cached data.
    public private(set) var unreachable: Set<InstalledAddon.ID> = []

    private let defaults: UserDefaults
    private let loadManifest: ManifestLoader

    public init(defaults: UserDefaults = .standard, loadManifest: @escaping ManifestLoader = { try await $0.manifest() }) {
        self.defaults = defaults
        self.loadManifest = loadManifest
        addons = Self.restore(from: defaults)
    }

    @discardableResult
    public func install(manifestURL string: String) async throws(InstallError) -> InstalledAddon {
        let client: AddonClient
        do {
            client = try AddonClient(manifestURL: string)
        } catch {
            throw .invalidURL
        }
        guard !isInstalled(client.manifestURL) else { throw .alreadyInstalled }

        let manifest: AddonManifest
        do {
            manifest = try await loadManifest(client)
        } catch is DecodingError {
            throw .invalidManifest
        } catch {
            throw .unreachable(Self.describe(error))
        }
        // Another install of the same URL may have finished while this one was loading.
        guard !isInstalled(client.manifestURL) else { throw .alreadyInstalled }

        let addon = InstalledAddon(manifestURL: client.manifestURL, manifest: manifest)
        addons.append(addon)
        save()
        return addon
    }

    public func remove(_ id: InstalledAddon.ID) {
        addons.removeAll { $0.id == id }
        unreachable.remove(id)
        save()
    }

    /// Same semantics as SwiftUI's `onMove`: `destination` is an index in the list before the move.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { addons[$0] }
        var remaining = addons.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertionIndex = destination - source.count(in: 0..<destination)
        remaining.insert(contentsOf: moving, at: insertionIndex)
        addons = remaining
        save()
    }

    /// Re-fetches every manifest so addon updates (new catalogs, renamed addons) take effect.
    public func refreshManifests() async {
        let loadManifest = loadManifest
        await withTaskGroup(of: (InstalledAddon.ID, Result<AddonManifest, Error>).self) { group in
            for addon in addons {
                group.addTask {
                    do {
                        let client = try AddonClient(manifestURL: addon.manifestURL)
                        return (addon.id, .success(try await loadManifest(client)))
                    } catch {
                        return (addon.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                // The addon may have been removed while its manifest was loading.
                guard let index = addons.firstIndex(where: { $0.id == id }) else { continue }
                switch result {
                case .success(let manifest):
                    addons[index].manifest = manifest
                    unreachable.remove(id)
                case .failure(let error):
                    // Log the host only: configured addon URLs often embed API keys.
                    let host = URL(string: id)?.host() ?? "addon"
                    log.error("Couldn't refresh \(host, privacy: .public): \(Self.describe(error), privacy: .public)")
                    unreachable.insert(id)
                }
            }
        }
        save()
    }

    private func isInstalled(_ manifestURL: String) -> Bool {
        addons.contains { $0.manifestURL == manifestURL }
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(addons), forKey: Self.defaultsKey)
        } catch {
            log.error("Couldn't save addons: \(error)")
        }
    }

    private static func restore(from defaults: UserDefaults) -> [InstalledAddon] {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return []
        }
        do {
            // Cinemeta is now built into discovery, rather than an installed addon.
            return try JSONDecoder().decode([InstalledAddon].self, from: data)
                .filter { $0.manifestURL != cinemetaURL }
        } catch {
            // Keep the stored data untouched so a fixed build can still read it;
            // it's only overwritten once the user changes their addons.
            log.error("Couldn't decode saved addons: \(error)")
            return []
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case AddonError.httpStatus(let code, _): "The addon responded with HTTP \(code)."
        default: error.localizedDescription
        }
    }
}
