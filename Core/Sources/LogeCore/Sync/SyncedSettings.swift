import Foundation

/// The setup a sync account carries between devices: addons and preferences, never
/// credentials, remembered sources or connection measurements.
public struct SyncedSettings: Codable, Equatable, Sendable {
    public var addonURLs: [String]
    public var audioLanguage: String
    public var subtitleLanguage: String
    public var subtitleScale: Double
    /// The highest bitrate, in Mbps, the app picks a source at by itself; 0 for no limit.
    public var maximumBitrate: Int
    public var homeLayout: HomeLayout

    /// The `UserDefaults` keys the app's settings screens bind to.
    public enum Key {
        public static let audioLanguage = "audioLanguage"
        public static let subtitleLanguage = "subtitleLanguage"
        public static let subtitleScale = "subtitleScale"
        public static let maximumBitrate = "maximumBitrate"
        /// The per-episode size limit the bitrate replaced.
        static let maximumSourceGigabytes = "maximumAutomaticSourceGigabytes"
        public static let homeLayout = HomeLayout.storageKey
    }

    public static let subtitleScales: [Double] = [0.8, 1, 1.25, 1.6]
    /// 0 means no limit.
    public static let maximumBitrateOptions = [0, 10, 25, 50, 100]

    public init(addonURLs: [String] = [], audioLanguage: String = "en", subtitleLanguage: String = "",
                subtitleScale: Double = 1, maximumBitrate: Int = 100, homeLayout: HomeLayout = .default) {
        self.addonURLs = addonURLs
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subtitleScale = subtitleScale
        self.maximumBitrate = maximumBitrate
        self.homeLayout = homeLayout
    }

    /// The preferences stored in `defaults`, without the addons, which belong to `AddonStore`.
    public init(preferencesIn defaults: UserDefaults) {
        self.init(addonURLs: [], defaults: defaults)
    }

    /// Unset preferences read as their defaults, so a fresh device and the server agree.
    init(addonURLs: [String], defaults: UserDefaults) {
        let fallback = Self()
        self.init(addonURLs: addonURLs,
                  audioLanguage: defaults.string(forKey: Key.audioLanguage) ?? fallback.audioLanguage,
                  subtitleLanguage: defaults.string(forKey: Key.subtitleLanguage) ?? fallback.subtitleLanguage,
                  subtitleScale: defaults.object(forKey: Key.subtitleScale) as? Double ?? fallback.subtitleScale,
                  maximumBitrate: defaults.object(forKey: Key.maximumBitrate) as? Int ?? fallback.maximumBitrate,
                  homeLayout: HomeLayout(storedData: defaults.data(forKey: Key.homeLayout)))
    }

    /// Carries over a stored size limit once: "No limit" stays so, any size becomes the
    /// default bitrate, since the two don't convert.
    public static func migrateSourceSizeLimit(in defaults: UserDefaults = .standard) {
        guard let gigabytes = defaults.object(forKey: Key.maximumSourceGigabytes) as? Int else { return }
        if defaults.object(forKey: Key.maximumBitrate) == nil {
            defaults.set(gigabytes == 0 ? 0 : Self().maximumBitrate, forKey: Key.maximumBitrate)
        }
        defaults.removeObject(forKey: Key.maximumSourceGigabytes)
    }

    /// Writes the preferences; addons belong to `AddonStore`.
    func writePreferences(to defaults: UserDefaults) {
        defaults.set(audioLanguage, forKey: Key.audioLanguage)
        defaults.set(subtitleLanguage, forKey: Key.subtitleLanguage)
        defaults.set(subtitleScale, forKey: Key.subtitleScale)
        defaults.set(maximumBitrate, forKey: Key.maximumBitrate)
        defaults.set(homeLayout.storedData, forKey: Key.homeLayout)
    }

