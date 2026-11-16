import Foundation

/// Which shelves Home shows and in what order. It syncs with the appearance settings, so an
/// addon's catalog is named by the addon's manifest `id`, never its URL, which can carry the
/// user's keys; the URL is looked up among the installed addons when Home is drawn.
public struct HomeLayout: Equatable, Sendable {
    public enum Shelf: Hashable, Sendable {
        /// One of `DiscoveryCatalogs.home`, by `HomeLayout.key(of:)`.
        case feed(String)
        case genres
        case continueWatching, watchLater, recommended
        case catalog(AddonCatalog)

        /// Built-in and library shelves can only be hidden, so they never go missing.
        public var isRemovable: Bool {
            if case .catalog = self { true } else { false }
        }
    }

    public struct AddonCatalog: Hashable, Sendable {
        public let addonID: String
        public let type: String
        public let catalogID: String
    }

    public struct Entry: Hashable, Sendable, Identifiable {
        public let shelf: Shelf
        public var isHidden: Bool

        public var id: Shelf { shelf }
    }

    /// What Home draws for a shelf that is shown and available on this device.
    public enum Row: Hashable, Sendable, Identifiable {
        case catalog(CatalogSource)
        case genres, continueWatching, watchLater, recommended

        public var id: String {
            switch self {
            case .catalog(let source): source.id
            case .genres: "genres"
            case .continueWatching: "continueWatching"
            case .watchLater: "watchLater"
            case .recommended: "recommended"
            }
        }
    }

    public static let storageKey = "homeLayout"

    public private(set) var entries: [Entry]

    /// Duplicates are dropped and built-in shelves missing from `entries` are appended, so
    /// shelves added in later versions appear on Home.
    public init(_ entries: [Entry]) {
        var seen = Set<Shelf>()
        let kept = entries.filter { seen.insert($0.shelf).inserted }
        self.entries = kept + Self.builtIns.filter { !seen.contains($0) }.map { Entry(shelf: $0, isHidden: false) }
    }

    /// Home as it was before it could be arranged: library rows, the popular shelves,
    /// genres, then the narrower shelves.
    public static let `default` = HomeLayout([])

    private static let builtIns: [Shelf] = {
        let feeds = DiscoveryCatalogs.home.map { Shelf.feed(key(of: $0)) }
        return [.continueWatching, .watchLater, .recommended] + feeds.prefix(3) + [.genres] + feeds.dropFirst(3)
    }()

    private static let feeds = Dictionary(uniqueKeysWithValues: DiscoveryCatalogs.home.map { (key(of: $0), $0) })

    /// A built-in feed's identity: its catalog and genre, without the service's URL.
    static func key(of feed: CatalogSource) -> String {
        [feed.catalog.type, feed.catalog.id, feed.defaultGenre].compactMap(\.self).joined(separator: "/")
    }

    /// Reads what `storedData` wrote; anything unreadable is the default layout.
    public init(storedData: Data?) {
        self = storedData.flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? .default
    }

    /// Only strings and booleans, which always encode.
    public var storedData: Data { try! JSONEncoder().encode(self) }

    // MARK: Resolving

    /// The shown shelves this device can draw, in order. A shelf whose addon or catalog isn't
    /// installed here is skipped but stays in the layout, for the devices that have it.
    public func rows(addons: [InstalledAddon]) -> [Row] {
        entries.filter { !$0.isHidden }.compactMap { entry in
            switch entry.shelf {
            case .feed, .catalog: source(for: entry.shelf, addons: addons).map(Row.catalog)
            case .genres: .genres
            case .continueWatching: .continueWatching
            case .watchLater: .watchLater
            case .recommended: .recommended
            }
        }
    }

    /// The catalog a feed or addon shelf loads from, if it's available on this device.
    public func source(for shelf: Shelf, addons: [InstalledAddon]) -> CatalogSource? {
        switch shelf {
        case .feed(let key):
            return Self.feeds[key]
        case .catalog(let catalog):
            guard let addon = Self.addon(for: catalog, in: addons),
                  let match = Self.match(catalog, in: addon) else { return nil }
            return CatalogSource(manifestURL: addon.manifestURL, catalog: match)
        default:
            return nil
        }
    }

    /// The first installed addon, in the user's order, with this manifest `id` that offers the
    /// catalog. The same addon can be installed twice with different configurations.
    public static func addon(for catalog: AddonCatalog, in addons: [InstalledAddon]) -> InstalledAddon? {
        addons.first { $0.manifest?.id == catalog.addonID && match(catalog, in: $0) != nil }
    }

