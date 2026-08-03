import Foundation
import AppKit

enum OAuthError: Error, LocalizedError {
    case notConfigured
    case denied
    case expired
    case network(String)
    case deviceFlowDisabled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OAuth isn't configured. Sign in with a token instead."
        case .denied:
            return "Authorization was denied on GitHub."
        case .expired:
            return "The code expired before you authorized. Please try again."
        case .deviceFlowDisabled:
            return "This OAuth App doesn't have Device Flow enabled. Enable it in the app settings on GitHub."
        case .network(let detail):
            return "Sign-in failed: \(detail)"
        }
    }
}

/// The pending device-flow challenge shown to the user while they authorize.
struct DeviceCodePrompt: Equatable {
    let userCode: String        // e.g. "WDJB-MJHT"
    let verificationURI: String // https://github.com/login/device
}

/// Implements the GitHub **OAuth Device Flow**. This needs only the (public)
/// client id — no client secret, so there's no backend and nothing secret to
/// distribute to teammates.
///
/// Flow:
///  1. POST /login/device/code  → device_code + user_code + verification_uri
///  2. Copy the user_code, open the verification page in the browser.
///  3. Poll /login/oauth/access_token until the user authorizes.
final class OAuthService {
    private let clientID: String

    init?(clientID: String? = AppConfig.clientID) {
        guard let clientID, !clientID.isEmpty else { return nil }
        self.clientID = clientID
    }

    /// Runs the device flow. `onCodeReady` fires once the user code is available
    /// (so the UI can display it); this service also copies it to the clipboard
    /// and opens the verification page automatically.
    func signIn(onCodeReady: @escaping @MainActor (DeviceCodePrompt) -> Void) async throws -> String {
        let device = try await requestDeviceCode()

        let prompt = DeviceCodePrompt(userCode: device.userCode, verificationURI: device.verificationURI)
        await MainActor.run {
            // Make authorizing as low-friction as possible: code on the clipboard,
            // verification page already open.
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(device.userCode, forType: .string)
            if let url = URL(string: device.verificationURI) {
                NSWorkspace.shared.open(url)
            }
            onCodeReady(prompt)
        }

        return try await pollForToken(deviceCode: device.deviceCode, interval: device.interval, expiresIn: device.expiresIn)
    }

    // MARK: - Step 1: device code

    private struct DeviceCodeResponse {
        let deviceCode: String
        let userCode: String
        let verificationURI: String
        let interval: Int
        let expiresIn: Int
    }

    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientID,
            "scope": AppConfig.scopes
        ])

        let (data, response) = try await dataTask(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OAuthError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        struct Raw: Decodable {
            let device_code: String?
            let user_code: String?
            let verification_uri: String?
            let interval: Int?
            let expires_in: Int?
            let error: String?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        if raw.error == "device_flow_disabled" { throw OAuthError.deviceFlowDisabled }
        guard let deviceCode = raw.device_code,
              let userCode = raw.user_code,
              let uri = raw.verification_uri else {
            throw OAuthError.network(raw.error ?? "Malformed device code response")
        }
        return DeviceCodeResponse(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: uri,
            interval: raw.interval ?? 5,
            expiresIn: raw.expires_in ?? 900
        )
    }

    // MARK: - Step 3: poll for the token

    private func pollForToken(deviceCode: String, interval: Int, expiresIn: Int) async throws -> String {
        var pollInterval = max(interval, 5)
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formBody([
                "client_id": clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])

            let (data, _) = try await dataTask(request)
            struct Raw: Decodable {
                let access_token: String?
                let error: String?
            }
            let raw = try JSONDecoder().decode(Raw.self, from: data)

            if let token = raw.access_token { return token }

            switch raw.error {
            case "authorization_pending":
                continue                          // user hasn't finished yet
            case "slow_down":
                pollInterval += 5                 // back off as instructed
            case "expired_token":
                throw OAuthError.expired
            case "access_denied":
                throw OAuthError.denied
            default:
                throw OAuthError.network(raw.error ?? "Unknown polling error")
            }
        }
        throw OAuthError.expired
    }

    // MARK: - Helpers

    private func formBody(_ params: [String: String]) -> Data {
        params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private func dataTask(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw OAuthError.network(error.localizedDescription)
        }
    }
}

private extension CharacterSet {
    /// Query-value-safe set (excludes `&`, `=`, `+`, etc.).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