    public func validated() throws -> Self {
        guard addonURLs.count <= 100,
              Set(addonURLs).count == addonURLs.count,
              ([""] + LanguageCodes.common).contains(audioLanguage),
              ([""] + LanguageCodes.common).contains(subtitleLanguage),
              Self.subtitleScales.contains(subtitleScale),
              Self.maximumBitrateOptions.contains(maximumBitrate),
              homeLayout.isValid
        else { throw SyncError.invalidData }
        for url in addonURLs {
            guard url.utf8.count <= 32_768,
                  let client = try? AddonClient(manifestURL: url), client.manifestURL == url,
                  url != AddonStore.cinemetaURL
            else { throw SyncError.invalidData }
        }
        return self
    }

    private enum CodingKeys: String, CodingKey {
        case addonURLs, audioLanguage, subtitleLanguage, subtitleScale, maximumBitrate, maximumSourceGigabytes, accent, homeLayout
    }

    /// Setups saved or synced by versions before the bitrate limit carry the size limit
    /// instead, converted as `migrateSourceSizeLimit` does.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let gigabytes = try container.decodeIfPresent(Int.self, forKey: .maximumSourceGigabytes)
        self.init(addonURLs: try container.decode([String].self, forKey: .addonURLs),
                  audioLanguage: try container.decode(String.self, forKey: .audioLanguage),
                  subtitleLanguage: try container.decode(String.self, forKey: .subtitleLanguage),
                  subtitleScale: try container.decode(Double.self, forKey: .subtitleScale),
                  maximumBitrate: try container.decodeIfPresent(Int.self, forKey: .maximumBitrate)
                      ?? (gigabytes == 0 ? 0 : Self().maximumBitrate),
                  // Missing before Home could be arranged. A layout this version can't read at
                  // all is Home's default rather than a setup that can't be opened.
                  homeLayout: (try? container.decodeIfPresent(HomeLayout.self, forKey: .homeLayout)) ?? .default)
    }

    /// Older versions on other devices require a size limit (none for no limit, else what was
    /// their default) and an accent colour to read the setup at all; both go once those
    /// versions are gone.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(addonURLs, forKey: .addonURLs)
        try container.encode(audioLanguage, forKey: .audioLanguage)
        try container.encode(subtitleLanguage, forKey: .subtitleLanguage)
        try container.encode(subtitleScale, forKey: .subtitleScale)
        try container.encode(maximumBitrate, forKey: .maximumBitrate)
        try container.encode(maximumBitrate == 0 ? 0 : 50, forKey: .maximumSourceGigabytes)
        try container.encode("white", forKey: .accent)
        try container.encode(homeLayout, forKey: .homeLayout)
    }

    public enum Field: String, Codable, CaseIterable, Sendable {
        case addonURLs, audioLanguage, subtitleLanguage, subtitleScale, maximumBitrate, homeLayout
    }

    public struct Merge: Sendable {
        public let settings: SyncedSettings
        public let conflicts: Set<Field>
    }

    /// The ordered addon list is one field: unioning lists would resurrect removals. Home's
    /// layout is one field for the same reason.
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
        choose(\.maximumBitrate, .maximumBitrate)
        choose(\.homeLayout, .homeLayout)
        return Merge(settings: result, conflicts: conflicts)
    }

    /// `self` with the fields in `categories` taken from `source`.
    func replacing(categories: Set<SyncCategory>, from source: Self) -> Self {
        var result = self
        if categories.contains(.addons) { result.addonURLs = source.addonURLs }
        if categories.contains(.playback) {
            result.audioLanguage = source.audioLanguage
            result.subtitleLanguage = source.subtitleLanguage
            result.subtitleScale = source.subtitleScale
            result.maximumBitrate = source.maximumBitrate
        }
        if categories.contains(.appearance) { result.homeLayout = source.homeLayout }
        return result
    }

    func replacing(_ fields: Set<Field>, from source: Self) -> Self {
        var result = self
        for field in fields {
            switch field {
            case .addonURLs: result.addonURLs = source.addonURLs
            case .audioLanguage: result.audioLanguage = source.audioLanguage
            case .subtitleLanguage: result.subtitleLanguage = source.subtitleLanguage
            case .subtitleScale: result.subtitleScale = source.subtitleScale
            case .maximumBitrate: result.maximumBitrate = source.maximumBitrate
            case .homeLayout: result.homeLayout = source.homeLayout
            }
        }
        return result
    }
}
