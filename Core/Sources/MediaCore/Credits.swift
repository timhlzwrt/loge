import Foundation

/// Someone credited on a title, with every role they had on it.
public struct Person: Sendable, Hashable, Identifiable {
    public enum Role: Sendable, Hashable {
        case actor, director, writer
    }

    public var name: String
    public var roles: [Role]

    public var id: String { name }

    public init(name: String, roles: [Role]) {
        self.name = name
        self.roles = roles
    }

    /// The titles among name-search results that credit this person, newest first, plus the
    /// title they were found on. Searching for a name also matches titles that merely contain
    /// it ("Tom Hanks: The Nomad"), and can miss titles the person is known for.
    public func titles(in results: [MetaPreview], foundOn title: MetaPreview) -> [MetaPreview] {
        var credited = results.filter { $0.id != title.id && $0.credits(name) }
        credited.append(title)
        // Stable, so titles from the same year keep the addon's relevance order.
        return credited.sorted { ($0.startYear ?? 0) > ($1.startYear ?? 0) }
    }
}

extension Meta {
    /// Cast in billing order, then directors and writers; someone with several roles appears once.
    public var people: [Person] {
        var people: [Person] = []
        func add(_ names: [String]?, as role: Person.Role) {
            for name in names ?? [] {
                let name = name.trimmingCharacters(in: .whitespaces)
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

extension MetaPreview {
    func credits(_ name: String) -> Bool {
        [cast, director, writer].contains { names in
            names?.contains { $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame } == true
        }
    }

    /// 2008 for "2008–2013".
    var startYear: Int? {
        releaseInfo.flatMap { Int($0.prefix(4)) }
    }
}
