import Foundation
import Testing
@testable import MediaCore

struct CreditsTests {
    @Test func movieListsCastThenCrewWithSharedRolesMerged() throws {
        let meta = try decodeFixture("cinemeta-meta-movie", as: MetaResponse.self).meta

        #expect(meta.people.map(\.name) == [
            "Matthew McConaughey", "Anne Hathaway", "Jessica Chastain", "Christopher Nolan", "Jonathan Nolan",
        ])
        #expect(meta.people.first { $0.name == "Christopher Nolan" }?.roles == [.director, .writer])
        #expect(meta.country == "United States, United Kingdom, Canada")
        #expect(meta.awards?.hasPrefix("Won 1 Oscar") == true)
        #expect(meta.releaseDate == Date(timeIntervalSince1970: 1_415_318_400))
    }

    @Test func seriesWithoutDirectorsKeepsItsWriters() throws {
        let meta = try decodeFixture("cinemeta-meta-series", as: MetaResponse.self).meta

        #expect(meta.people.map(\.roles) == [[.actor], [.actor], [.actor], [.writer]])
    }

    @Test func linksStandInForMissingCreditFields() throws {
        let json = #"""
        {"id": "x", "type": "movie", "name": "X", "cast": [], "links": [
            {"name": "Ana", "category": "Cast", "url": "stremio:///search?search=Ana"},
            {"name": "Drama", "category": "Genres", "url": "stremio:///discover/x"},
            {"name": "Ben", "category": "Directors", "url": "stremio:///search?search=Ben"}
        ]}
        """#
        let meta = try JSONDecoder().decode(Meta.self, from: Data(json.utf8))
        #expect(meta.people == [Person(name: "Ana", roles: [.actor]), Person(name: "Ben", roles: [.director])])
    }

    @Test func personTitlesKeepOnlyCreditedResultsNewestFirst() {
        let person = Person(name: "Tom Hanks", roles: [.actor])
        let found = MetaPreview(id: "tt3", type: "movie", name: "Larry Crowne", releaseInfo: "2011")
        let results = [
            MetaPreview(id: "tt1", type: "movie", name: "Tom Hanks: The Nomad", releaseInfo: "2023"),
            MetaPreview(id: "tt2", type: "movie", name: "Greyhound", releaseInfo: "2020", cast: ["tom hanks"]),
            MetaPreview(id: "tt4", type: "movie", name: "Dragnet", releaseInfo: "1987", writer: ["Tom Hanks"]),
            MetaPreview(id: "tt5", type: "movie", name: "That Thing You Do!", releaseInfo: "1996", director: ["Tom Hanks"]),
        ]

        // The title they were found on is kept even though search didn't return it.
        #expect(person.titles(in: results, foundOn: found).map(\.id) == ["tt2", "tt3", "tt5", "tt4"])
        #expect(person.titles(in: results + [found], foundOn: found).filter { $0.id == "tt3" }.count == 1)
    }
}
