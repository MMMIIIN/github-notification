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

        // Even though an agent app shows no menu bar, installing an Edit menu is
        // what enables the standard Cut/Copy/Paste/Select-All key equivalents in
        // text fields (⌘V routes through the Edit menu's paste: item).
        NSApp.mainMenu = Self.makeMainMenu()

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

    /// Builds a minimal main menu whose Edit submenu enables the system editing
    /// shortcuts (⌘X/⌘C/⌘V/⌘A) for text fields inside the popover.
    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // Application menu (holds Quit).
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit GitHub Notifier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu (holds the editing shortcuts).
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        return mainMenu
    }
}
