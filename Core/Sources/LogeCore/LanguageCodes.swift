import Foundation

public enum LanguageCodes {
    /// Languages offered as audio and subtitle preferences, as ISO 639-1 codes.
    public static let common = [
        "ar", "cs", "da", "de", "el", "en", "es", "fi", "fr", "he", "hi", "hu", "it", "ja",
        "ko", "nl", "no", "pl", "pt", "ro", "ru", "sv", "th", "tr", "uk", "zh",
    ]

    /// ISO 639-2/B codes that differ from the terminology codes Foundation returns.
    /// Matroska files commonly use these, e.g. `ger` rather than `deu`.
    private static let bibliographic = [
        "de": "ger", "fr": "fre", "zh": "chi", "nl": "dut", "cs": "cze", "el": "gre",
        "fa": "per", "ro": "rum", "sk": "slo", "hy": "arm", "ka": "geo", "is": "ice",
        "mk": "mac", "ms": "may", "my": "bur", "sq": "alb", "eu": "baq", "cy": "wel",
    ]

    /// Codes OpenSubtitles uses for regional variants that ISO 639-2 doesn't have.
    private static let openSubtitles = ["pob": "pt", "spn": "es", "zht": "zh", "zhe": "zh", "scc": "sr"]

    /// The ISO 639-1 code for a language tag in any form tracks and subtitle addons use,
    /// `en`, `eng` or `ger`, or nil when it isn't a language.
    public static func alpha2(for tag: String) -> String? {
        let tag = tag.lowercased()
        if let code = openSubtitles[tag] ?? bibliographic.first(where: { $0.value == tag })?.key {
            return code
        }
        // Codes without a two-letter form, such as `und` (undetermined), aren't usable here.
        return Locale.LanguageCode(tag).identifier(.alpha2).flatMap { $0.count == 2 ? $0 : nil }
    }

    /// Every tag a track in `language` might carry, for mpv's `alang`/`slang`:
    /// `de` gives `de,deu,ger`.
    public static func trackTags(for language: String) -> String {
        var tags = [language]
        if let alpha3 = Locale.LanguageCode(language).identifier(.alpha3), alpha3 != language {
            tags.append(alpha3)
        }
        if let alternative = bibliographic[language] {
            tags.append(alternative)
        }
        return tags.joined(separator: ",")
    }
}

public extension Locale {
    /// The locale for dates, numbers and sizes the app shows. The interface is English only, so
    /// formatting by the device region would mix "5. November 2014" or "1,5 GB" into English text.
    /// Clock times use the device locale instead, so they follow its 12- or 24-hour setting.
    static let interface = Locale(identifier: "en_US")
}
