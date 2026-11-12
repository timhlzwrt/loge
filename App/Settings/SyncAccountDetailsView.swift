import LogeCore
import SwiftUI

/// Server, devices and recovery key of the connected account. It closes itself on disconnect,
/// rather than stay open on a connection that no longer exists.
struct SyncAccountDetailsView: View {
    @Environment(AccountSync.self) private var sync
    @Environment(PlaybackSession.self) private var playback
    @Environment(\.dismiss) private var dismiss
    @State private var revoking: SyncDevice?
    @State private var confirmsDisconnect = false
    @State private var devicesError: String?
    @State private var actionError: String?

    var body: some View {
        SettingsPage("Connection & Recovery") {
            Section {
                if let endpoint = sync.endpoint, let host = URL(string: endpoint)?.host() {
                    LabeledContent("Server", value: host)
                }
                LabeledContent("Account", value: sync.displayName ?? "Account")
                Text("Playback progress belongs to this account. Account switching keeps each person's local library separate.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(sync.devices) { device in
                    LabeledContent {
                        Button("Revoke access", role: .destructive) { revoking = device }
                            #if os(iOS)
                            // Otherwise the whole row is the button, and a tap on the name revokes.
                            .buttonStyle(.borderless)
                            #endif
                    } label: {
                        Text(device.id == sync.currentDeviceID ? "\(device.name) (This device)" : device.name)
                        if let added = try? Date(device.createdAt, strategy: .iso8601) {
                            Text("Added \(added.formatted(.dateTime.day().month(.abbreviated).year().locale(.interface)))")
                        }
                    }
                }
                Button("Refresh devices") { Task { await refreshDevices() } }
            } header: {
                SettingsHeader("Devices")
            } footer: {
                if let devicesError { Text(devicesError).foregroundStyle(.red) }
            }
            Section {
                if let key = sync.recoveryKey {
                    NavigationLink("Recovery key") {
                        SettingsPage("Recovery key") {
                            Section {
                                Text(key).font(.system(.body, design: .monospaced))
                                    #if !os(tvOS)
                                    .textSelection(.enabled)
                                    #endif
                            }
                        }
                    }
                }
            } footer: {
                Text("Keep your recovery key safe. Resetting a server login cannot decrypt data without this key or a connected device.")
            }
            Section {
                Button("Disconnect account", role: .destructive) { confirmsDisconnect = true }
                    .disabled(sync.isSyncing || playback.current != nil)
                if let actionError { Text(actionError).foregroundStyle(.red) }
            } footer: {
                Text("""
                    Your account library stays saved on this device. Disconnecting returns to the local \
                    library you used before connecting.
                    """)
            }
        }
        .task { await refreshDevices() }
        .onChange(of: sync.isConnected) { _, connected in
            if !connected { dismiss() }
        }
        .confirmationDialog(
            revoking?.id == sync.currentDeviceID ? "Disconnect this device?" : "Revoke \(revoking?.name ?? "device")?",
            isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
            titleVisibility: .visible,
            presenting: revoking
        ) { device in
            Button(device.id == sync.currentDeviceID ? "Disconnect" : "Revoke Access", role: .destructive) {
                Task { await revoke(device) }
            }
        } message: { device in
            Text(device.id == sync.currentDeviceID
                 ? "This device stops syncing and returns to its own library. Connecting again needs a new code."
                 : "That device stops syncing with this account. Connecting it again needs a new code.")
        }
        .confirmationDialog("Disconnect this account?", isPresented: $confirmsDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                actionError = nil
                do { try sync.disconnect() }
                catch { actionError = "Couldn't remove this connection from Keychain. Try again." }
            }
        } message: {
            Text("This device returns to the library it used before connecting. Connecting again needs a new code.")
        }
    }

    private func refreshDevices() async {
        do {
            try await sync.refreshDevices()
            devicesError = nil
        } catch {
            devicesError = message(for: error, otherwise: "Couldn't load the devices. Try again.")
        }
    }

    private func revoke(_ device: SyncDevice) async {
        do {
            try await sync.revokeDevice(id: device.id)
            devicesError = nil
        } catch {
            devicesError = message(for: error, otherwise: "Couldn't revoke \(device.name). Try again.")
        }
    }

    private func message(for error: Error, otherwise fallback: String) -> String {
        (error as? SyncError)?.localizedDescription ?? fallback
    }
}
