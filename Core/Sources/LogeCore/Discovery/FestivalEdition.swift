import Foundation

/// Dated award facts, independent of whether a streaming database has mapped the title yet.
public struct FestivalEdition: Decodable, Sendable {
    public let festival: FilmCollection
    public let year: Int
    public let checkedOn: String
    public let coverage: String
    public let sources: [URL]
    public let awards: [FestivalAward]

    public enum Failure: Error { case missingData, invalidData }

    public static func all() throws -> [Self] {
        try bundled.get()
    }

    /// Decoded once: navigation destinations ask again each time the stack updates.
    private static let bundled: Result<[FestivalEdition], any Error> = Result { () throws -> [FestivalEdition] in
        guard let url = Bundle.module.url(forResource: "festival-awards-2026", withExtension: "json") else {
            throw Failure.missingData
        }
        return try decode(Data(contentsOf: url))
    }

    public static func edition(for festival: FilmCollection) throws -> Self {
        guard let edition = try all().first(where: { $0.festival == festival }) else { throw Failure.missingData }
        return edition
    }

    static func decode(_ data: Data) throws -> [Self] {
        let editions = try JSONDecoder().decode([Self].self, from: data)
        guard Set(editions.map(\.festival)) == Set(FilmCollection.festivals),
              editions.count == FilmCollection.festivals.count else { throw Failure.invalidData }
        for edition in editions {
            guard edition.year >= 2026, !edition.coverage.isEmpty, !edition.awards.isEmpty,
                  edition.checkedOn.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil,
                  !edition.sources.isEmpty,
                  edition.sources.allSatisfy({ $0.scheme == "https" && $0.host() != nil && $0.user == nil && $0.password == nil }),
                  Set(edition.awards.map(\.id)).count == edition.awards.count,
                  edition.awards.allSatisfy({ !$0.section.isEmpty && !$0.award.isEmpty && !$0.title.isEmpty }) else {
                throw Failure.invalidData
            }
        }
        return editions
    }
}

public struct FestivalAward: Decodable, Sendable, Identifiable {
    public let section: String
    public let award: String
    public let title: String
    public let recipient: String?
    public let isFilm: Bool
    public var id: String { [section, award, title, recipient ?? ""].joined(separator: "\u{1F}") }
}
