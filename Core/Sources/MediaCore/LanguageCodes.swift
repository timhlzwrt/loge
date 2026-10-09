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
