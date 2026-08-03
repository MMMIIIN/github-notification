import Foundation

/// OAuth application configuration.
///
/// For this MVP there is **no backend**: the GitHub OAuth App's client id and
/// secret are read from a local JSON file that lives outside the repo:
///
///   ~/Library/Application Support/GitHubNotifier/config.json
///
///   {
///     "clientID": "Iv1.xxxxxxxx",
///     "clientSecret": "xxxxxxxxxxxxxxxxxxxx",
///     "callbackScheme": "ghnotifier"
///   }
///
/// If the file is absent or incomplete, OAuth is unavailable and the UI falls
/// back to Personal Access Token sign-in (which needs no client secret).
struct AppConfig: Codable {
    let clientID: String
    let clientSecret: String
    let callbackScheme: String

    /// OAuth callback URL registered in the GitHub OAuth App settings.
    var callbackURL: String { "\(callbackScheme)://oauth-callback" }

    /// Scopes required for reading notifications on private repositories.
    static let scopes = "notifications,repo,read:org"

    static var configDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GitHubNotifier", isDirectory: true)
    }

    static var configFileURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    /// Loads OAuth config from disk, or nil if unavailable/invalid.
    static func load() -> AppConfig? {
        guard let data = try? Data(contentsOf: configFileURL) else { return nil }
        guard let config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return nil }
        guard !config.clientID.isEmpty, !config.clientSecret.isEmpty else { return nil }
        return config
    }

    /// Whether OAuth sign-in can be offered.
    static var isOAuthAvailable: Bool { load() != nil }
}
