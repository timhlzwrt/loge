import Foundation

/// A one-time copy of a setup that one person sends another: the addons, in their order,
/// and optionally the playback preferences. Nothing stays connected after the import.
///
/// The text is `loge-setup-1:` and base64url of deflated compact JSON. Deflate takes about
/// 40% off configured manifest URLs, which repeat their host and path pieces. The addon URLs
/// often embed accounts' keys, so the code is never logged, shown or put into an error.
public struct SetupCode: Equatable, Sendable {
    public var addonURLs: [String]
    public var preferences: Preferences?

    public struct Preferences: Codable, Equatable, Sendable {
        public var audioLanguage: String
        public var subtitleLanguage: String
        public var maximumBitrate: Int

        enum CodingKeys: String, CodingKey {
            case audioLanguage = "a", subtitleLanguage = "s", maximumBitrate = "b"
        }

        public init(audioLanguage: String, subtitleLanguage: String, maximumBitrate: Int) {
            self.audioLanguage = audioLanguage
            self.subtitleLanguage = subtitleLanguage
            self.maximumBitrate = maximumBitrate
        }

        /// This device's preferences, read as `SyncedSettings` reads them.
        public init(defaults: UserDefaults) {
            let settings = SyncedSettings(addonURLs: [], defaults: defaults)
            audioLanguage = settings.audioLanguage
            subtitleLanguage = settings.subtitleLanguage
            maximumBitrate = settings.maximumBitrate
        }

        public func write(to defaults: UserDefaults) {
            defaults.set(audioLanguage, forKey: SyncedSettings.Key.audioLanguage)
            defaults.set(subtitleLanguage, forKey: SyncedSettings.Key.subtitleLanguage)
            defaults.set(maximumBitrate, forKey: SyncedSettings.Key.maximumBitrate)
        }
    }

    public enum DecodingError: Error, Equatable {
        /// Not a complete setup code or link: cut off, mistyped, or something else.
        case malformed
        /// From a later version of loge, which this one can't read.
        case newerVersion
    }

    /// The link that opens the app with a code, for the devices that can open links.
    public static let linkPrefix = "loge://setup#"
    private static let prefix = "loge-setup-"
    private static let version = 1
    private static let maximumLength = 32_768

    /// What the app shows of the addons: their hosts, never the URLs.
    public var addonHosts: [String] { addonURLs.map { InstalledAddon(manifestURL: $0).host } }

    public init(addonURLs: [String], preferences: Preferences? = nil) {
        self.addonURLs = addonURLs
        self.preferences = preferences
    }

    /// Reads a code or a link holding one, whole or not at all.
    public init(decoding text: String) throws(DecodingError) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(Self.linkPrefix) { text.removeFirst(Self.linkPrefix.count) }
        guard text.utf8.count <= Self.maximumLength, text.hasPrefix(Self.prefix),
              let separator = text.firstIndex(of: ":"),
              let version = Int(text[text.index(text.startIndex, offsetBy: Self.prefix.count)..<separator])
        else { throw .malformed }
        guard version == Self.version else { throw version > Self.version ? .newerVersion : .malformed }
        guard let compressed = Data(base64URLEncoded: String(text[text.index(after: separator)...])),
              let json = try? (compressed as NSData).decompressed(using: .zlib) as Data,
              let payload = try? JSONDecoder().decode(Payload.self, from: json),
              !payload.a.isEmpty, (try? SyncedSettings(addonURLs: payload.a).validated()) != nil,
              payload.p.map(Self.isValid) ?? true
        else { throw .malformed }
        self.init(addonURLs: payload.a, preferences: payload.p)
    }

    public func encoded() throws -> String {
        let json = try JSONEncoder().encode(Payload(a: addonURLs, p: preferences))
        let compressed = try (json as NSData).compressed(using: .zlib) as Data
        return Self.prefix + String(Self.version) + ":" + compressed.base64URLEncodedString()
    }

    /// One-letter keys keep the code short; it's typed into a TV with a phone at worst.
    private struct Payload: Codable {
        let a: [String]
        let p: Preferences?
    }

    private static func isValid(_ preferences: Preferences) -> Bool {
        ([""] + LanguageCodes.common).contains(preferences.audioLanguage)
            && ([""] + LanguageCodes.common).contains(preferences.subtitleLanguage)
            && SyncedSettings.maximumBitrateOptions.contains(preferences.maximumBitrate)
    }
}

extension AddonStore {
    public struct SetupImport: Sendable {
        /// Hosts only, like everything else the app shows of an addon.
        public var added: [String] = []
        public var failed: [(host: String, error: InstallError)] = []
        /// The addons are now the code's, in its order.
        public var replaced = false
        /// Replacing kept the addons already here, because not all of the new ones installed.
        public var keptExisting = false
    }

    /// Installs the code's addons through `install`, so each manifest is fetched and checked
    /// as when adding one by hand. Adding skips addons already installed (the same manifest
    /// URL). Replacing removes the others only once every addon in the code installed, and
    /// then takes the code's order.
    public func importSetup(_ code: SetupCode, replacing: Bool) async -> SetupImport {
        var result = SetupImport()
        for url in code.addonURLs where !addons.contains(where: { $0.manifestURL == url }) {
            do throws(InstallError) {
                result.added.append(try await install(manifestURL: url).host)
            } catch InstallError.alreadyInstalled {
                continue
            } catch {
                result.failed.append((InstalledAddon(manifestURL: url).host, error))
            }
        }
        guard replacing else { return result }
        guard result.failed.isEmpty else {
            result.keptExisting = true
            return result
        }
        do {
            try replaceManifestURLs(code.addonURLs)
            result.replaced = true
        } catch {
            // The code's URLs were validated when it was read, so this means a bug, not bad input.
            assertionFailure("A decoded setup code's addons failed validation")
            result.keptExisting = true
        }
        return result
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
