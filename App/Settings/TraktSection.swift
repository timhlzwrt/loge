import MediaCore
import SwiftUI

/// Signs this device in to Trakt, which carries watch progress between devices.
struct TraktSection: View {
    @Environment(TraktAccount.self) private var trakt
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var signingIn: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            switch trakt.state {
            case .signedIn(let username):
                LabeledContent("Signed in as", value: username)
                Button("Sync Now") { Task { await trakt.pullProgress() } }
                Button("Sign Out", role: .destructive) { trakt.signOut() }
            case .awaitingApproval(let code):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Go to \(code.verificationURL) and enter")
                        .foregroundStyle(.secondary)
                    Text(code.userCode)
                        .font(.title.monospaced().weight(.semibold))
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                }
                Button("Cancel") { signingIn?.cancel() }
            case .signedOut where trakt.credentials == nil:
                TextField("Client ID", text: $clientID)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Client Secret", text: $clientSecret)
                Button("Save") {
                    trakt.setCredentials(TraktCredentials(
                        clientID: clientID.trimmingCharacters(in: .whitespaces),
                        clientSecret: clientSecret.trimmingCharacters(in: .whitespaces)))
                    clientID = ""
                    clientSecret = ""
                }
                .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty
                          || clientSecret.trimmingCharacters(in: .whitespaces).isEmpty)
            case .signedOut:
                Button("Sign In", action: signIn)
                Button("Use Different App Keys") { trakt.setCredentials(nil) }
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Trakt")
        } footer: {
            if trakt.credentials == nil {
                Text("Create an app at trakt.tv/oauth/applications with the redirect URI urn:ietf:wg:oauth:2.0:oob, then enter its keys here.")
            } else {
                Text("Progress syncs with Trakt, so playback continues where it stopped on another device.")
            }
        }
    }

    private func signIn() {
        errorMessage = nil
        signingIn = Task {
            do {
                try await trakt.signIn()
            } catch is CancellationError {
                // Cancelled from the button; nothing to report.
            } catch TraktError.codeExpired {
                errorMessage = "The code expired before it was entered. Try again."
            } catch TraktError.denied {
                errorMessage = "Trakt declined the sign-in."
            } catch TraktError.httpStatus(401) {
                errorMessage = "Trakt didn't accept the app keys. Check the Client ID and Secret."
            } catch {
                errorMessage = "Couldn't reach Trakt. \(error.localizedDescription)"
            }
        }
    }
}
