import LogeCore
import SwiftUI

/// A short index of settings pages, each row showing where that setting stands, so the
/// addon form and account keys don't make one long scroll.
struct SettingsView: View {
    @Environment(AddonStore.self) private var store
    @Environment(TraktAccount.self) private var trakt
    @Environment(TMDBAccount.self) private var tmdb
    @AppStorage(Accent.storageKey) private var accent = Accent.white

    var body: some View {
        List {
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
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.canvas)
        .navigationTitle("Settings")
    }

    private var addonSummary: String {
        switch store.addons.count {
        case 0: "None"
        case 1: "1 installed"
        case let count: "\(count) installed"
        }
    }

    private var traktSummary: String {
        switch trakt.state {
        case .signedIn(let username): username
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
        List { content }
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(Color.canvas)
            .navigationTitle(title)
    }
}

struct AddonsSettingsView: View {
    @Environment(AddonStore.self) private var store
    @State private var manifestURL = ""
    @State private var isInstalling = false
    @State private var installError: AddonStore.InstallError?

    var body: some View {
        List {
            Section {
                Text("Movies, series, search and IMDb ratings are built in. Add a playback addon to watch.")
                    .foregroundStyle(.secondary)
            }
            Section {
                if store.addons.isEmpty {
                    Text("No playback addons yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.addons) { addon in
                    let row = AddonRow(addon: addon, isUnreachable: store.unreachable.contains(addon.id))
                    #if os(tvOS)
                    // Plain rows can't take focus on tvOS, so the row opens its actions instead.
                    Menu { actions(for: addon) } label: { row }
                    #else
                    row.contextMenu { actions(for: addon) }
                    #endif
                }
                #if !os(tvOS)
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    offsets.map { store.addons[$0].id }.forEach(store.remove)
                }
                #endif
            } header: {
                Text("Your addons")
            } footer: {
                Text("Addons higher in the list are asked first.")
                    .foregroundStyle(.secondary)
            }

            Section("Add addon") {
                TextField("Manifest URL", text: $manifestURL)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit(install)
                    .onChange(of: manifestURL) { installError = nil }
                Button(action: install) {
                    if isInstalling {
                        ProgressView()
                    } else {
                        Text("Install")
                    }
                }
                .disabled(manifestURL.trimmingCharacters(in: .whitespaces).isEmpty || isInstalling)
                if let installError {
                    Text(message(for: installError))
                        .foregroundStyle(.red)
                }
            }

        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.canvas)
        .navigationTitle("Addons")
        #if os(iOS)
        .toolbar {
            if !store.addons.isEmpty { EditButton() }
        }
        #endif
    }

    @ViewBuilder
    private func actions(for addon: InstalledAddon) -> some View {
        // tvOS lists have no drag-to-reorder, so moving lives in the row's menu there.
        #if os(tvOS)
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
            store.remove(addon.id)
        }
    }

    private func install() {
        guard !isInstalling else { return }
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
                    .foregroundStyle(.orange)
            } else if addon.manifest == nil {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(addon.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Full-width rows, so focused rows on tvOS line up instead of hugging their text.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
