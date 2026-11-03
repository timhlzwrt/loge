import Foundation
import Testing
@testable import LogeCore

struct FestivalEditionTests {
    @Test func everyFestivalHasADatedEditionAndCompletePublishedSections() throws {
        let editions = try FestivalEdition.all()
        #expect(editions.count == 7)
        let expected: [FilmCollection: Int] = [.cannes: 21, .berlin: 66, .venice: 21, .sundance: 40,
                                              .toronto: 36, .locarno: 34, .sanSebastian: 60]
        for edition in editions {
            #expect(edition.year == 2026)
            #expect(edition.checkedOn == "2026-11-03")
            #expect(edition.awards.count == expected[edition.festival])
            #expect(edition.sources.allSatisfy { $0.scheme == "https" })
            #expect(edition.awards.contains { $0.isFilm })
            #expect(!edition.coverage.isEmpty)
        }
    }

    @Test func tiesAndRepeatedFilmsRemainSeparateAwards() throws {
        let cannes = try FestivalEdition.edition(for: .cannes)
        #expect(cannes.awards.filter { $0.award == "Best Director — joint winner" }.count == 2)
        let sundance = try FestivalEdition.edition(for: .sundance)
        #expect(sundance.awards.filter { $0.title == "Josephine" }.count == 2)
        #expect(sundance.awards.contains { $0.award == "Gayle Stevens Award" && !$0.isFilm })
        #expect(sundance.awards.allSatisfy { !$0.id.hasPrefix("tt") })
    }

    @Test func invalidOrIncompleteDataCannotMasqueradeAsAnEmptySuccess() {
        #expect(throws: (any Error).self) { try FestivalEdition.decode(Data("[]".utf8)) }
        #expect(throws: (any Error).self) { try FestivalEdition.decode(Data("{}".utf8)) }
        #expect(throws: FestivalEdition.Failure.self) { try FestivalEdition.edition(for: .nolan) }
    }
}