    private static func match(_ catalog: AddonCatalog, in addon: InstalledAddon) -> AddonManifest.Catalog? {
        addon.manifest?.catalogs.first { $0.type == catalog.type && $0.id == catalog.catalogID && $0.isBrowsable }
    }

    /// The catalogs of `addon` that can be a shelf and aren't one yet.
    public func addableCatalogs(of addon: InstalledAddon) -> [CatalogSource] {
        let shelves = Set(entries.map(\.shelf))
        return [addon].homeCatalogs.filter { source in
            Self.shelf(for: source, of: addon).map { !shelves.contains($0) } ?? false
        }
    }

    private static func shelf(for source: CatalogSource, of addon: InstalledAddon) -> Shelf? {
        guard let id = addon.manifest?.id else { return nil }
        return .catalog(AddonCatalog(addonID: id, type: source.catalog.type, catalogID: source.catalog.id))
    }

    // MARK: Editing

    /// Same semantics as SwiftUI's `onMove`: `destination` is an index in the list before the move.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { entries[$0] }
        var remaining = entries.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - source.count(in: 0..<destination))
        entries = remaining
    }

    public mutating func setHidden(_ isHidden: Bool, for shelf: Shelf) {
        guard let index = entries.firstIndex(where: { $0.shelf == shelf }) else { return }
        entries[index].isHidden = isHidden
    }

    public mutating func remove(_ shelf: Shelf) {
        guard shelf.isRemovable else { return }
        entries.removeAll { $0.shelf == shelf }
    }

    /// Appends `source` of `addon` as a shown shelf.
    public mutating func add(_ source: CatalogSource, of addon: InstalledAddon) {
        guard let shelf = Self.shelf(for: source, of: addon) else { return }
        self = HomeLayout(entries + [Entry(shelf: shelf, isHidden: false)])
    }

    /// Sync accepts only layouts this size, with identifiers an addon would plausibly use.
    var isValid: Bool {
        entries.count <= 500 && entries.allSatisfy { entry in
            switch entry.shelf {
            case .feed(let key): key.utf8.count <= 200
            case .catalog(let catalog): [catalog.addonID, catalog.type, catalog.catalogID].allSatisfy { $0.utf8.count <= 200 }
            default: true
            }
        }
    }
}

extension [HomeLayout.Row] {
    /// The catalog shelves among these rows, in order.
    public var catalogs: [CatalogSource] {
        compactMap { if case .catalog(let source) = $0 { source } else { nil } }
    }
}

extension HomeLayout: Codable {
    private enum CodingKeys: String, CodingKey { case shelves }

    /// A shelf a later version added is skipped rather than failing the whole layout.
    public init(from decoder: Decoder) throws {
        struct Lenient: Decodable {
            let entry: Entry?
            init(from decoder: Decoder) { entry = try? Entry(from: decoder) }
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode([Lenient].self, forKey: .shelves).compactMap(\.entry))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .shelves)
    }
}

extension HomeLayout.Entry: Codable {
    private enum CodingKeys: String, CodingKey { case kind, feed, addon, type, catalog, hidden }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "feed": shelf = .feed(try container.decode(String.self, forKey: .feed))
        case "genres": shelf = .genres
        case "continueWatching": shelf = .continueWatching
        case "watchLater": shelf = .watchLater
        case "recommended": shelf = .recommended
        case "catalog":
            shelf = .catalog(HomeLayout.AddonCatalog(addonID: try container.decode(String.self, forKey: .addon),
                                                     type: try container.decode(String.self, forKey: .type),
                                                     catalogID: try container.decode(String.self, forKey: .catalog)))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown shelf")
        }
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch shelf {
        case .feed(let key):
            try container.encode("feed", forKey: .kind)
            try container.encode(key, forKey: .feed)
        case .genres: try container.encode("genres", forKey: .kind)
        case .continueWatching: try container.encode("continueWatching", forKey: .kind)
        case .watchLater: try container.encode("watchLater", forKey: .kind)
        case .recommended: try container.encode("recommended", forKey: .kind)
        case .catalog(let catalog):
            try container.encode("catalog", forKey: .kind)
            try container.encode(catalog.addonID, forKey: .addon)
            try container.encode(catalog.type, forKey: .type)
            try container.encode(catalog.catalogID, forKey: .catalog)
        }
        if isHidden { try container.encode(true, forKey: .hidden) }
    }
}
