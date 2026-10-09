import Testing
@testable import MediaCore

struct LanguageCodesTests {
    @Test func includesTerminologyAndBibliographicCodes() {
        #expect(LanguageCodes.trackTags(for: "de") == "de,deu,ger")
        #expect(LanguageCodes.trackTags(for: "en") == "en,eng")
        #expect(LanguageCodes.trackTags(for: "ja") == "ja,jpn")
    }
}
