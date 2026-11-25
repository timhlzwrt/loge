import LogeCore
import SwiftUI

/// Settings as sentences, or as the usual list of pages for those who prefer it.
struct SettingsView: View {
    static let showsListKey = "settingsShowsList"
    @AppStorage(showsListKey) private var showsList = false

    var body: some View {
        if showsList { SettingsListView() } else { SettingsSentencesView() }
    }
}

/// A short index of settings pages, each row showing where that setting stands, so the
/// addon form and account keys don't make one long scroll.
private struct SettingsListView: View {
    @Environment(AddonStore.self) private var store
    @Environment(TMDBAccount.self) private var tmdb
    @Environment(AccountSync.self) private var sync
    @AppStorage(HomeLayout.storageKey) private var homeLayout: Data?
    @AppStorage(SettingsView.showsListKey) private var showsList = false
    @State private var isConnectingTMDB = false

    var body: some View {
        SettingsPage("Settings") {
            Section {
                NavigationLink {
                    AddonsSettingsView()
                } label: {
                    row("Addons", value: addonSummary, isWarning: store.addons.isEmpty)
                }
                if tmdb.isConfigured || tmdb.storageError != nil {
                    NavigationLink {
                        SettingsPage("TMDB") { TMDBSection() }
                    } label: {
                        row("Cast & Recommendations", value: tmdb.storageError == nil ? "On" : "Unavailable",
                            isWarning: tmdb.storageError != nil)
                    }
                } else {
                    // Off, the TMDB page would only say so; this goes straight to entering a token.
                    Button { isConnectingTMDB = true } label: {
                        row("Cast & Recommendations", value: "Off")
                    }
                    .foregroundStyle(.primary)
                }
                NavigationLink {
                    HomeSettingsView()
                } label: {
                    row("Home Shelves", value: HomeLayout(storedData: homeLayout) == .default ? "Default" : "Customized")
                }
                NavigationLink {
                    SyncSettingsView()
                } label: {
                    row("Sync", value: sync.problem ?? (sync.isConnected ? sync.displayName ?? "On" : "Off"),
                        isWarning: sync.problem != nil)
                }
            }

            PlaybackSettingsSection()

            Section {
                NavigationLink {
                    SettingsPage("About") { AboutSection() }
                } label: {
                    row("About loge", value: AboutSection.version)
                }
                Button("Show as Sentences") { showsList = false }
            }
        }
        .sheet(isPresented: $isConnectingTMDB) { TMDBSetupView() }
    }

    private func row(_ title: String, value: String, isWarning: Bool = false) -> some View {
        LabeledContent(title) {
            Text(value).foregroundStyle(isWarning ? .orange : .secondary)
        }
    }

    /// The first addon's name says whether the right one is installed, where a count wouldn't.
    private var addonSummary: String {
        switch store.addons.count {
        case 0: "None"
        case 1: store.addons[0].displayName
        case let count: "\(store.addons[0].displayName) +\(count - 1)"
        }
    }
}

extension AddonStore {
    /// Addons that answer stream requests, and those not loaded yet, which may.
    var streamAddons: [InstalledAddon] {
        addons.filter { $0.manifest?.resources.contains { $0.name == AddonResource.stream.rawValue } ?? true }
    }
}

extension AccountSync {
    /// What holds up syncing, shown on Settings itself so it's seen without opening the page.
    var problem: String? {
        guard isConnected else { return nil }
        if needsChoice { return "Needs review" }
        if status == .failed { return "Couldn't sync" }
        return nil
    }
}

