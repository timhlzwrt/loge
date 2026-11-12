import Foundation

/// Someone credited on a title, with every role they had on it.
public struct Person: Sendable, Hashable, Identifiable {
    public enum Role: Sendable, Hashable {
        case actor, director, writer
    }

    public var name: String
    public var roles: [Role]
    public var tmdbID: Int?
    public var portraitURL: String?
    public var character: String?

    public var id: String { tmdbID.map { "tmdb:\($0)" } ?? name }

    public init(name: String, roles: [Role], tmdbID: Int? = nil, portraitURL: String? = nil, character: String? = nil) {
        self.name = name
        self.roles = roles
        self.tmdbID = tmdbID
        self.portraitURL = portraitURL
        self.character = character
    }
}

extension Meta {
    /// Cast in billing order, then directors and writers; someone with several roles appears once.
    public var people: [Person] {
        var people: [Person] = []
        func add(_ names: [String]?, as role: Person.Role) {
            for name in names ?? [] {
                let name = name.decodingHTMLEntities.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                if let index = people.firstIndex(where: { $0.name == name }) {
                    if !people[index].roles.contains(role) { people[index].roles.append(role) }
                } else {
                    people.append(Person(name: name, roles: [role]))
                }
            }
        }
        add(credits(cast, linkCategory: "Cast"), as: .actor)
        add(credits(director, linkCategory: "Directors"), as: .director)
        add(credits(writer, linkCategory: "Writers"), as: .writer)
        return people
    }

    private func credits(_ names: [String]?, linkCategory: String) -> [String]? {
        if let names, !names.isEmpty { return names }
        return links?.filter { $0.category == linkCategory }.compactMap(\.name)
    }
}

extension String {
    /// Cinemeta escapes some names as HTML: "Catherine O&apos;Hara".
    var decodingHTMLEntities: String {
        guard contains("&") else { return self }
        var result = self
        for (entity, character) in [("&apos;", "'"), ("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
