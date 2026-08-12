import AppKit
import SwiftUI
import Combine

/// Owns the `NSStatusItem` (menu bar icon) and the `NSPopover` that hosts the
/// SwiftUI dropdown. Keeps the icon badge in sync with poller state.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let appState: AppState
    private var cancellables: Set<AnyCancellable> = []
    private var eventMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        configurePopover()
        observeState()
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeft
        button.target = self
        button.action = #selector(handleClick)
        // Receive both left- and right-clicks so we can show a context menu.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "GitHub Notifier"
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if isRightClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        if popover.isShown { closePopover() }

        let menu = NSMenu()
        let header = NSMenuItem(title: "GitHub Notifier", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit GitHub Notifier", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Pop up at the button without assigning statusItem.menu, so normal
        // left-click behavior is preserved.
        let origin = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: button)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func refreshNow() {
        appState.poller.refreshNow()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        let root = RootView().environmentObject(appState)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 380, height: 480)
    }

    private func observeState() {
        // @Published emits in willSet, so render from the values delivered by
        // the publishers instead of reading properties that are still stale.
        // The badge counts arrivals the user hasn't looked at, not GitHub's
        // unread flag — that flag is shared with every other GitHub client and
        // is routinely cleared before this app's poll ever sees the thread.
        Publishers.CombineLatest3(
            appState.poller.$newArrivalIDs,
            appState.settings.$badgeStyle,
            appState.poller.$connectionStatus
        )
            .sink { [weak self] newArrivalIDs, style, status in
                self?.updateIcon(
                    newCount: newArrivalIDs.count,
                    style: style,
                    status: status
                )
            }
            .store(in: &cancellables)
    }

    // MARK: - Icon

    private func updateIcon(newCount: Int, style: BadgeStyle, status: ConnectionStatus) {
        guard let button = statusItem.button else { return }
        // Keep the bell as a standard template image and render unread state as
        // native status-item text. Composite bitmap badges were intermittently
        // clipped or ignored by the menu bar.
        button.image = BadgeRenderer.image(
            unreadCount: 0,
            style: style,
            status: status
        )
        let badgeText: String
        if status != .connected || newCount == 0 {
            badgeText = ""
        } else {
            switch style {
            case .number: badgeText = newCount > 99 ? "99+" : String(newCount)
            case .dot: badgeText = "●"
            }
        }
        button.attributedTitle = NSAttributedString(
            string: badgeText,
            attributes: [
                .font: NSFont.systemFont(ofSize: style == .dot ? 8 : 11, weight: .semibold),
                .foregroundColor: NSColor.systemRed
            ]
        )
        button.toolTip = newCount > 0
            ? "GitHub Notifier — \(newCount) new"
            : "GitHub Notifier"

        DebugLog.log("badge", "newCount=\(newCount) status=\(status) "
            + "badgeText=\"\(badgeText)\"")
    }

    // MARK: - Popover toggle

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Agent apps aren't active by default; activate so the popover's text
        // fields receive keyboard input (typing, ⌘V paste, etc.).
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)

        // Close when the user clicks outside the popover.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// Programmatically opens the popover (used when a banner is clicked).
    func openPopover() {
        if !popover.isShown { showPopover() }
    }
}