/// One settings page: its sections on the app's canvas. iPhone and iPad draw them as
/// translucent groups of tall rows under small grey labels.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Group {
            #if os(macOS)
            Form { content }.formStyle(.grouped)
            #elseif os(tvOS)
            List {
                // Lined up with the rows, as on My Lists; the system's title is centred and grey.
                // The padding clears the tab menu.
                Text(title)
                    .font(.system(size: 57, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 60)
                content
            }
            #else
            List { content.listRowBackground(Color.white.opacity(0.07)) }
                .listStyle(.insetGrouped)
                .environment(\.defaultMinListRowHeight, 52)
                .toggleStyle(SettingsToggleStyle())
            #endif
        }
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            .navigationTitle(title)
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .background(Color.canvas)
    }
}

#if os(iOS)
/// A switch that reads with the white accent: the system's draws a white knob on a white track.
/// On, the track is white and the knob dark; off, a translucent track and a white knob.
struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                Capsule()
                    .fill(configuration.isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.18)))
                    .frame(width: 51, height: 31)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? Color(white: 0.07) : .white)
                            .padding(2)
                    }
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}
#endif

/// A section heading. The TV's system headers are small and grey, hard to read as headings
/// from across the room, so there they take the size of the app's other section titles.
struct SettingsHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            #if os(tvOS)
            .font(.sectionTitle)
            .foregroundStyle(.white)
            .textCase(nil)
            .padding(.top, 24)
            #elseif os(iOS)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.45))
            .textCase(nil)
            #endif
    }
}

struct AddonsSettingsView: View {
    @Environment(AddonStore.self) private var store
    @Environment(AccountSync.self) private var sync
    @State private var manifestURL = ""
    @State private var isInstalling = false
    @State private var installError: AddonStore.InstallError?
    @State private var removing: InstalledAddon?
    @State private var renaming: InstalledAddon?
    @State private var newName = ""
    @AppStorage(SyncedSettings.Key.combinesAddonSources) private var combinesAddonSources = false
    #if !os(tvOS)
    @State private var isSharing = false
    #endif

