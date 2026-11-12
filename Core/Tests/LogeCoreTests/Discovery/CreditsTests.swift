import Foundation
import Testing
@testable import LogeCore

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

    @Test func escapedNamesAreDecoded() throws {
        let json = #"{"id": "x", "type": "movie", "name": "X", "cast": ["Catherine O&apos;Hara", "Tom &amp; Jerry"]}"#
        let meta = try JSONDecoder().decode(Meta.self, from: Data(json.utf8))
        #expect(meta.people.map(\.name) == ["Catherine O'Hara", "Tom & Jerry"])
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
}
