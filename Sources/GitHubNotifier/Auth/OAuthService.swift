import Foundation
import AuthenticationServices
import AppKit

enum OAuthError: Error, LocalizedError {
    case notConfigured
    case cancelled
    case stateMismatch
    case noCode
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OAuth is not configured. Add config.json or sign in with a token."
        case .cancelled:
            return "Sign-in was cancelled."
        case .stateMismatch:
            return "Security check failed (state mismatch). Please try again."
        case .noCode:
            return "GitHub did not return an authorization code."
        case .tokenExchangeFailed(let detail):
            return "Could not complete sign-in: \(detail)"
        }
    }
}

/// Implements the GitHub OAuth web application flow using
/// `ASWebAuthenticationSession`: the system opens GitHub in a browser sheet,
/// the user approves, and GitHub redirects back to our custom scheme.
final class OAuthService: NSObject {
    private let config: AppConfig

    init?(config: AppConfig? = AppConfig.load()) {
        guard let config else { return nil }
        self.config = config
    }

    /// Runs the full browser flow and returns an access token.
    @MainActor
    func signIn() async throws -> String {
        let state = UUID().uuidString
        let authURL = buildAuthorizeURL(state: state)

        let callbackURL = try await presentAuthSession(url: authURL)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw OAuthError.noCode
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw OAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.noCode
        }
        return try await exchangeCodeForToken(code)
    }

    // MARK: - Steps

    private func buildAuthorizeURL(state: String) -> URL {
        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.callbackURL),
            URLQueryItem(name: "scope", value: AppConfig.scopes),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }

    @MainActor
    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: config.callbackScheme
            ) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: OAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.tokenExchangeFailed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthError.noCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: OAuthError.tokenExchangeFailed("Could not start authentication session"))
            }
        }
    }

    private func exchangeCodeForToken(_ code: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "code": code,
            "redirect_uri": config.callbackURL
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OAuthError.tokenExchangeFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        struct TokenResponse: Decodable {
            let access_token: String?
            let error: String?
            let error_description: String?
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let token = decoded.access_token { return token }
        throw OAuthError.tokenExchangeFailed(decoded.error_description ?? decoded.error ?? "Unknown error")
    }
}

// MARK: - Presentation anchor

extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Menu bar agents have no main window; use the key window if present,
        // otherwise a transient anchor window keeps AppKit happy.
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            return window
        }
        return OAuthService.anchorWindow
    }

    private static let anchorWindow: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.alphaValue = 0
        return window
    }()
}
