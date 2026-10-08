import Foundation

public enum AddonError: Error, Equatable {
    case invalidManifestURL(String)
    case httpStatus(Int, URL)
}

/// Talks to one Stremio addon over its HTTP protocol:
/// `{base}/{resource}/{type}/{id}[/{extra}].json`.
public struct AddonClient: Sendable {
    /// The manifest URL without the trailing `/manifest.json`.
    public let baseURL: URL
    private let session: URLSession

    /// Accepts the URL users copy from addon pages, including `stremio://` install links.
    public init(manifestURL string: String, session: URLSession = .shared) throws {
        var string = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("stremio://") {
            string = "https://" + string.dropFirst("stremio://".count)
        }
        guard var components = URLComponents(string: string),
              components.scheme == "https" || components.scheme == "http",
              components.host?.isEmpty == false,
              components.path.hasSuffix("/manifest.json")
        else {
            throw AddonError.invalidManifestURL(string)
        }
        components.path.removeLast("/manifest.json".count)
        guard let baseURL = components.url else {
            throw AddonError.invalidManifestURL(string)
        }
        self.baseURL = baseURL
        self.session = session
    }

    public func manifest() async throws -> AddonManifest {
        try await fetch(baseURL.appending(path: "manifest.json"))
    }

    public func catalog(type: String, id: String, extra: [(name: String, value: String)] = []) async throws -> [MetaPreview] {
        let response: CatalogResponse = try await fetch(resourceURL("catalog", type: type, id: id, extra: extra))
        return response.metas
    }

    public func meta(type: String, id: String) async throws -> Meta {
        let response: MetaResponse = try await fetch(resourceURL("meta", type: type, id: id))
        return response.meta
    }

    public func streams(type: String, id: String) async throws -> [StreamSource] {
        let response: StreamsResponse = try await fetch(resourceURL("stream", type: type, id: id))
        return response.streams
    }

    func resourceURL(_ resource: String, type: String, id: String, extra: [(name: String, value: String)] = []) -> URL {
        var path = [resource, Self.encode(type), Self.encode(id)].joined(separator: "/")
        if !extra.isEmpty {
            path += "/" + extra.map { "\(Self.encode($0.name))=\(Self.encode($0.value))" }.joined(separator: "&")
        }
        // The path is already percent-encoded, so append it to the string form;
        // `appending(path:)` would encode the `%` signs a second time.
        return URL(string: baseURL.absoluteString + "/" + path + ".json")!
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AddonError.httpStatus(http.statusCode, url)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Matches JavaScript's `encodeURIComponent`, which the reference
    /// implementation uses, so `tt0903747:1:1` becomes `tt0903747%3A1%3A1`.
    private static let componentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )

    private static func encode(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: componentAllowed) ?? component
    }
}
