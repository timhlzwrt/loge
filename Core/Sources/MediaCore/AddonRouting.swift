import Foundation

/// One catalog of one installed addon, e.g. Cinemeta's popular movies.
public struct CatalogSource: Sendable, Hashable, Identifiable {
    public let manifestURL: String
    public let catalog: AddonManifest.Catalog

    public var id: String { "\(manifestURL)|\(catalog.type)|\(catalog.id)" }

    /// "Popular Movies": the catalog name followed by its content type.
    public var title: String {
        [catalog.name ?? catalog.id, Self.typeLabel(catalog.type)].joined(separator: " ")
    }

    public func items(search: String? = nil) async throws -> [MetaPreview] {
        let client = try AddonClient(manifestURL: manifestURL)
        let extra = search.map { [(name: "search", value: $0)] } ?? []
        return try await client.catalog(type: catalog.type, id: catalog.id, extra: extra)
    }

    static func typeLabel(_ type: String) -> String {
        switch type {
        case "movie": "Movies"
        case "series": "Series"
        case "channel": "Channels"
        case "tv": "TV"
        default: type.prefix(1).uppercased() + type.dropFirst()
        }
    }
}

// Addon order is the user's priority order, so every lookup walks the list front to back.
extension [InstalledAddon] {
    /// Catalogs that can be shown as rows without user input.
    public var homeCatalogs: [CatalogSource] {
        catalogs { $0.isBrowsable }
    }

    public var searchCatalogs: [CatalogSource] {
        catalogs { $0.supportsSearch }
    }

    /// The first addon that serves details for this item, as Stremio picks it.
    public func metaClient(type: String, id: String) -> AddonClient? {
        first { $0.manifest?.provides("meta", type: type, id: id) == true }
            .flatMap { try? AddonClient(manifestURL: $0.manifestURL) }
    }

    private func catalogs(where include: (AddonManifest.Catalog) -> Bool) -> [CatalogSource] {
        flatMap { addon in
            (addon.manifest?.catalogs ?? [])
                .filter(include)
                .map { CatalogSource(manifestURL: addon.manifestURL, catalog: $0) }
        }
    }
}
