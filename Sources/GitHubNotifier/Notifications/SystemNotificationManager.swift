import Foundation
import UserNotifications

/// Posts macOS notification-center banners for newly arrived GitHub
/// notifications and opens the corresponding page in the browser on click.
@MainActor
final class SystemNotificationManager: NSObject {
    /// Called with (notification id, fallback URL) when a banner is clicked.
    var onOpen: ((String, String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private nonisolated static let urlKey = "targetURL"
    private nonisolated static let idKey = "notificationID"

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
            content.userInfo = [
                Self.idKey: item.id,
                Self.urlKey: item.url
            ]

            let request = UNNotificationRequest(
                // GitHub reuses a thread ID when another comment arrives. A
                // revision-specific identifier prevents Notification Center
                // from replacing/suppressing that later banner.
                identifier: "\(item.id)-\(Int(item.updatedAt.timeIntervalSince1970))",
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
        if let id = userInfo[Self.idKey] as? String,
           let urlString = userInfo[Self.urlKey] as? String {
            Task { @MainActor [weak self] in
                self?.onOpen?(id, urlString)
            }
        }
        completionHandler()
    }
}
