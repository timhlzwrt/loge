import Foundation

/// The `manifest.json` every Stremio addon serves at its base URL.
public struct AddonManifest: Codable, Sendable, Equatable {
    public var id: String
    public var version: String
    public var name: String
    public var description: String?
    public var resources: [Resource]
    public var types: [String]
    public var idPrefixes: [String]?
    public var catalogs: [Catalog]

    public struct Catalog: Codable, Sendable, Hashable {
        public var type: String
        public var id: String
        public var name: String?
        public var extra: [Extra]?
        /// Legacy form of `extra[].isRequired`, still sent by many addons.
        public var extraRequired: [String]?
        /// Legacy form of `extra[].name`.
        public var extraSupported: [String]?

        public struct Extra: Codable, Sendable, Hashable {
            public var name: String
            public var isRequired: Bool?
        }

        /// Catalogs that need input (a genre, a query, a list of IDs) can't be shown as a plain row.
        public var isBrowsable: Bool {
            (extraRequired ?? []).isEmpty && !(extra ?? []).contains { $0.isRequired == true }
        }

        public var supportsSearch: Bool {
            (extra ?? []).contains { $0.name == "search" } || (extraSupported ?? []).contains("search")
        }
    }

    /// Whether this addon answers `resource` requests for an item, honouring
    /// per-resource type and ID-prefix restrictions over the manifest-wide ones.
    public func provides(_ resource: String, type: String, id: String) -> Bool {
        guard let declared = resources.first(where: { $0.name == resource }) else { return false }
        guard (declared.types ?? types).contains(type) else { return false }
        guard let prefixes = declared.idPrefixes ?? idPrefixes else { return true }
        return prefixes.contains { id.hasPrefix($0) }
    }

    /// Addons declare resources either as a bare name (`"stream"`) or as an object
    /// that narrows the types and ID prefixes it applies to.
    public struct Resource: Codable, Sendable, Equatable {
        public var name: String
        public var types: [String]?
        public var idPrefixes: [String]?

        public init(name: String, types: [String]? = nil, idPrefixes: [String]? = nil) {
            self.name = name
            self.types = types
            self.idPrefixes = idPrefixes
        }

        public init(from decoder: Decoder) throws {
            if let name = try? decoder.singleValueContainer().decode(String.self) {
                self.init(name: name)
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                name: try container.decode(String.self, forKey: .name),
                types: try container.decodeIfPresent([String].self, forKey: .types),
                idPrefixes: try container.decodeIfPresent([String].self, forKey: .idPrefixes)
            )
        }
    }
}
