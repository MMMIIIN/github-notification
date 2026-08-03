import Foundation
import Combine

/// Coordinates authentication: OAuth (primary) and PAT (fallback), token
/// persistence in the Keychain, and the app's high-level auth state.
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
    /// While an OAuth Device Flow is in progress, the code the user must confirm.
    @Published var deviceCodePrompt: DeviceCodePrompt?

    var isOAuthAvailable: Bool { AppConfig.isOAuthAvailable }

    init() {
        // Restore a previous session from the Keychain on launch.
        if let saved = KeychainStore.loadToken() {
            self.token = saved
            self.state = .signedIn(login: "…")
            Task { await self.validateRestoredToken(saved) }
        }
    }

    // MARK: - OAuth

    func signInWithOAuth() async {
        guard let service = OAuthService() else {
            state = .error(OAuthError.notConfigured.errorDescription ?? "OAuth not configured")
            return
        }
        state = .signingIn
        deviceCodePrompt = nil
        do {
            let token = try await service.signIn { [weak self] prompt in
                self?.deviceCodePrompt = prompt
            }
            deviceCodePrompt = nil
            try await finishSignIn(token: token, method: .oauth)
        } catch {
            deviceCodePrompt = nil
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - PAT

    func signInWithPAT(_ pat: String) async {
        let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .error("Please enter a token.")
            return
        }
        state = .signingIn
        do {
            try await finishSignIn(token: trimmed, method: .pat)
        } catch GitHubAPIError.unauthorized {
            state = .error("That token was rejected. Check its scopes (needs notifications, repo).")
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Shared sign-in completion

    private func finishSignIn(token: String, method: AuthMethod) async throws {
        // Validate by resolving the user's login; this also confirms scopes work.
        let login = try await GitHubAPIClient(token: token).fetchAuthenticatedUserLogin()
        KeychainStore.saveToken(token)
        SettingsStore.shared.authMethod = method
        self.token = token
        self.state = .signedIn(login: login)
    }

    private func validateRestoredToken(_ token: String) async {
        do {
            let login = try await GitHubAPIClient(token: token).fetchAuthenticatedUserLogin()
            state = .signedIn(login: login)
        } catch GitHubAPIError.unauthorized {
            // Token revoked/expired — force re-auth.
            signOut()
            state = .error("Your saved sign-in expired. Please sign in again.")
        } catch {
            // Network hiccup on launch: keep the token, stay signed in.
        }
    }

    // MARK: - Logout

    func signOut() {
        KeychainStore.deleteToken()
        SettingsStore.shared.resetForLogout()
        token = nil
        state = .signedOut
    }
}
