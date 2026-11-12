import LogeCore
import SwiftUI

/// Opens Settings from Home on iPhone, the one platform without a tab for it.
struct SettingsRoute: Hashable {}

/// A short index of settings pages, each row showing where that setting stands, so the
/// addon form and account keys don't make one long scroll.
struct SettingsView: View {
    @Environment(AddonStore.self) private var store
    @Environment(TraktAccount.self) private var trakt
    @Environment(TMDBAccount.self) private var tmdb
    @Environment(AccountSync.self) private var sync
    @AppStorage(Accent.storageKey) private var accent = Accent.white

    var body: some View {
        SettingsPage("Settings") { sections }
    }

    @ViewBuilder private var sections: some View {
        Section {
            NavigationLink {
                SyncSettingsView()
            } label: {
                LabeledContent("Sync", value: syncSummary)
            }
        }
        Section {
            NavigationLink {
                AddonsSettingsView()
            } label: {
                LabeledContent("Addons", value: addonSummary)
            }
            NavigationLink {
                SettingsPage("Trakt") { TraktSection() }
            } label: {
                LabeledContent("Trakt", value: traktSummary)
            }
            NavigationLink {
                SettingsPage("TMDB") { TMDBSection() }
            } label: {
                LabeledContent("TMDB", value: tmdb.isConfigured ? "Connected" : "Off")
            }
        }

        PlaybackSettingsSection()

        Section {
            NavigationLink {
                SettingsPage("Accent Color") { AccentSettingsSection() }
            } label: {
                LabeledContent("Accent Color", value: accent.name)
            }
        }

        AboutSection()
    }

    private var addonSummary: String {
        switch store.addons.count {
        case 0: "None"
        case 1: "1 installed"
        case let count: "\(count) installed"
        }
    }

    /// States that hold up syncing come before the account name, so they show without opening the page.
    private var syncSummary: String {
        guard sync.isConnected else { return "Off" }
        if sync.needsChoice { return "Needs review" }
        if sync.status == .failed { return "Couldn't sync" }
        return sync.displayName ?? "Connected"
    }

    private var traktSummary: String {
        switch trakt.state {
        case .signedIn(let username): trakt.isPaused ? "Paused" : username
        case .awaitingApproval: "Signing in"
        case .signedOut: "Off"
        }
    }
}

/// One settings page: its sections on the app's canvas.
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
            List { content }
            #endif
        }
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            .navigationTitle(title)
            #endif
            .background(Color.canvas)
    }
}

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

    var body: some View {
        SettingsPage("Addons") {
            Section {
                Text("Movies, series, search and IMDb ratings are built in. Add a playback addon to watch.")
                    .foregroundStyle(.secondary)
            }
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
                    Group {
                        #if os(tvOS)
                        // Plain rows can't take focus on tvOS, so the row opens its actions instead.
                        Menu { actions(for: addon) } label: { row }
                        #else
                        row.contextMenu { actions(for: addon) }
                        #endif
                    }
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
                }
                #if !os(tvOS)
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    offsets.map { store.addons[$0].id }.forEach(store.remove)
                }
                #endif
            } header: {
                SettingsHeader("Your addons")
            } footer: {
                if store.addons.count > 1 {
                    Text("Addons higher in the list are asked first.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextField("Manifest URL", text: $manifestURL)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit(install)
                    .onChange(of: manifestURL) { installError = nil }
                // The keyboard's Done already installs on tvOS, where a disabled Install row reads as
                // stray grey text; it shows once there's a URL to install.
                #if os(tvOS)
                let showsInstall = !isManifestURLEmpty || isInstalling
                #else
                let showsInstall = true
                #endif
                if showsInstall {
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
                if let installError {
                    Text(message(for: installError))
                        .foregroundStyle(.red)
                }
            } header: {
                SettingsHeader("Add addon")
            } footer: {
                #if os(tvOS)
                Text("Paste the URL with the Remote keyboard on your iPhone, or add the addon on a device connected to Sync.")
                #endif
            }
        }
        #if os(iOS)
        .toolbar {
            if !store.addons.isEmpty { EditButton() }
        }
        #endif
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

    private func message(for error: AddonStore.InstallError) -> String {
        switch error {
        case .invalidURL: "That isn't a manifest URL. It should end in /manifest.json."
        case .alreadyInstalled: "This addon is already installed."
        case .unreachable(let reason): "Couldn't reach the addon. \(reason)"
        case .invalidManifest: "The URL responded, but not with an addon manifest."
        }
    }
}

private struct AddonRow: View {
    let addon: InstalledAddon
    let isUnreachable: Bool
    #if os(tvOS)
    /// The row turns white under focus, where the orange warning disappears.
    @Environment(\.isFocused) private var isFocused
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(addon.displayName)
                    .font(.headline)
                if let version = addon.manifest?.version {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let description = addon.manifest?.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
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
            } else if addon.manifest == nil {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Full-width rows, so focused rows on tvOS line up instead of hugging their text.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the addon answers, then its host: "Streams · Subtitles · example.com".
    private var caption: String {
        let resources = Set(addon.manifest?.resources.map(\.name) ?? [])
        let provides = [("stream", "Streams"), ("subtitles", "Subtitles"), ("catalog", "Catalogs"), ("meta", "Details")]
            .filter { resources.contains($0.0) }
            .map(\.1)
        return (provides + [addon.host]).joined(separator: " · ")
    }
}
