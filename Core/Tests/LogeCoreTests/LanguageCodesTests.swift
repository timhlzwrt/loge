import Testing
@testable import LogeCore

struct LanguageCodesTests {
    @Test func includesTerminologyAndBibliographicCodes() {
        #expect(LanguageCodes.trackTags(for: "de") == "de,deu,ger")
        #expect(LanguageCodes.trackTags(for: "en") == "en,eng")
        #expect(LanguageCodes.trackTags(for: "ja") == "ja,jpn")
    }

    @Test func normalisesSubtitleAddonCodes() {
        #expect(LanguageCodes.alpha2(for: "eng") == "en")
        #expect(LanguageCodes.alpha2(for: "ger") == "de")
        #expect(LanguageCodes.alpha2(for: "deu") == "de")
        #expect(LanguageCodes.alpha2(for: "pob") == "pt")
        #expect(LanguageCodes.alpha2(for: "fr") == "fr")
        #expect(LanguageCodes.alpha2(for: "und") == nil)
        #expect(LanguageCodes.alpha2(for: "xyz") == nil)
    }
}
