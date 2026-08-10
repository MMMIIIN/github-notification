import Foundation
import Combine

/// User preferences and lightweight cache, persisted in UserDefaults.
/// No database — preferences and lightweight cache are all the local state we
/// need beyond the Keychain token.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let legacySubscribedRepos = "subscribedRepositories"
        static let legacyOnboarded = "hasCompletedOnboarding"
        static let badgeStyle = "badgeStyle"
        static let autoLaunch = "autoLaunch"
        static let authMethod = "authMethod"
        static let etag = "notificationsETag"
        static let legacyDismissedNotificationIDs = "dismissedNotificationIDs"
        static let dismissedNotificationVersions = "dismissedNotificationVersions"
    }

    @Published var badgeStyle: BadgeStyle {
        didSet { defaults.set(badgeStyle.rawValue, forKey: Keys.badgeStyle) }
    }

    @Published var autoLaunch: Bool {
        didSet { defaults.set(autoLaunch, forKey: Keys.autoLaunch) }
    }

    /// Exact notification revisions hidden locally. GitHub reuses a thread ID
    /// when new activity arrives, so the update timestamp must be part of the key.
    @Published private(set) var dismissedNotificationVersions: [String: TimeInterval] {
        didSet { defaults.set(dismissedNotificationVersions, forKey: Keys.dismissedNotificationVersions) }
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
        // Repository filtering was removed. If this is an upgraded install,
        // discard the old filter and ETag so the first poll fetches the full list.
        if defaults.object(forKey: Keys.legacySubscribedRepos) != nil ||
            defaults.object(forKey: Keys.legacyOnboarded) != nil {
            defaults.removeObject(forKey: Keys.legacySubscribedRepos)
            defaults.removeObject(forKey: Keys.legacyOnboarded)
            defaults.removeObject(forKey: Keys.etag)
        }
        // Old dismissed IDs hid a thread forever, including future comments.
        defaults.removeObject(forKey: Keys.legacyDismissedNotificationIDs)
        self.badgeStyle = BadgeStyle(rawValue: defaults.string(forKey: Keys.badgeStyle) ?? "") ?? .number
        self.autoLaunch = defaults.bool(forKey: Keys.autoLaunch)
        self.dismissedNotificationVersions = defaults.dictionary(forKey: Keys.dismissedNotificationVersions) as? [String: TimeInterval] ?? [:]
    }

    func dismiss(_ notification: GitHubNotification) {
        dismissedNotificationVersions[notification.id] = notification.updatedAt.timeIntervalSince1970
    }

    func isDismissed(_ notification: GitHubNotification) -> Bool {
        dismissedNotificationVersions[notification.id] == notification.updatedAt.timeIntervalSince1970
    }

    /// Clears preferences on logout (token is cleared separately via KeychainStore).
    func resetForLogout() {
        authMethod = nil
        notificationsETag = nil
        dismissedNotificationVersions = [:]
    }
}
