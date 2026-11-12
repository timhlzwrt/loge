import CoreImage.CIFilterBuiltins
import LogeCore
import SwiftUI

struct SyncSettingsView: View {
    @Environment(AccountSync.self) private var sync
    @Environment(PlaybackSession.self) private var playback
    @State private var connectionCode = ""
    @State private var recoveryKey = ""
    @State private var presentedSheet: SyncSheet?
    @State private var leaving: SyncGroup?

    var body: some View {
        SettingsPage("Sync") {
            if sync.isConnected {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sync.displayName ?? "Account").font(.title2.weight(.semibold))
                        // Inline, so a background sync doesn't add and remove a row and shift focus.
                        HStack(spacing: 8) {
                            Text(sync.status.text).foregroundStyle(.secondary)
                            if sync.isSyncing { ProgressView() }
                        }
                        if let date = sync.lastSync {
                            Text("Last synced \(date, style: .relative) ago")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    Button("Sync Now") { Task { await sync.sync() } }
                        .disabled(sync.isSyncing || sync.needsChoice)
                }
                if sync.needsChoice {
                    Section {
                        Text(sync.choiceSummary)
                            .foregroundStyle(.secondary)
                        Button("Keep This Device's Version") { Task { await sync.resolve(useLocal: true) } }
                        Button("Keep Server Version") { Task { await sync.resolve(useLocal: false) } }
                    } header: { SettingsHeader("Review changes") }
                        .disabled(sync.isSyncing)
                }
                Section {
                    Button { presentedSheet = .device } label: {
                        Label("Add my device", systemImage: "plus.rectangle.on.rectangle")
                    }
                    Button { presentedSheet = .share } label: {
                        Label("Share setup", systemImage: "person.2")
                    }
                    Button("Join shared setup") { presentedSheet = .join }
                } footer: {
                    Text("Your devices share playback progress. Other people only receive the setup categories you choose.")
                }
                if !sync.sharedGroups.isEmpty {
                    Section {
                        ForEach(sync.sharedGroups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name).font(.headline)
                                Text(SyncCategory.allCases.filter { group.categories.contains($0) }.map(\.name).joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                Button("Leave shared setup", role: .destructive) { leaving = group }
                                    #if os(iOS)
                                    // Otherwise the whole row is the button, and a tap on the name leaves.
                                    .buttonStyle(.borderless)
                                    #endif
                                    .disabled(sync.isSyncing)
                            }
                        }
                    } header: { SettingsHeader("Shared setup") } footer: {
                        Text("Leaving a setup you created stops sharing for everyone. Other setups are removed only from your account.")
                    }
                }
                Section {
                    NavigationLink("Connection & recovery") {
                        SyncAccountDetailsView()
                    }
                } header: { SettingsHeader("Advanced") }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Continue on your other devices")
                            .font(.title2.weight(.semibold))
                        Text("Keep playback progress, addons and preferences in sync through your own server.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Section {
                    SecureField("Connection code", text: $connectionCode)
                        .accessibilityIdentifier("sync.connectionCode")
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    if !trimmedRecoveryKey.isEmpty {
                        LabeledContent("Recovery key added") {
                            Button("Clear") { recoveryKey = "" }
                                #if os(iOS)
                                .buttonStyle(.borderless)
                                #endif
                        }
                    }
                    // A disabled row on tvOS reads as a stray caption under the field, so the action
                    // appears once there's a code to connect with.
                    #if os(tvOS)
                    let showsConnect = !connectionCode.isEmpty || sync.isSyncing
                    #else
                    let showsConnect = true
                    #endif
                    if showsConnect {
                        Button(sync.isSyncing ? "Connecting…" : "Connect account") {
                            Task {
                                await sync.connect(code: connectionCode, deviceName: currentDeviceName,
                                                   recoveryKey: trimmedRecoveryKey.isEmpty ? nil : trimmedRecoveryKey)
                                if sync.isConnected { connectionCode = ""; recoveryKey = "" }
                            }
                        }
                        .disabled(connectionCode.isEmpty || sync.isSyncing || playback.current != nil)
                    }
                } footer: {
                    Text("""
                        Use a code from your server administrator or one of your connected devices. On Apple \
                        TV, paste it with the Remote keyboard on your phone.
                        """)
                }
                Section {
                    NavigationLink(trimmedRecoveryKey.isEmpty ? "Recover an existing account" : "Change recovery key") {
                        SettingsPage("Recover account") {
                            Section {
                                SecureField("Recovery key", text: $recoveryKey)
                                    .autocorrectionDisabled()
                                    #if !os(macOS)
                                    .textInputAutocapitalization(.never)
                                    #endif
                            } footer: {
                                Text("""
                                    Enter the original recovery key, then return and connect with your \
                                    administrator's code. A code from your connected device already includes \
                                    the key.
                                    """)
                            }
                        }
                    }
                    #if !os(tvOS)
                    Link("Set up your own server", destination: URL(string: "https://github.com/timhlzwrt/loge/blob/main/docs/SYNC.md")!)
                    #endif
                } header: {
                    SettingsHeader("Advanced")
                } footer: {
                    #if os(tvOS)
                    // tvOS can't open web links.
                    Text("To run your own server, see docs/SYNC.md in the loge repository on GitHub.")
                    #endif
                }
            }
            if playback.current != nil {
                Section { Text("Close playback before connecting or disconnecting an account.").foregroundStyle(.secondary) }
            }
            if let message = sync.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            NavigationStack {
                SyncSharingView(mode: sheet)
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 620)
            #endif
        }
        .confirmationDialog(
            "Leave \(leaving?.name ?? "shared setup")?",
            isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
            titleVisibility: .visible,
            presenting: leaving
        ) { group in
            Button("Leave", role: .destructive) { Task { await sync.leaveGroup(id: group.id) } }
        } message: { _ in
            Text("If you created this setup, sharing stops for everyone in it. Otherwise only your account leaves.")
        }
    }

    /// A pasted key often ends in a newline, which isn't valid base64.
    private var trimmedRecoveryKey: String {
        recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentDeviceName: String {
        #if os(macOS)
        "Mac"
        #elseif os(tvOS)
        "Apple TV"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}

private enum SyncSheet: String, Identifiable {
    case device, share, join
    var id: Self { self }
    var title: String {
        #if os(tvOS)
        switch self {
        case .device: "Device"
        case .share: "Share"
        case .join: "Join"
        }
        #else
        switch self {
        case .device: "Add my device"
        case .share: "Share setup"
        case .join: "Join shared setup"
        }
        #endif
    }
}

private struct SyncSharingView: View {
    let mode: SyncSheet
    @Environment(AccountSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var categories: Set<SyncCategory> = [.addons]
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        SettingsPage(mode.title) {
            if mode == .join {
                Section {
                    SecureField("Invitation code", text: $code)
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button("Join shared setup", action: join)
                        // `joinShare` returns without a word while a sync runs or a choice waits.
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking
                                  || sync.isSyncing || sync.needsChoice)
                } footer: {
                    Text("Shared addon and preference changes sync for everyone in the group. Your playback progress stays private.")
                }
            } else if code.isEmpty {
                if mode == .share {
                    Section {
                        categoryToggle("Addons", category: .addons)
                        categoryToggle("Playback preferences", category: .playback)
                        categoryToggle("Appearance", category: .appearance)
                    } header: { SettingsHeader("What to share") } footer: {
                        Text("Members share future changes to these categories. Playback progress and account access are never included.")
                    }
                } else {
                    Section {
                        Text("""
                            This connects another device to your personal account, including playback \
                            progress. Use Share setup when inviting another person.
                            """)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Create connection code", action: createCode)
                        .disabled(isWorking || (mode == .share && categories.isEmpty))
                }
            } else {
                Section {
                    QRCodeImage(code, label: "Scan this connection code with your other device")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .accessibilityLabel("Connection code")
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                        #if !os(tvOS)
                        ShareLink("Share code", item: code)
                        #endif
                } footer: {
                    Text("This code expires and works once. Share it only with the intended person or device.")
                }
            }
            if isWorking { Section { ProgressView(mode == .join ? "Joining…" : "Creating code…") } }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            #if os(tvOS)
            // The toolbar's Done doesn't show on tvOS; Menu also closes the sheet.
            Section { Button("Done") { dismiss() } }
            #endif
        }
        .toolbar { Button("Done") { dismiss() } }
    }

    private func categoryToggle(_ title: String, category: SyncCategory) -> some View {
        Toggle(title, isOn: Binding(get: { categories.contains(category) }, set: { enabled in
            if enabled { categories.insert(category) } else { categories.remove(category) }
        }))
    }

    private func join() {
        isWorking = true
        errorMessage = nil
        Task {
            await sync.joinShare(code: code)
            isWorking = false
            // Failures land on the Sync page behind this sheet, so they're repeated here.
            if sync.status == .sharedSetupJoined && sync.errorMessage == nil {
                dismiss()
            } else {
                errorMessage = sync.errorMessage ?? "Couldn't join the shared setup. Try again."
            }
        }
    }

    private func createCode() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                if mode == .device {
                    code = try await sync.makeDeviceCode()
                } else {
                    code = try await sync.makeShareCode(categories: categories)
                }
            } catch let error as SyncError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Couldn't create a connection code. Check the connection and try again."
            }
        }
    }
}

/// A QR code on a white square, which phones read reliably on a dark screen.
struct QRCodeImage: View {
    private let image: CGImage?
    private let label: String

    init(_ message: String, label: String) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        image = filter.outputImage.flatMap {
            CIContext().createCGImage($0, from: $0.extent)
        }
        self.label = label
    }

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable().interpolation(.none).scaledToFit()
                .frame(width: 250, height: 250)
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel(label)
        }
    }
}
