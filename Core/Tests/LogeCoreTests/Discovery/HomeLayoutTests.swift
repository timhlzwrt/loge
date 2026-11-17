import Foundation
import Testing
@testable import LogeCore

struct HomeLayoutTests {
    static let secretURL = "https://addon.example/synthetic-credential/manifest.json"
    let addon = InstalledAddon(manifestURL: secretURL, manifest: AddonManifest(
        id: "org.example.lists", version: "1.0.0", name: "Example Lists", resources: [.init(name: "catalog")],
        types: ["movie"], catalogs: [
            .init(type: "movie", id: "popular", name: "Popular"),
            .init(type: "movie", id: "search", name: "Search", extra: [.init(name: "search", isRequired: true)]),
        ]))

    var catalog: HomeLayout.Shelf { .catalog(.init(addonID: "org.example.lists", type: "movie", catalogID: "popular")) }

    @Test func defaultIsHomeAsItWas() {
        let rows = HomeLayout.default.rows(addons: [])
        let feeds = DiscoveryCatalogs.home.map(HomeLayout.Row.catalog)
        #expect(rows == [.continueWatching, .watchLater, .recommended] + feeds.prefix(3) + [.genres] + feeds.dropFirst(3))
        #expect(Set(HomeLayout.default.entries.map(\.shelf)).count == HomeLayout.default.entries.count)
    }

    @Test func builtInsMissingFromASavedLayoutAreAppended() throws {
        let json = #"{"shelves":[{"kind":"genres"},{"kind":"watchLater","hidden":true}]}"#
        let layout = try JSONDecoder().decode(HomeLayout.self, from: Data(json.utf8))
        #expect(layout.entries.prefix(2).map(\.shelf) == [.genres, .watchLater])
        #expect(layout.entries[1].isHidden)
        #expect(Set(layout.entries.map(\.shelf)) == Set(HomeLayout.default.entries.map(\.shelf)))
        #expect(layout.rows(addons: []).first == .genres)
    }

    @Test func unknownShelvesAreSkippedAndUnreadableLayoutsAreTheDefault() throws {
        let json = #"{"shelves":[{"kind":"trending","id":"x"},{"kind":"recommended"},{"kind":"feed"}]}"#
        let layout = try JSONDecoder().decode(HomeLayout.self, from: Data(json.utf8))
        #expect(layout.entries.first?.shelf == .recommended)
        #expect(layout.entries.count == HomeLayout.default.entries.count)
        #expect(HomeLayout(storedData: Data("[1]".utf8)) == .default)
        #expect(HomeLayout(storedData: nil) == .default)
    }

    @Test func addonShelvesWithoutTheirAddonAreSkippedButKept() {
        var layout = HomeLayout.default
        layout.add(CatalogSource(manifestURL: Self.secretURL, catalog: addon.manifest!.catalogs[0]), of: addon)
        #expect(layout.rows(addons: [addon]).catalogs.last?.manifestURL == Self.secretURL)
        #expect(layout.rows(addons: []) == HomeLayout.default.rows(addons: []))
        #expect(layout.entries.last?.shelf == catalog)
        let notLoaded = InstalledAddon(manifestURL: Self.secretURL, manifest: nil)
        #expect(layout.rows(addons: [notLoaded]) == HomeLayout.default.rows(addons: []))
        // Another configuration of the same addon, without this catalog, comes first.
        var otherManifest = addon.manifest!; otherManifest.catalogs = []
        let other = InstalledAddon(manifestURL: "https://addon.example/other/manifest.json", manifest: otherManifest)
        #expect(layout.rows(addons: [other, addon]).catalogs.last?.manifestURL == Self.secretURL)
    }

    @Test func onlyBrowsableCatalogsNotYetAddedCanBeAdded() {
        var layout = HomeLayout.default
        let addable = layout.addableCatalogs(of: addon)
        #expect(addable.map(\.catalog.id) == ["popular"])
        layout.add(addable[0], of: addon)
        layout.add(addable[0], of: addon)
        #expect(layout.addableCatalogs(of: addon).isEmpty)
        #expect(layout.entries.filter { $0.shelf == catalog }.count == 1)
    }

    @Test func moveHideAndRemove() {
        var layout = HomeLayout.default
        layout.add(layout.addableCatalogs(of: addon)[0], of: addon)
        layout.move(fromOffsets: [0], toOffset: 3)
        #expect(layout.entries.prefix(3).map(\.shelf) == [.watchLater, .recommended, .continueWatching])
        layout.setHidden(true, for: .watchLater)
        #expect(layout.rows(addons: []).first == .recommended)
        layout.remove(.genres)
        #expect(layout.entries.contains { $0.shelf == .genres })
        layout.remove(catalog)
        #expect(!layout.entries.contains { $0.shelf == catalog })
        #expect(layout.entries.count == HomeLayout.default.entries.count)
    }

    @Test func storedLayoutNamesAddonsWithoutTheirURL() throws {
        var layout = HomeLayout.default
        layout.add(layout.addableCatalogs(of: addon)[0], of: addon)
        layout.setHidden(true, for: .recommended)
        let text = String(decoding: layout.storedData, as: UTF8.self)
        #expect(!text.contains("synthetic-credential") && !text.contains("://"))
        #expect(text.contains("org.example.lists"))
        #expect(HomeLayout(storedData: layout.storedData) == layout)
    }

    @Test func syncedSettingsCarryTheLayoutAndReadOlderSetups() throws {
        var layout = HomeLayout.default
        layout.add(layout.addableCatalogs(of: addon)[0], of: addon)
        layout.move(fromOffsets: [6], toOffset: 0)
        let settings = SyncedSettings(homeLayout: layout)
        #expect(try JSONDecoder().decode(SyncedSettings.self, from: JSONEncoder().encode(settings)) == settings)
        #expect(try settings.validated() == settings)

        let older = #"{"addonURLs":[],"audioLanguage":"en","subtitleLanguage":"","subtitleScale":1,"maximumSourceGigabytes":50,"accent":"white"}"#
        #expect(try JSONDecoder().decode(SyncedSettings.self, from: Data(older.utf8)).homeLayout == .default)
        let unreadable = older.dropLast() + #","homeLayout":"later"}"#
        #expect(try JSONDecoder().decode(SyncedSettings.self, from: Data(unreadable.utf8)).homeLayout == .default)

        // The layout is appearance: only that category carries it, and conflicting edits need a choice.
        #expect(SyncedSettings().replacing(categories: [.addons, .playback], from: settings).homeLayout == .default)
        #expect(SyncedSettings().replacing(categories: [.appearance], from: settings).homeLayout == layout)
        var other = HomeLayout.default; other.setHidden(true, for: .genres)
        let merge = SyncedSettings.merged(base: SyncedSettings(), local: settings, remote: SyncedSettings(homeLayout: other))
        #expect(merge.conflicts == [.homeLayout])
        let independent = SyncedSettings.merged(base: SyncedSettings(), local: SyncedSettings(),
                                                remote: SyncedSettings(homeLayout: other))
        #expect(independent.conflicts.isEmpty && independent.settings.homeLayout == other)
    }

    @MainActor @Test func preferencesWriteTheLayoutToDefaults() {
        let defaults = UserDefaults(suiteName: "HomeLayoutTests-\(UUID().uuidString)")!
        var layout = HomeLayout.default; layout.setHidden(true, for: .genres)
        SyncedSettings(homeLayout: layout).writePreferences(to: defaults)
        #expect(SyncedSettings(addonURLs: [], defaults: defaults).homeLayout == layout)
    }
}
