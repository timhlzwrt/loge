import Foundation

/// This device's addons and preferences as `SyncedSettings`. While an account is connected
/// its setup replaces them; each account's setup and the one from before connecting are
/// saved apart, so switching never leaves one person's setup active for another.
@MainActor
struct AccountSyncLocalSetup {
    let addons: AddonStore
    let defaults: UserDefaults

    private static let activeProfileKey = "accountSyncSettingsProfile"
    private static let beforeConnectingKey = "accountSyncLocalSetup"
    private static func profileKey(_ id: String) -> String { "accountSyncSettings.\(id)" }

    var current: SyncedSettings {
        SyncedSettings(addonURLs: addons.addons.map(\.manifestURL), defaults: defaults)
    }

    func apply(_ settings: SyncedSettings, categories: Set<SyncCategory> = Set(SyncCategory.allCases)) throws {
        let settings = try settings.validated()
        if categories.contains(.addons), addons.addons.map(\.manifestURL) != settings.addonURLs {
            try addons.replaceManifestURLs(settings.addonURLs)
            Task { await addons.refreshManifests() }
        }
        settings.writePreferences(to: defaults, categories: categories)
    }

    func rememberBeforeConnecting(_ settings: SyncedSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.beforeConnectingKey)
    }

    func forgetBeforeConnecting() {
        defaults.removeObject(forKey: Self.beforeConnectingKey)
    }

    /// Saves the active profile's setup, then switches to `profileID`'s, or back to the
    /// setup from before connecting when `profileID` is nil.
    func activate(profileID: String?) throws {
        let previous = defaults.string(forKey: Self.activeProfileKey)
        if let previous {
            defaults.set(try JSONEncoder().encode(current), forKey: Self.profileKey(previous))
        }
        guard let profileID else {
            defer { defaults.removeObject(forKey: Self.activeProfileKey) }
            if let saved = defaults.data(forKey: Self.beforeConnectingKey) {
                do { try apply(JSONDecoder().decode(SyncedSettings.self, from: saved)) }
                catch {
                    try apply(SyncedSettings())
                    throw SyncError.invalidData
                }
            } else if previous != nil {
                try apply(SyncedSettings())
            }
            return
        }
        if previous != profileID {
            let saved = defaults.data(forKey: Self.profileKey(profileID))
            try apply(saved.map { try JSONDecoder().decode(SyncedSettings.self, from: $0).validated() } ?? SyncedSettings())
        }
        defaults.set(profileID, forKey: Self.activeProfileKey)
    }
}
