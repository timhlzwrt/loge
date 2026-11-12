import LogeCore
import SwiftUI

/// Signs this device in to Trakt, which carries watch progress between devices.
struct TraktSection: View {
    @Environment(TraktAccount.self) private var trakt
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var confirmsSignOut = false
    @State private var confirmsForgettingKeys = false

    var body: some View {
        Section {
            switch trakt.state {
            case .signedIn(let username):
                LabeledContent("Signed in as", value: username)
                Button(trakt.isPulling ? "Syncing…" : "Sync Now") { Task { await trakt.pullProgress() } }
                    .disabled(trakt.isPaused || trakt.isPulling)
                if trakt.pullFailed {
                    Text("Couldn't reach Trakt. Progress syncs again when the app next opens.")
                        .foregroundStyle(.red)
                }
                Button("Sign Out", role: .destructive) { confirmsSignOut = true }
                    .confirmationDialog("Sign out of Trakt?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) { trakt.signOut() }
                    } message: {
                        Text(trakt.hasUnsentChanges
                             ? "Progress from this device that hasn't reached Trakt yet won't be sent."
                             : "This device's library keeps its progress.")
                    }
            case .awaitingApproval(let code):
                approval(code)
                Button("Cancel") { trakt.cancelSignIn() }
            case .signedOut where trakt.credentials == nil:
                TextField("Client ID", text: $clientID)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Client Secret", text: $clientSecret)
                Button("Save") {
                    trakt.setCredentials(TraktCredentials(clientID: trimmed(clientID), clientSecret: trimmed(clientSecret)))
                    clientID = ""
                    clientSecret = ""
                }
                .disabled(trimmed(clientID).isEmpty || trimmed(clientSecret).isEmpty)
            case .signedOut:
                if trakt.isSigningIn {
                    // Until Trakt hands out a code, which can take a moment on a slow connection.
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Getting a code…").foregroundStyle(.secondary)
                    }
                    Button("Cancel") { trakt.cancelSignIn() }
                } else {
                    // A failure shows through `signInError`, which outlasts this page.
                    Button("Sign In") { Task { try? await trakt.signIn() } }
                }
                Button("Use Different App Keys", role: .destructive) { confirmsForgettingKeys = true }
                    .confirmationDialog("Remove the saved app keys?", isPresented: $confirmsForgettingKeys,
                                        titleVisibility: .visible) {
                        Button("Remove Keys", role: .destructive) { trakt.setCredentials(nil) }
                    } message: {
                        Text("You'll enter a Client ID and Secret again before signing in.")
                    }
            }
            if let signInMessage {
                Text(signInMessage)
                    .foregroundStyle(.red)
            }
            if trakt.credentialsNotSaved {
                Text("Couldn't save the app keys in Keychain. They'll need entering again after the app restarts.")
                    .foregroundStyle(.red)
            }
        } footer: {
            if trakt.isPaused {
                Text("""
                    Your Sync account handles playback progress. Trakt imports and scrobbling are paused to \
                    keep accounts separate; its existing connection stays saved on this device.
                    """)
            } else if trakt.credentials == nil {
                Text("Create an app at trakt.tv/oauth/applications with the redirect URI urn:ietf:wg:oauth:2.0:oob, then enter its keys here.")
            } else {
                Text("Progress syncs with Trakt, so playback continues where it stopped on another device.")
            }
        }
    }

    @ViewBuilder
    private func approval(_ code: TraktDeviceCode) -> some View {
        #if os(tvOS)
        // Scanning opens the page on the phone, so only the short code is typed there.
        HStack(spacing: 48) {
            QRCodeImage(code.verificationURL, label: "Scan to open \(code.verificationURL) on your phone")
            userCode(code, instruction: "Scan the code or go to \(code.verificationURL), then enter")
        }
        .padding(.vertical, 12)
        #else
        userCode(code, instruction: "Go to \(code.verificationURL) and enter")
        if let url = URL(string: code.verificationURL) {
            Link("Open \(url.host() ?? "Trakt")", destination: url)
        }
        #endif
    }

    private func userCode(_ code: TraktDeviceCode, instruction: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(instruction)
                .foregroundStyle(.secondary)
            Text(code.userCode)
                .font(.title.monospaced().weight(.semibold))
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
        }
    }

    /// The account keeps the error, so it still shows after the page was closed and opened again.
    private var signInMessage: String? {
        guard let error = trakt.signInError else { return nil }
        return switch error as? TraktError {
        case .codeExpired: "The code expired before it was entered. Try again."
        case .denied: "Trakt declined the sign-in."
        case .httpStatus(401): "Trakt didn't accept the app keys. Check the Client ID and Secret."
        case .unavailable(let code): "Couldn't reach Trakt. \(URLError(code).localizedDescription)"
        default: "Couldn't sign in to Trakt. Try again."
        }
    }

    /// Pasted keys often carry a trailing newline, which Trakt then rejects.
    private func trimmed(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
