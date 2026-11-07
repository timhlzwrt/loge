import Foundation

/// The setup a sync account carries between devices: addons and preferences, never
/// credentials, remembered sources or connection measurements.
public struct SyncedSettings: Codable, Equatable, Sendable {
    public var addonURLs: [String]
    public var audioLanguage: String
    public var subtitleLanguage: String
    public var subtitleScale: Double
    public var maximumSourceGigabytes: Int
    public var accent: Accent

    /// The `UserDefaults` keys the app's settings screens bind to.
    public enum Key {
        public static let audioLanguage = "audioLanguage"
        public static let subtitleLanguage = "subtitleLanguage"
        public static let subtitleScale = "subtitleScale"
        public static let maximumSourceGigabytes = "maximumAutomaticSourceGigabytes"
        public static let accent = Accent.storageKey
    }

    public static let subtitleScales: [Double] = [0.8, 1, 1.25, 1.6]
    /// 0 means no limit.
    public static let maximumSourceGigabyteOptions = [0, 10, 25, 50, 100]

    public init(addonURLs: [String] = [], audioLanguage: String = "en", subtitleLanguage: String = "",
                subtitleScale: Double = 1, maximumSourceGigabytes: Int = 50, accent: Accent = .white) {
        self.addonURLs = addonURLs
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subtitleScale = subtitleScale
        self.maximumSourceGigabytes = maximumSourceGigabytes
        self.accent = accent
    }

    /// Unset preferences read as their defaults, so a fresh device and the server agree.
    init(addonURLs: [String], defaults: UserDefaults) {
        let fallback = Self()
        self.init(addonURLs: addonURLs,
                  audioLanguage: defaults.string(forKey: Key.audioLanguage) ?? fallback.audioLanguage,
                  subtitleLanguage: defaults.string(forKey: Key.subtitleLanguage) ?? fallback.subtitleLanguage,
                  subtitleScale: defaults.object(forKey: Key.subtitleScale) as? Double ?? fallback.subtitleScale,
                  maximumSourceGigabytes: defaults.object(forKey: Key.maximumSourceGigabytes) as? Int
                      ?? fallback.maximumSourceGigabytes,
                  accent: defaults.string(forKey: Key.accent).flatMap(Accent.init) ?? fallback.accent)
    }

    /// Writes the preferences in `categories`; addons belong to `AddonStore`.
    func writePreferences(to defaults: UserDefaults, categories: Set<SyncCategory>) {
        if categories.contains(.playback) {
            defaults.set(audioLanguage, forKey: Key.audioLanguage)
            defaults.set(subtitleLanguage, forKey: Key.subtitleLanguage)
            defaults.set(subtitleScale, forKey: Key.subtitleScale)
            defaults.set(maximumSourceGigabytes, forKey: Key.maximumSourceGigabytes)
        }
        if categories.contains(.appearance) { defaults.set(accent.rawValue, forKey: Key.accent) }
    }

    public func validated() throws -> Self {
        guard addonURLs.count <= 100,
              Set(addonURLs).count == addonURLs.count,
              ([""] + LanguageCodes.common).contains(audioLanguage),
              ([""] + LanguageCodes.common).contains(subtitleLanguage),
              Self.subtitleScales.contains(subtitleScale),
              Self.maximumSourceGigabyteOptions.contains(maximumSourceGigabytes)
        else { throw SyncError.invalidData }
        for url in addonURLs {
            guard url.utf8.count <= 32_768,
                  let client = try? AddonClient(manifestURL: url), client.manifestURL == url,
                  url != AddonStore.cinemetaURL
            else { throw SyncError.invalidData }
        }
        return self
    }

    public enum Field: String, Codable, CaseIterable, Sendable {
        case addonURLs, audioLanguage, subtitleLanguage, subtitleScale, maximumSourceGigabytes, accent
    }

    public struct Merge: Sendable {
        public let settings: SyncedSettings
        public let conflicts: Set<Field>
    }

    /// The ordered addon list is one field: unioning lists would resurrect removals.
    public static func merged(base: Self, local: Self, remote: Self) -> Merge {
        var result = local
        var conflicts = Set<Field>()
        func choose<T: Equatable>(_ key: WritableKeyPath<Self, T>, _ field: Field) {
            if local[keyPath: key] == base[keyPath: key] {
                result[keyPath: key] = remote[keyPath: key]
            } else if remote[keyPath: key] != base[keyPath: key], local[keyPath: key] != remote[keyPath: key] {
                conflicts.insert(field)
            }
        }
        choose(\.addonURLs, .addonURLs)
        choose(\.audioLanguage, .audioLanguage)
        choose(\.subtitleLanguage, .subtitleLanguage)
        choose(\.subtitleScale, .subtitleScale)
        choose(\.maximumSourceGigabytes, .maximumSourceGigabytes)
        choose(\.accent, .accent)
        return Merge(settings: result, conflicts: conflicts)
    }

    /// The fields in `categories`, with every other field at its default.
    func only(_ categories: Set<SyncCategory>) -> Self {
        var result = Self()
        if categories.contains(.addons) { result.addonURLs = addonURLs }
        if categories.contains(.playback) {
            result.audioLanguage = audioLanguage
            result.subtitleLanguage = subtitleLanguage
            result.subtitleScale = subtitleScale
            result.maximumSourceGigabytes = maximumSourceGigabytes
        }
        if categories.contains(.appearance) { result.accent = accent }
        return result
    }

    func excluding(_ categories: Set<SyncCategory>) -> Self { only(Set(SyncCategory.allCases).subtracting(categories)) }

    func replacing(_ fields: Set<Field>, from source: Self) -> Self {
        var result = self
        for field in fields {
            switch field {
            case .addonURLs: result.addonURLs = source.addonURLs
            case .audioLanguage: result.audioLanguage = source.audioLanguage
            case .subtitleLanguage: result.subtitleLanguage = source.subtitleLanguage
            case .subtitleScale: result.subtitleScale = source.subtitleScale
            case .maximumSourceGigabytes: result.maximumSourceGigabytes = source.maximumSourceGigabytes
            case .accent: result.accent = source.accent
            }
        }
        return result
    }
}
