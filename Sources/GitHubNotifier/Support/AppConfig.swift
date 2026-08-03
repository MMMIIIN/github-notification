import Foundation

/// OAuth configuration for the **Device Flow**.
///
/// Device Flow needs only the OAuth App's **client id**, which is *not* secret —
/// so there's no client secret, no backend, and nothing sensitive to distribute.
/// Teammates just install the app and sign in.
///
/// The client id is resolved in this order:
///   1. `~/Library/Application Support/GitHubNotifier/config.json`  → `{ "clientID": "Iv1.xxxx" }`
///   2. The compiled-in `bundledClientID` below (fill this once to distribute to a team).
///
/// If neither is set, OAuth is unavailable and the UI falls back to a Personal
/// Access Token.
enum AppConfig {
    /// Fill this in to bake the (public) client id into team builds. Leave empty
    /// to require a local config.json instead.
    static let bundledClientID = ""

    /// Scopes required for reading notifications on private repositories.
    static let scopes = "notifications repo read:org"

    static var configDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GitHubNotifier", isDirectory: true)
    }

    static var configFileURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    /// The effective client id, or nil if OAuth isn't configured.
    static var clientID: String? {
        if let fromFile = clientIDFromFile(), !fromFile.isEmpty { return fromFile }
        if !bundledClientID.isEmpty { return bundledClientID }
        return nil
    }

    /// Whether OAuth (Device Flow) sign-in can be offered.
    static var isOAuthAvailable: Bool { clientID != nil }

    private static func clientIDFromFile() -> String? {
        guard let data = try? Data(contentsOf: configFileURL) else { return nil }
        struct File: Decodable { let clientID: String? }
        return (try? JSONDecoder().decode(File.self, from: data))?.clientID
    }
}
