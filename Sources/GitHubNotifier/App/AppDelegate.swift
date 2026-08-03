import AppKit
import Combine

/// Application delegate for the menu bar agent. Owns the top-level objects and
/// wires poller → system notifications → browser.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var statusItemController: StatusItemController!
    private let systemNotifications = SystemNotificationManager()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar agent: no dock icon, no main menu window.
        NSApp.setActivationPolicy(.accessory)

        statusItemController = StatusItemController(appState: appState)

        systemNotifications.requestAuthorization()
        systemNotifications.onOpenURL = { [weak self] urlString in
            self?.appState.openInBrowser(urlString)
        }

        // New unread notifications → raise banners.
        appState.poller.newNotifications
            .sink { [weak self] fresh in
                self?.systemNotifications.notify(fresh)
            }
            .store(in: &cancellables)

        // Keep launch-at-login registration in sync with the stored preference.
        appState.settings.$autoLaunch
            .sink { desired in
                LoginItemManager.sync(to: desired)
            }
            .store(in: &cancellables)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
