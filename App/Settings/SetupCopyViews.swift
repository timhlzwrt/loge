import LogeCore
import SwiftUI

#if !os(tvOS)
/// A one-time copy of this device's addons for someone else. The Apple TV has no share
/// sheet, so it only imports.
struct ShareSetupView: View {
    @Environment(AddonStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var includesPreferences = false
    @State private var copied = false

    var body: some View {
        SettingsPage("Share Setup") {
            Section {
                ForEach(store.addons) { Text($0.displayName) }
            } header: {
                SettingsHeader("Addons")
            }
            Section {
                Toggle("Include playback preferences", isOn: $includesPreferences)
            } footer: {
                Text("Audio and subtitle language, and the maximum bitrate.")
            }
            Section {
                if let code {
                    ShareLink(item: message(link: SetupCode.linkPrefix + code), subject: Text("loge setup")) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    Button(copied ? "Code Copied" : "Copy Code", systemImage: "doc.on.doc") { copy(code) }
                } else {
                    Text("Couldn't create a code for these addons.").foregroundStyle(.red)
                }
            } footer: {
                Text("""
                    Anyone with this code can use your addons, including any accounts their addresses \
                    contain. Send it only to people you trust.
                    """)
            }
        }
        .onChange(of: includesPreferences) { copied = false }
        .toolbar { Button("Done") { dismiss() } }
    }

    /// Rebuilt with each change, so it always matches what the sheet shows.
    private var code: String? {
        let preferences = includesPreferences ? SetupCode.Preferences(defaults: .standard) : nil
        return try? SetupCode(addonURLs: store.addons.map(\.manifestURL), addonNames: store.customNames, preferences: preferences).encoded()
    }

    /// The link alone carries the code: the import field takes it as it is, for the Apple TV.
    private func message(link: String) -> String {
        """
        My loge addons: open this link on an iPhone, iPad or Mac with loge, or paste it into \
        Settings → Addons → Import Setup.

        \(link)
        """
    }

    private func copy(_ code: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        // Not left on the clipboard for long: the addons' addresses can hold account keys.
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: code]],
                                      options: [.expirationDate: Date.now.addingTimeInterval(600)])
        #endif
        copied = true
    }
}
#endif

/// Adds the addons, and the preferences if included, from a code someone sent.
struct ImportSetupView: View {
    @Environment(AddonStore.self) private var store
    @State private var text = ""
    @State private var code: SetupCode?
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var result: AddonStore.SetupImport?

    /// A link opening the app arrives already read, or as the reason it couldn't be.
    init(code: SetupCode? = nil, errorMessage: String? = nil) {
        _code = State(initialValue: code)
        _errorMessage = State(initialValue: errorMessage)
    }

    var body: some View {
        SettingsPage("Import Setup") {
            if code == nil {
                Section {
                    SecureField("Setup code or link", text: $text)
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit(review)
                        .onChange(of: text) { errorMessage = nil }
                    // As with Install, a disabled row reads as stray grey text on tvOS.
                    #if os(tvOS)
                    let showsReview = !isTextEmpty
                    #else
                    let showsReview = true
                    #endif
                    if showsReview {
                        Button("Review", action: review).disabled(isTextEmpty)
                    }
                } footer: {
                    #if os(tvOS)
                    Text("Paste the code or link someone sent you with the Remote keyboard on your iPhone.")
                    #else
                    Text("Paste the code or link someone sent you.")
                    #endif
                }
            } else if let code {
                review(of: code)
            }
            if let result {
                outcome(of: result)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
    }

    @ViewBuilder
    private func review(of code: SetupCode) -> some View {
        Section {
            // By position: two configurations of one addon share a host.
            ForEach(Array(code.addonHosts.enumerated()), id: \.offset) { Text($0.element) }
        } header: {
            SettingsHeader("Addons in this setup")
        } footer: {
            Text(code.preferences == nil
                 ? "Playback preferences aren't included."
                 : "Also sets audio and subtitle language and the maximum bitrate.")
        }
        Section {
            Button("Add to My Addons") { run(code, replacing: false) }
            Button("Replace My Addons", role: .destructive) { run(code, replacing: true) }
            Button("Cancel") { self.code = nil }
            if isImporting { ProgressView() }
        } footer: {
            Text("Adding keeps your addons. Replacing removes the ones not in this setup, once all of these are installed.")
        }
        .disabled(isImporting)
    }

    @ViewBuilder
    private func outcome(of result: AddonStore.SetupImport) -> some View {
        Section {
            if result.replaced {
                Text("Your addons now match this setup.")
            } else {
                Text(result.added.isEmpty ? "No addons added." : "Added \(result.added.joined(separator: ", ")).")
            }
            // By position: several addons can share a host.
            ForEach(Array(result.failed.enumerated()), id: \.offset) { _, failure in
                Text("Couldn't add \(failure.host). \(AddonsSettingsView.message(for: failure.error))")
                    .foregroundStyle(.red)
            }
            if result.keptExisting {
                Text("Your other addons were kept, because not all of these could be installed.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isTextEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func review() {
        guard !isTextEmpty else { return }
        result = nil
        do throws(SetupCode.DecodingError) {
            code = try SetupCode(decoding: text)
            text = ""
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func run(_ code: SetupCode, replacing: Bool) {
        isImporting = true
        Task {
            let result = await store.importSetup(code, replacing: replacing)
            code.preferences?.write(to: .standard)
            self.result = result
            self.code = nil
            isImporting = false
        }
    }

    static func message(for error: SetupCode.DecodingError) -> String {
        switch error {
        case .malformed: "That isn't a complete loge setup. Copy all of it and try again."
        case .newerVersion: "This setup comes from a newer version of loge. Update the app to import it."
        }
    }
}
