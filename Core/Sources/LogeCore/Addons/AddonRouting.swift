import Foundation

/// One catalog feed, either managed by loge or supplied by an installed addon.
public struct CatalogSource: Sendable, Hashable, Identifiable {
    public let manifestURL: String
    public let catalog: AddonManifest.Catalog
    public let defaultGenre: String?
    private let displayTitle: String?
    /// For addons that draw ratings onto their posters, which don't fit the app's
    /// plain artwork: their IMDb titles show Cinemeta's artwork instead.
    var usesCinemetaArtwork = false
    /// For a narrow column, where `title` would be cut off.
    var compactTitle: String?

    public init(manifestURL: String, catalog: AddonManifest.Catalog, title: String? = nil, genre: String? = nil) {
        self.manifestURL = manifestURL
        self.catalog = catalog
        self.displayTitle = title
        self.defaultGenre = genre
    }

    public var id: String {
        let base = "\(manifestURL)|\(catalog.type)|\(catalog.id)"
        return defaultGenre.map { base + "|" + $0 } ?? base
    }

    /// "Popular Movies": the catalog name followed by its content type.
    public var title: String {
        displayTitle ?? [catalog.name ?? catalog.id, Self.typeLabel(catalog.type)].joined(separator: " ")
    }

    public var shortTitle: String { compactTitle ?? title }

    /// A search in a genre, or by a source fixed to one, returns only titles in that genre.
    /// - Parameter skip: How many items to skip, for loading further pages.
    public func items(search: String? = nil, genre: String? = nil, skip: Int = 0) async throws -> [MetaPreview] {
        let client = try AddonClient(manifestURL: manifestURL)
        var extra: [(name: String, value: String)] = []
        if let search { extra.append((name: "search", value: search)) }
        if let genre = genre ?? (search == nil ? defaultGenre : nil) {
            extra.append((name: "genre", value: genre))
        }
        if skip > 0 { extra.append((name: "skip", value: String(skip))) }
        let url = client.resourceURL("catalog", type: catalog.type, id: catalog.id, extra: extra)
        let fetched = try await CatalogCache.shared.metas(
            for: url, persist: search == nil && skip == 0,
            load: { try await client.data(from: url) },
            decode: AddonClient.decodeCatalog
        )
        let results = usesCinemetaArtwork ? fetched.map(\.withCinemetaArtwork) : fetched
        guard search != nil, let scope = genre ?? defaultGenre else { return results }
        return try await Self.narrow(results, to: scope) { try await client.meta(type: $0.type, id: $0.id) }
    }

    static func typeLabel(_ type: String) -> String {
        switch type {
        case MediaType.movie: "Movies"
        case MediaType.series: "Series"
        case "channel": "Channels"
        case "tv": "TV"
        default: type.prefix(1).uppercased() + type.dropFirst()
        }
    }
}

/// An installed addon that serves streams for a particular item.
public struct StreamProvider: Sendable, Identifiable {
    public let manifestURL: String
    public let name: String

    public var id: String { manifestURL }

    public func streams(type: String, id: String) async throws -> [StreamSource] {
        let manifestURL = manifestURL
        return try await StreamCache.shared.streams(manifestURL: manifestURL, type: type, id: id) {
            try await AddonClient(manifestURL: manifestURL).streams(type: type, id: id)
        }
    }

    /// Starts loading streams the user is likely to ask for next. A failure isn't kept,
    /// so the sources screen asks again and shows it.
    public func prefetchStreams(type: String, id: String) {
        Task { _ = try? await streams(type: type, id: id) }
    }
}

/// An installed addon that serves subtitles for a particular item.
public struct SubtitleProvider: Sendable, Identifiable {
    public let manifestURL: String
    public let name: String

    public var id: String { manifestURL }

    public func subtitles(type: String, id: String, filename: String?) async throws -> [Subtitle] {
        try await AddonClient(manifestURL: manifestURL).subtitles(type: type, id: id, filename: filename)
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

    /// User-installed metadata providers take priority over built-in IMDb metadata.
    public func metaClient(type: String, id: String) -> AddonClient? {
        if let installed = first(where: { $0.manifest?.provides("meta", type: type, id: id) == true }),
           let client = try? AddonClient(manifestURL: installed.manifestURL) {
            return client
        }
        guard type == MediaType.movie || type == MediaType.series, id.hasPrefix("tt") else { return nil }
        return try? AddonClient(manifestURL: AddonStore.cinemetaURL)
    }

    /// Addons that serve streams for this item, in the user's order.
    public func streamProviders(type: String, id: String) -> [StreamProvider] {
        compactMap { addon in
            guard addon.manifest?.provides("stream", type: type, id: id) == true else { return nil }
            return StreamProvider(manifestURL: addon.manifestURL, name: addon.displayName)
        }
    }

    /// Addons that serve subtitles for this item, in the user's order.
    public func subtitleProviders(type: String, id: String) -> [SubtitleProvider] {
        compactMap { addon in
            guard addon.manifest?.provides("subtitles", type: type, id: id) == true else { return nil }
            return SubtitleProvider(manifestURL: addon.manifestURL, name: addon.displayName)
        }
    }

    private func catalogs(where include: (AddonManifest.Catalog) -> Bool) -> [CatalogSource] {
        flatMap { addon in
            (addon.manifest?.catalogs ?? [])
                .filter(include)
                .map { CatalogSource(manifestURL: addon.manifestURL, catalog: $0) }
        }
    }
}
