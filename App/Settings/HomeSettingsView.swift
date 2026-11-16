import LogeCore
import SwiftUI

/// Which shelves Home shows, and in what order. Saved in `UserDefaults`, from where sync
/// carries it with the appearance settings.
struct HomeSettingsView: View {
    @Environment(AddonStore.self) private var store
    @AppStorage(HomeLayout.storageKey) private var storedLayout: Data?
    @State private var confirmsReset = false

    private var layout: HomeLayout { HomeLayout(storedData: storedLayout) }

    var body: some View {
        let layout = layout
        SettingsPage("Home") {
            Section {
                ForEach(layout.entries) { entry in
                    let label = ShelfLabel(name: name(of: entry.shelf), origin: origin(of: entry.shelf))
                    #if os(tvOS)
                    // Plain rows can't take focus on tvOS, and lists there can't be dragged, so the row
                    // opens its actions, as on the addons page.
                    Menu { actions(for: entry) } label: {
                        HStack {
                            label
                            Text(entry.isHidden ? "Hidden" : "Shown").foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(name(of: entry.shelf))
                    #else
                    Toggle(isOn: Binding(get: { !entry.isHidden },
                                         set: { shown in edit { $0.setHidden(!shown, for: entry.shelf) } })) {
                        label
                    }
                    #if os(macOS)
                    .contextMenu { actions(for: entry) }
                    #endif
                    .deleteDisabled(!entry.shelf.isRemovable)
                    #endif
                }
                #if !os(tvOS)
                .onMove { source, destination in edit { $0.move(fromOffsets: source, toOffset: destination) } }
                .onDelete { offsets in
                    let shelves = offsets.map { layout.entries[$0].shelf }
                    edit { layout in shelves.forEach { layout.remove($0) } }
                }
                #endif
            } header: {
                SettingsHeader("Shelves")
            } footer: {
                Text("Shelves from an addon that isn't installed on this device stay in the list for your other devices.")
            }

            Section {
                NavigationLink("Add Shelf") { AddShelfView() }
                Button("Reset to Default", role: .destructive) { confirmsReset = true }
                    .disabled(layout == .default)
                    .confirmationDialog("Reset Home?", isPresented: $confirmsReset, titleVisibility: .visible) {
                        Button("Reset", role: .destructive) { storedLayout = HomeLayout.default.storedData }
                    } message: {
                        Text("Every built-in shelf is shown in its original order, and addon shelves are removed.")
                    }
            }
        }
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }

    #if !os(iOS)
    /// Dragging rows in the Mac's grouped form is easy to miss, so moving is here too, as on
    /// the addons page. iPhone and iPad drag and swipe instead.
    @ViewBuilder
    private func actions(for entry: HomeLayout.Entry) -> some View {
        #if os(tvOS)
        Button(entry.isHidden ? "Show" : "Hide", systemImage: entry.isHidden ? "eye" : "eye.slash") {
            edit { $0.setHidden(!entry.isHidden, for: entry.shelf) }
        }
        #endif
        if let index = layout.entries.firstIndex(of: entry) {
            if index > 0 {
                Button("Move Up", systemImage: "arrow.up") {
                    edit { $0.move(fromOffsets: [index], toOffset: index - 1) }
                }
            }
            if index < layout.entries.count - 1 {
                Button("Move Down", systemImage: "arrow.down") {
                    edit { $0.move(fromOffsets: [index], toOffset: index + 2) }
                }
            }
        }
        if entry.shelf.isRemovable {
            Button("Remove", systemImage: "trash", role: .destructive) {
                edit { $0.remove(entry.shelf) }
            }
        }
    }
    #endif

    private func edit(_ change: (inout HomeLayout) -> Void) {
        var layout = layout
        change(&layout)
        storedLayout = layout.storedData
    }

    private func name(of shelf: HomeLayout.Shelf) -> String {
        switch shelf {
        case .genres: "Genres"
        case .continueWatching: "Continue Watching"
        case .watchLater: "Watch Later"
        case .recommended: "Recommended"
        case .feed(let key): layout.source(for: shelf, addons: store.addons)?.title ?? key
        case .catalog(let catalog):
            layout.source(for: shelf, addons: store.addons)?.title ?? "\(catalog.catalogID) (\(catalog.type))"
        }
    }

    /// Never the addon's URL, which can carry the user's keys.
    private func origin(of shelf: HomeLayout.Shelf) -> String {
        switch shelf {
        case .continueWatching, .watchLater, .recommended: "Library"
        case .genres: "Built in"
        case .feed, .catalog:
            if layout.source(for: shelf, addons: store.addons) == nil {
                "Not available on this device"
            } else if case .catalog(let catalog) = shelf, let addon = HomeLayout.addon(for: catalog, in: store.addons) {
                addon.displayName
            } else {
                "Built in"
            }
        }
    }
}

private struct ShelfLabel: View {
    let name: String
    let origin: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
            Text(origin)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // A tvOS button centres its label otherwise.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The catalogs of installed addons that aren't on Home yet, by addon.
private struct AddShelfView: View {
    @Environment(AddonStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeLayout.storageKey) private var storedLayout: Data?

    var body: some View {
        let layout = HomeLayout(storedData: storedLayout)
        let addons = store.addons.filter { !layout.addableCatalogs(of: $0).isEmpty }
        SettingsPage("Add Shelf") {
            if addons.isEmpty {
                Section {
                    Text(store.addons.isEmpty
                         ? "Install an addon that offers catalogs, and its catalogs can be added to Home here."
                         : "Your addons have no other catalogs that can be a shelf. Catalogs that only list search results aren't offered.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(addons) { addon in
                Section {
                    ForEach(layout.addableCatalogs(of: addon)) { source in
                        Button(source.title) {
                            var layout = layout
                            layout.add(source, of: addon)
                            storedLayout = layout.storedData
                            // Back to the list, where the new shelf is last.
                            dismiss()
                        }
                    }
                } header: {
                    SettingsHeader(addon.displayName)
                }
            }
        }
    }
}
