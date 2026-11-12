import Foundation

extension AddonManifest.Catalog {
    /// Whether a genre has to be picked before the catalog lists anything.
    public var requiresGenre: Bool {
        (extraRequired ?? []).contains("genre") || (extra ?? []).contains { $0.name == "genre" && $0.isRequired == true }
    }

    /// Cinemeta's "New" catalogs are filtered by release year through the genre extra.
    public var genresAreYears: Bool {
        !genres.isEmpty && genres.allSatisfy { $0.count == 4 && $0.allSatisfy(\.isNumber) }
    }

    /// Listable as is, or once one of its genres is picked.
    var isBrowsableByGenre: Bool {
        let required = Set((extraRequired ?? []) + (extra ?? []).filter { $0.isRequired == true }.map(\.name))
        return required.isEmpty || (required == ["genre"] && !genres.isEmpty)
    }
}

extension AddonManifest {
    /// The catalogs a grid of `source` can switch between. Addons offer sort orders as sibling
    /// catalogs of one type, like Cinemeta's Popular, New and Featured. A source fixed to a
    /// genre switches only to catalogs that offer it. Empty when there is nothing to switch to.
    public func sortOptions(for source: CatalogSource) -> [Catalog] {
        let options = catalogs.filter { catalog in
            catalog.type == source.catalog.type && catalog.isBrowsableByGenre
                && (source.defaultGenre.map(catalog.genres.contains) ?? true)
        }
        guard options.count > 1, options.contains(where: { $0.id == source.catalog.id }) else { return [] }
        return options
    }
}

extension [CatalogSource] {
    /// Every genre these catalogs can be filtered by, in the order they first appear.
    public var genres: [String] {
        var seen = Set<String>()
        return flatMap(\.catalog.genres).filter { seen.insert($0).inserted }
    }

    /// These catalogs limited to one type and genre, each titled "Movies · Comedy". Catalogs
    /// that don't offer the genre are left out, so a series-only genre shows only series.
    public func filtered(type: String?, genre: String?) -> [CatalogSource] {
        compactMap { source in
            guard type.map({ $0 == source.catalog.type }) ?? true else { return nil }
            guard let genre else { return source }
            guard source.catalog.genres.contains(genre) else { return nil }
            return CatalogSource(manifestURL: source.manifestURL, catalog: source.catalog,
                                 title: "\(source.title) · \(genre)", genre: genre)
        }
    }
}

extension CatalogSource {
    /// Addons answer a search regardless of genre, and Cinemeta's search results list no genres,
    /// so results that don't list theirs are looked up in their details. A title whose details
    /// fail to load is left out, since whether it belongs is unknown; if every lookup fails,
    /// the error is thrown so the search can be retried.
    static func narrow(
        _ results: [MetaPreview], to genre: String,
        details: @escaping @Sendable (MetaPreview) async throws -> Meta
    ) async throws -> [MetaPreview] {
        let (matches, failure) = await withTaskGroup(of: (Int, Result<Bool, Error>).self) { group in
            var remaining = results.enumerated().makeIterator()
            func enqueue(_ index: Int, _ preview: MetaPreview) {
                group.addTask {
                    if let genres = preview.genres, !genres.isEmpty {
                        return (index, .success(Self.genres(genres, contain: genre)))
                    }
                    do {
                        let meta = try await details(preview)
                        let genres = meta.genres ?? meta.links?.filter { $0.category == "Genres" }.compactMap(\.name) ?? []
                        return (index, .success(Self.genres(genres, contain: genre)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            // Every pause in typing starts another search, so lookups go a few at a time
            // rather than one request per result at once.
            for _ in 0..<Self.concurrentLookups {
                if let next = remaining.next() { enqueue(next.offset, next.element) }
            }
            var matches = [Bool?](repeating: nil, count: results.count)
            var failure: Error?
            for await (index, result) in group {
                switch result {
                case .success(let match): matches[index] = match
                case .failure(let error): failure = error
                }
                if let next = remaining.next() { enqueue(next.offset, next.element) }
            }
            return (matches, failure)
        }
        if let failure, matches.allSatisfy({ $0 == nil }) { throw failure }
        return zip(results, matches).filter { $0.1 == true }.map(\.0)
    }

    private static let concurrentLookups = 6

    private static func genres(_ genres: [String], contain genre: String) -> Bool {
        genres.contains { $0.caseInsensitiveCompare(genre) == .orderedSame }
    }
}
