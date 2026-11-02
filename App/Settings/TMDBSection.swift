import MediaCore
import SwiftUI

struct TMDBSection: View {
    @Environment(TMDBAccount.self) private var tmdb
    @State private var isSettingUp = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            LabeledContent("Access", value: tmdb.isConfigured ? "Connected" : "Not connected")
            Button(tmdb.isConfigured ? "Replace API token" : "Connect TMDB") { isSettingUp = true }
                .sheet(isPresented: $isSettingUp) { TMDBSetupView() }
            if tmdb.isConfigured || tmdb.storageError != nil {
                Button("Remove API token", role: .destructive) {
                    do { try tmdb.disconnect() } catch { errorMessage = error.localizedDescription }
                }
            }
            if let message = errorMessage ?? tmdb.storageError?.localizedDescription {
                Text(message).foregroundStyle(.red)
            }
            if tmdb.storageError != nil {
                Button("Retry reading saved token") {
                    errorMessage = nil
                    tmdb.retryStorageRead()
                }
            }
        } header: {
            Text("TMDB")
        } footer: {
            Text("Adds movie and series details, cast portraits and crew credits. The API token is stored in this device's Keychain.")
        }
        .onChange(of: tmdb.revision) { errorMessage = nil }
    }
}

private struct TMDBSetupView: View {
    @Environment(TMDBAccount.self) private var tmdb
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var connecting: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Copy the API Read Access Token from your TMDB account's API settings.")
                    #if os(tvOS)
                    Text("On your phone or computer, open themoviedb.org/settings/api. Enter the token here using the Apple TV Remote keyboard.")
                        .foregroundStyle(.secondary)
                    #else
                    Link("Open TMDB API settings", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                    #endif
                    SecureField("API Read Access Token", text: $token)
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .disabled(connecting != nil)
                        .onChange(of: token) { errorMessage = nil }
                } footer: {
                    Text("The token is checked with TMDB before it is saved. Replacing a token keeps the existing one until the new token is verified and saved.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                #if os(tvOS)
                Section {
                    Button(connecting == nil ? "Connect" : "Checking token…", action: connect)
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting != nil)
                    Button("Cancel", action: cancel)
                }
                #endif
            }
            .navigationTitle(tmdb.isConfigured ? "Replace TMDB token" : "Connect TMDB")
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: connect) {
                        if connecting != nil { ProgressView() } else { Text("Connect") }
                    }
                    .accessibilityLabel("Connect TMDB")
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting != nil)
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
        .onDisappear {
            connecting?.cancel()
            token = ""
        }
    }

    private func cancel() {
        connecting?.cancel()
        token = ""
        dismiss()
    }

    private func connect() {
        errorMessage = nil
        connecting = Task {
            defer { connecting = nil }
            do {
                try await tmdb.connect(readAccessToken: token)
                token = ""
                dismiss()
            } catch is CancellationError {
                // Closing the form cancels validation without saving a token.
            } catch TMDBError.unauthorized {
                errorMessage = "TMDB didn't accept this token. Copy the API Read Access Token from your API settings and try again."
            } catch TMDBError.rateLimited {
                errorMessage = "TMDB is receiving too many requests. Wait a moment and try again."
            } catch let error as TMDBAccountError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Couldn't verify the token with TMDB. Check your connection and try again."
            }
        }
    }
}

struct TMDBCreditsSection: View {
    var body: some View {
        Section("Credits") {
            VStack(alignment: .leading, spacing: 12) {
                Image("TMDBLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 16)
                    .foregroundStyle(.white)
                    .accessibilityLabel("TMDB")
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #if os(tvOS)
                Text("themoviedb.org").font(.footnote).foregroundStyle(.secondary)
                #else
                Link("The Movie Database", destination: URL(string: "https://www.themoviedb.org")!)
                    .font(.footnote)
                #endif
            }
            .padding(.vertical, 8)
        }
    }
}
