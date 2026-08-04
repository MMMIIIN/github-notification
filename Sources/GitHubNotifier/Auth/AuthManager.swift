import Foundation
import Combine

/// Authentication via a GitHub Personal Access Token. No OAuth App, no client
/// secret, no backend — the user supplies a token, we validate it and keep it in
/// the Keychain.
@MainActor
final class AuthManager: ObservableObject {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn(login: String)
        case error(String)
    }

    @Published private(set) var state: State = .signedOut
    /// The active token, or nil when signed out. Read by the poller.
    @Published private(set) var token: String?
    /// The signed-in user's login, used to locate @mentions in a thread.
    @Published private(set) var currentLogin: String?

    init() {
        // Restore a previous session from the Keychain on launch.
        if let saved = KeychainStore.loadToken() {
            self.token = saved
            self.state = .signedIn(login: "…")
            Task { await self.validateRestoredToken(saved) }
        }
    }

    // MARK: - Sign in with a Personal Access Token

    func signIn(withToken pat: String) async {
        let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .error("Please enter a token.")
            return
        }
        state = .signingIn
        do {
            // Validate by resolving the user's login; confirms the token + scopes.
            let login = try await GitHubAPIClient(token: trimmed).fetchAuthenticatedUserLogin()
            KeychainStore.saveToken(trimmed)
            SettingsStore.shared.authMethod = .pat
            self.token = trimmed
            self.currentLogin = login
            self.state = .signedIn(login: login)
        } catch GitHubAPIError.unauthorized {
            state = .error("That token was rejected. Check its scopes (needs notifications and repo).")
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func validateRestoredToken(_ token: String) async {
        do {
            let login = try await GitHubAPIClient(token: token).fetchAuthenticatedUserLogin()
            currentLogin = login
            state = .signedIn(login: login)
        } catch GitHubAPIError.unauthorized {
            // Token revoked/expired — force re-auth.
            signOut()
            state = .error("Your saved token expired. Please sign in again.")
        } catch {
            // Network hiccup on launch: keep the token, stay signed in.
        }
    }

    // MARK: - Logout

    func signOut() {
        KeychainStore.deleteToken()
        SettingsStore.shared.resetForLogout()
        token = nil
        currentLogin = nil
        state = .signedOut
    }
}
