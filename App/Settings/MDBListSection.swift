import LogeCore
import SwiftUI

/// The API key for MDBList, laid out like the TMDB page.
struct MDBListSection: View {
    @Environment(MDBListAccount.self) private var mdblist
    @State private var isSettingUp = false
    @State private var confirmsRemoval = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            LabeledContent("Access", value: mdblist.isConfigured ? "Connected" : "Not connected")
            Button(mdblist.isConfigured ? "Replace API key" : "Connect MDBList") { isSettingUp = true }
                .sheet(isPresented: $isSettingUp) { MDBListSetupView() }
            if mdblist.isConfigured || mdblist.storageError != nil {
                Button("Remove API key", role: .destructive) { confirmsRemoval = true }
                    .confirmationDialog("Remove the MDBList key?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                        Button("Remove", role: .destructive) {
                            do { try mdblist.disconnect() } catch { errorMessage = error.localizedDescription }
                        }
                    } message: {
                        Text("Letterboxd and Rotten Tomatoes scores stop until a key is entered again.")
                    }
            }
            if let message = errorMessage ?? mdblist.storageError?.localizedDescription {
                Text(message).foregroundStyle(.red)
            }
            if mdblist.storageError != nil {
                Button("Retry reading saved key") {
                    errorMessage = nil
                    mdblist.retryStorageRead()
                }
            }
        } footer: {
            Text("""
                Adds the Letterboxd score and Rotten Tomatoes' Tomatometer beside the IMDb rating on a \
                title's page. A free key allows 1,000 titles a day. It is stored in this device's Keychain.
                """)
        }
        .onChange(of: mdblist.revision) { errorMessage = nil }
    }
}

private struct MDBListSetupView: View {
    @Environment(MDBListAccount.self) private var mdblist
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var connecting: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Copy the API key from your MDBList account's preferences, under API Access.")
                    #if os(tvOS)
                    Text("On your phone or computer, open mdblist.com/preferences. Enter the key here using the Apple TV Remote keyboard.")
                        .foregroundStyle(.secondary)
                    #else
                    Link("Open MDBList preferences", destination: URL(string: "https://mdblist.com/preferences/")!)
                    #endif
                    SecureField("API key", text: $key)
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .disabled(connecting != nil)
                        .onChange(of: key) { errorMessage = nil }
                } footer: {
                    Text("""
                        The key is checked with MDBList before it is saved. Replacing a key keeps the \
                        existing one until the new key is verified and saved.
                        """)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                #if os(tvOS)
                Section {
                    Button(connecting == nil ? "Connect" : "Checking key…", action: connect)
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting != nil)
                    Button("Cancel", action: cancel)
                }
                #endif
            }
            .navigationTitle(mdblist.isConfigured ? "Replace MDBList key" : "Connect MDBList")
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: connect) {
                        if connecting != nil { ProgressView() } else { Text("Connect") }
                    }
                    .accessibilityLabel("Connect MDBList")
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting != nil)
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
        .onDisappear {
            connecting?.cancel()
            key = ""
        }
    }

    private func cancel() {
        connecting?.cancel()
        key = ""
        dismiss()
    }

    private func connect() {
        errorMessage = nil
        connecting = Task {
            defer { connecting = nil }
            do {
                try await mdblist.connect(apiKey: key)
                key = ""
                dismiss()
            } catch is CancellationError {
                // Closing the form cancels validation without saving a key.
            } catch MDBListError.unauthorized {
                errorMessage = "MDBList didn't accept this key. Copy the API key from your preferences and try again."
            } catch MDBListError.rateLimited {
                errorMessage = "This key has used up its requests for now. Try again later."
            } catch let error as MDBListAccountError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Couldn't verify the key with MDBList. Check your connection and try again."
            }
        }
    }
}
