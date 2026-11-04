import LogeCore
import SwiftUI

struct ConfigurationSyncView: View {
    @Environment(ConfigurationSyncAccount.self) private var sync
    @State private var endpoint = ""
    @State private var username = ""
    @State private var password = ""
    @State private var key = ""
    @State private var showKey = false
    @State private var showSetupCode = false
    @State private var setupCode = ""
    @State private var disconnectError: String?

    var body: some View {
        SettingsPage("Sync") {
            Section {
                Text("Sync addon setup and app preferences through your own server. Watch progress and history use Trakt separately.")
                    .foregroundStyle(.secondary)
            }
            if sync.isConnected {
                Section("Connection") {
                    Text(sync.status)
                    if let date = sync.lastSync {
                        LabeledContent("Last synced") { Text(date, style: .relative) }
                    }
                    Button("Sync Now") { Task { await sync.sync() } }
                        .disabled(sync.isSyncing || sync.needsChoice)
                }
                if sync.needsChoice {
                    Section("Choose setup") {
                        Text(sync.lastSync == nil
                             ? "Choose the setup to start with. Your current settings stay in place until you choose."
                             : "Choose which version to keep for the conflicting settings. Changes to different settings are combined.")
                            .foregroundStyle(.secondary)
                        if let local = sync.choiceLocal, let remote = sync.choiceRemote {
                            ForEach(ConfigurationField.allCases.filter { sync.conflictingFields.contains($0) }, id: \.self) { field in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(name(for: field)).font(.headline)
                                    Text("This device: \(value(field, in: local))")
                                    Text("Server: \(value(field, in: remote))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Use This Device’s Setup") { Task { await sync.resolve(useLocal: true) } }
                        Button("Use Server Setup") { Task { await sync.resolve(useLocal: false) } }
                    }
                    .disabled(sync.isSyncing)
                }
                Section {
                    Button(showSetupCode ? "Hide Setup Code" : "Show Setup Code") { showSetupCode.toggle() }
                    if showSetupCode, let code = sync.setupCode {
                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            #if !os(tvOS)
                            .textSelection(.enabled)
                            #endif
                    }
                    Button(showKey ? "Hide Recovery Key" : "Show Recovery Key") { showKey.toggle() }
                    if showKey, let recoveryKey = sync.recoveryKey {
                        Text(recoveryKey)
                            .font(.system(.body, design: .monospaced))
                            #if !os(tvOS)
                            .textSelection(.enabled)
                            #endif
                            .accessibilityLabel("Recovery key: \(recoveryKey)")
                    }
                } footer: {
                    Text("The setup code includes your password and recovery key. Share it only with your own devices, using the Apple TV Remote keyboard if needed. Keep the recovery key safe; your server cannot recover it.")
                }
                Section {
                    Button("Disconnect", role: .destructive) {
                        do {
                            try sync.disconnect()
                            password = ""
                            key = ""
                            showKey = false
                            showSetupCode = false
                            disconnectError = nil
                        } catch {
                            disconnectError = "Couldn’t remove the saved connection from Keychain. Try again."
                        }
                    }
                    .disabled(sync.isSyncing)
                } footer: {
                    Text("Disconnecting keeps this device’s addons and preferences.")
                }
            } else {
                Section("Connect another device") {
                    SecureField("Setup code", text: $setupCode)
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button("Use Setup Code") { importSetupCode() }
                        .disabled(setupCode.isEmpty || sync.isSyncing)
                }
                Section("Your server") {
                    TextField("HTTPS configuration URL", text: $endpoint)
                        .accessibilityIdentifier("sync.endpoint")
                        #if !os(macOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Username", text: $username)
                        .accessibilityIdentifier("sync.username")
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("App password", text: $password)
                        .accessibilityIdentifier("sync.password")
                }
                .autocorrectionDisabled()
                Section {
                    SecureField("Recovery key", text: $key)
                        .accessibilityIdentifier("sync.key")
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button("Generate New Recovery Key") {
                        key = ConfigurationCipher.generateKey()
                        showKey = true
                    }
                    if showKey, !key.isEmpty {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            #if !os(tvOS)
                            .textSelection(.enabled)
                            #endif
                    }
                } header: {
                    Text("Encryption")
                } footer: {
                    Text("Use the existing recovery key when connecting another device. Generate a new key only for a new setup. Addon credentials are encrypted before they leave this device.")
                }
                Section {
                    Button("Connect") {
                        disconnectError = nil
                        showKey = false
                        Task {
                            await sync.connect(endpoint: endpoint, username: username, password: password, key: key)
                            if sync.isConnected { password = ""; key = "" }
                        }
                    }
                    .disabled(sync.isSyncing || endpoint.isEmpty || username.isEmpty || password.isEmpty || key.isEmpty)
                } footer: {
                    Text("Optional. No server is selected by default. Requires a compatible CouchDB sync endpoint; see the self-hosting guide in the project README.")
                }
            }
            if sync.isSyncing {
                Section { ProgressView("Syncing…") }
            }
            if let message = disconnectError ?? sync.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
    }

    private func importSetupCode() {
        struct Setup: Decodable {
            let endpoint: String
            let username: String
            let password: String
            let key: String
        }
        guard setupCode.utf8.count <= 32_768,
              let data = Data(base64Encoded: setupCode.trimmingCharacters(in: .whitespacesAndNewlines)),
              let setup = try? JSONDecoder().decode(Setup.self, from: data) else {
            disconnectError = "That setup code isn’t valid. Copy it again from your connected device."
            return
        }
        endpoint = setup.endpoint
        username = setup.username
        password = setup.password
        key = setup.key
        setupCode = ""
        disconnectError = nil
    }

    private func name(for field: ConfigurationField) -> String {
        switch field {
        case .addonURLs: "Addons"
        case .audioLanguage: "Audio"
        case .subtitleLanguage: "Subtitles"
        case .subtitleScale: "Subtitle size"
        case .maximumSourceGigabytes: "Automatic source limit"
        case .accent: "Accent"
        }
    }

    private func value(_ field: ConfigurationField, in configuration: SyncedConfiguration) -> String {
        switch field {
        case .addonURLs:
            let hosts = configuration.addonURLs.prefix(5).compactMap { URL(string: $0)?.host() }
            return configuration.addonURLs.isEmpty ? "None" : "\(configuration.addonURLs.count) — \(hosts.joined(separator: ", "))"
        case .audioLanguage:
            return configuration.audioLanguage.isEmpty ? "File default" : language(configuration.audioLanguage)
        case .subtitleLanguage:
            return configuration.subtitleLanguage.isEmpty ? "Off" : language(configuration.subtitleLanguage)
        case .subtitleScale:
            return PlaybackPreferences.subtitleScales.first { $0.scale == configuration.subtitleScale }?.name ?? "Normal"
        case .maximumSourceGigabytes:
            return configuration.maximumSourceGigabytes == 0 ? "No limit" : "\(configuration.maximumSourceGigabytes) GB"
        case .accent: return configuration.accent.capitalized
        }
    }

    private func language(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
