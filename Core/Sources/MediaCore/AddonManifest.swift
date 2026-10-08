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

    public struct Catalog: Codable, Sendable, Equatable {
        public var type: String
        public var id: String
        public var name: String?
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