    var body: some View {
        SettingsPage("Addons") {
            Section {
                if store.addons.isEmpty {
                    #if os(tvOS)
                    // Typing a configured URL with the remote is the slow way; Sync brings it from a phone.
                    NavigationLink {
                        SyncSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No playback addons yet")
                            Text(sync.isConnected
                                 ? "Addons added on your other devices appear here."
                                 : "Connect Sync to bring your addons over from your iPhone.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    #else
                    Text("No playback addons yet")
                        .foregroundStyle(.secondary)
                    #endif
                }
                ForEach(store.addons) { addon in
                    let row = AddonRow(addon: addon, isUnreachable: store.unreachable.contains(addon.id))
                    #if os(tvOS)
                    // Plain rows can't take focus on tvOS, so the row opens its actions instead.
                    Menu { actions(for: addon) } label: { row }
                        .accessibilityLabel(addon.displayName)
                    #else
                    row.contextMenu { actions(for: addon) }
                        // On the row, so on iPhone and iPad the dialog points at the addon it removes.
                        .confirmationDialog(
                            "Remove \(addon.displayName)?",
                            isPresented: Binding(get: { removing?.id == addon.id }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible
                        ) {
                            Button("Remove", role: .destructive) { store.remove(addon.id) }
                        } message: {
                            Text("Adding it back means entering its manifest URL again.")
                        }
                    #endif
                }
                #if !os(tvOS)
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    offsets.map { store.addons[$0].id }.forEach(store.remove)
                }
                #endif
            } header: {
                SettingsHeader("Playback, asked in this order")
            }

            // Only a choice with more than one addon to take sources from.
            if store.addons.filter({ $0.manifest?.resources.contains { $0.name == AddonResource.stream.rawValue } == true }).count > 1 {
                Section {
                    Toggle("Combine sources from all addons", isOn: $combinesAddonSources)
                } footer: {
                    Text(combinesAddonSources
                         ? "On: the sources list shows every addon's sources together."
                         : "Off: sources come from one addon at a time, chosen in the sources list.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                #if os(tvOS)
                manifestField
                // The keyboard's Done already installs on tvOS, where a disabled Install row reads as
                // stray grey text; it shows once there's a URL to install.
                if !isManifestURLEmpty || isInstalling {
                    installButton
                }
                #else
                HStack {
                    manifestField
                    installButton
                        .fontWeight(.semibold)
                }
                #endif
                if let installError {
                    Text(Self.message(for: installError))
                        .foregroundStyle(.red)
                }
            } header: {
                SettingsHeader("Add an addon")
            } footer: {
                #if os(tvOS)
                Text("Paste the URL with the Remote keyboard on your iPhone, or add the addon on a device connected to Sync.")
                #endif
            }

            Section {
                AddonLabel(name: "Cinemeta", detail: "Movies, series, search and IMDb ratings")
            } header: {
                SettingsHeader("Built in")
            }

            Section {
                #if !os(tvOS)
                Button("Share Setup…") { isSharing = true }
                    .disabled(store.addons.isEmpty)
                #endif
                NavigationLink("Import Setup…") { ImportSetupView() }
            } footer: {
                #if os(tvOS)
                Text("Add the addons someone sent you. Nothing stays connected afterwards.")
                #else
                Text("Send someone a copy of your addons, or add the ones they sent you. Nothing stays connected afterwards.")
                #endif
            }
        }
        #if !os(tvOS)
        .sheet(isPresented: $isSharing) {
            NavigationStack { ShareSetupView() }
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
                #endif
        }
        #endif
        #if os(tvOS)
        .fullScreenCover(item: $removing) { addon in
            AddonRemovalConfirmation(host: addon.host) { store.remove(addon.id) }
        }
        .fullScreenCover(item: $renaming) { addon in
            AddonRenameSheet(name: addon.displayName) { store.rename(addon.id, to: $0) }
        }
        #else
        .alert("Rename Addon", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               presenting: renaming) { addon in
            TextField("Name", text: $newName)
            Button("Save") { store.rename(addon.id, to: newName) }
            Button("Cancel", role: .cancel) {}
        } message: { addon in
            Text("Leave it empty to use \(addon.manifest?.name ?? addon.host).")
        }
        #endif
        #if os(iOS)
        .toolbar {
            if !store.addons.isEmpty { EditButton() }
        }
        #endif
    }

    private var manifestField: some View {
        TextField("Manifest URL", text: $manifestURL)
            .autocorrectionDisabled()
            #if !os(macOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .onSubmit(install)
            .onChange(of: manifestURL) { installError = nil }
    }

    private var installButton: some View {
        Button(action: install) {
            if isInstalling {
                ProgressView()
            } else {
                Text("Install")
            }
        }
        .accessibilityLabel(isInstalling ? "Installing" : "Install")
        .disabled(isManifestURLEmpty || isInstalling)
    }

    private var isManifestURLEmpty: Bool {
        manifestURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private func actions(for addon: InstalledAddon) -> some View {
        // tvOS lists have no drag-to-reorder, and dragging rows in the Mac's grouped form is easy
        // to miss, so moving lives in the row's menu there too.
        #if !os(iOS)
        if let index = store.addons.firstIndex(of: addon) {
            Button("Move Up", systemImage: "arrow.up") {
                store.move(fromOffsets: [index], toOffset: index - 1)
            }
            .disabled(index == 0)
            Button("Move Down", systemImage: "arrow.down") {
                store.move(fromOffsets: [index], toOffset: index + 2)
            }
            .disabled(index == store.addons.count - 1)
        }
        #endif
        Button("Rename…", systemImage: "pencil") {
            newName = addon.displayName
            renaming = addon
        }
        Button("Remove", systemImage: "trash", role: .destructive) {
            removing = addon
        }
    }

    private func install() {
        // Return in the empty field submits too; that is not a wrong URL, just no URL yet.
        guard !isInstalling, !isManifestURLEmpty else { return }
        isInstalling = true
        installError = nil
        Task {
            defer { isInstalling = false }
            do throws(AddonStore.InstallError) {
                try await store.install(manifestURL: manifestURL)
                manifestURL = ""
            } catch {
                installError = error
            }
        }
    }

    static func message(for error: AddonStore.InstallError) -> String {
        switch error {
        case .invalidURL: "That isn't a manifest URL. It should end in /manifest.json."
        case .alreadyInstalled: "This addon is already installed."
        case .unreachable(let reason): "Couldn't reach the addon. \(reason)"
        case .invalidManifest: "The URL responded, but not with an addon manifest."
        }
    }
}

#if os(tvOS)
/// A name for an addon, in the same plain card as removing one.
private struct AddonRenameSheet: View {
    @State var name: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Rename addon").font(.title2.bold())
            TextField("Name", text: $name)
                .onSubmit {
                    save(name)
                    dismiss()
                }
            Text("Leave it empty to use the addon's own name.")
                .foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button("Save") {
                    save(name)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
            }
        }
        .padding(40)
        .frame(width: 640, alignment: .leading)
        .background(Color.canvas, in: .rect(cornerRadius: Metrics.cardRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationBackground(.black.opacity(0.7))
        .onExitCommand { dismiss() }
    }
}

/// Native tvOS alerts render their focused Cancel label white on the app's white accent.
private struct AddonRemovalConfirmation: View {
    let host: String
    let remove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var cancelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Remove addon?").font(.title2.bold())
            Text("To add this addon again, you'll need its manifest URL. Host: \(host).")
                .foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .focused($cancelFocused)
                Button("Remove", role: .destructive) {
                    remove()
                    dismiss()
                }
                .buttonStyle(.glass)
                .tint(.red)
            }
        }
        .padding(40)
        .frame(width: 640, alignment: .leading)
        .background(Color.canvas, in: .rect(cornerRadius: Metrics.cardRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationBackground(.black.opacity(0.7))
        .defaultFocus($cancelFocused, true)
        .onExitCommand { dismiss() }
    }
}
#endif

private struct AddonRow: View {
    let addon: InstalledAddon
    let isUnreachable: Bool
    #if os(tvOS)
    /// The row turns white under focus, where the orange warning disappears.
    @Environment(\.isFocused) private var isFocused
    #endif

    var body: some View {
        AddonLabel(name: addon.displayName, detail: detail) {
            if isUnreachable {
                Label(addon.manifest == nil
                      ? "Couldn't reach \(addon.host)."
                      : "Couldn't reach \(addon.host). Using the last known version.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    #if os(tvOS)
                    .foregroundStyle(isFocused ? .black : .orange)
                    #else
                    .foregroundStyle(.orange)
                    #endif
            }
        }
    }

    /// Its host, then what it answers: "example.com · Streams · Subtitles".
    private var detail: String {
        guard addon.manifest != nil else { return "\(addon.host) · Loading…" }
        let resources = Set(addon.manifest?.resources.map(\.name) ?? [])
        let provides = [(AddonResource.stream, "Streams"), (.subtitles, "Subtitles"), (.catalog, "Catalogs"), (.meta, "Details")]
            .filter { resources.contains($0.0.rawValue) }
            .map(\.1)
        return ([addon.host] + provides).joined(separator: " · ")
    }
}

/// An addon as the list shows it: its initial on a tile, its name, and a line about it.
private struct AddonLabel<Note: View>: View {
    let name: String
    let detail: String
    @ViewBuilder var note: Note

    var body: some View {
        HStack(spacing: 12) {
            Text(name.first.map(String.init) ?? "")
                .font(.subheadline.weight(.bold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.14), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                note
            }
        }
        // A tvOS button centres wrapped lines, which left a long line off the row's edge.
        .multilineTextAlignment(.leading)
        // Full-width rows, so focused rows on tvOS line up instead of hugging their text.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AddonLabel where Note == EmptyView {
    init(name: String, detail: String) {
        self.init(name: name, detail: detail) { EmptyView() }
    }
}
