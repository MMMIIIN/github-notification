import Foundation
import Combine

/// User preferences and lightweight cache, persisted in UserDefaults.
/// No database — preferences and lightweight cache are all the local state we
/// need beyond the Keychain token.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let subscribedRepos = "subscribedRepositories"
        static let badgeStyle = "badgeStyle"
        static let autoLaunch = "autoLaunch"
        static let authMethod = "authMethod"
        static let etag = "notificationsETag"
        static let onboarded = "hasCompletedOnboarding"
        static let dismissedNotificationIDs = "dismissedNotificationIDs"
    }

    /// Full names ("org/repo") the user chose to watch.
    @Published var subscribedRepositories: [String] {
        didSet { defaults.set(subscribedRepositories, forKey: Keys.subscribedRepos) }
    }

    @Published var badgeStyle: BadgeStyle {
        didSet { defaults.set(badgeStyle.rawValue, forKey: Keys.badgeStyle) }
    }

    @Published var autoLaunch: Bool {
        didSet { defaults.set(autoLaunch, forKey: Keys.autoLaunch) }
    }

    /// True once the user has passed the mandatory repo-subscription onboarding.
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) }
    }

    /// Read notifications the user explicitly removed from the local list.
    @Published var dismissedNotificationIDs: Set<String> {
        didSet { defaults.set(Array(dismissedNotificationIDs), forKey: Keys.dismissedNotificationIDs) }
    }

    var authMethod: AuthMethod? {
        get {
            guard let raw = defaults.string(forKey: Keys.authMethod) else { return nil }
            return AuthMethod(rawValue: raw)
        }
        set { defaults.set(newValue?.rawValue, forKey: Keys.authMethod) }
    }

    /// ETag from the last `/notifications` response, for conditional requests.
    var notificationsETag: String? {
        get { defaults.string(forKey: Keys.etag) }
        set { defaults.set(newValue, forKey: Keys.etag) }
    }

    private init() {
        self.subscribedRepositories = defaults.stringArray(forKey: Keys.subscribedRepos) ?? []
        self.badgeStyle = BadgeStyle(rawValue: defaults.string(forKey: Keys.badgeStyle) ?? "") ?? .number
        self.autoLaunch = defaults.bool(forKey: Keys.autoLaunch)
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
        self.dismissedNotificationIDs = Set(defaults.stringArray(forKey: Keys.dismissedNotificationIDs) ?? [])
    }

    /// Clears preferences on logout (token is cleared separately via KeychainStore).
    func resetForLogout() {
        subscribedRepositories = []
        hasCompletedOnboarding = false
        authMethod = nil
        notificationsETag = nil
        dismissedNotificationIDs = []
    }
}
