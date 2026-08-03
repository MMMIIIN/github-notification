import Foundation
import UserNotifications

/// Posts macOS notification-center banners for newly arrived GitHub
/// notifications and opens the corresponding page in the browser on click.
@MainActor
final class SystemNotificationManager: NSObject {
    /// Called with a URL string when the user clicks a banner.
    var onOpenURL: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private nonisolated static let urlKey = "targetURL"

    override init() {
        super.init()
        center.delegate = self
    }

    /// Requests banner/sound authorization once.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Raises a banner per newly-arrived unread notification.
    func notify(_ notifications: [GitHubNotification]) {
        for item in notifications {
            let content = UNMutableNotificationContent()
            content.title = item.notificationType.label
            content.subtitle = item.repositoryName
            content.body = item.title
            content.sound = .default
            content.userInfo = [Self.urlKey: item.url]

            let request = UNNotificationRequest(
                identifier: item.id,
                content: content,
                trigger: nil   // deliver immediately
            )
            center.add(request)
        }
    }
}

extension SystemNotificationManager: UNUserNotificationCenterDelegate {
    // Show banners even while the app (agent) is frontmost-ish.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Banner click → open the GitHub page in the browser.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo[Self.urlKey] as? String {
            Task { @MainActor [weak self] in
                self?.onOpenURL?(urlString)
            }
        }
        completionHandler()
    }
}
