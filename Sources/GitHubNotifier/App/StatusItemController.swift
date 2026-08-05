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
        button.imagePosition = .imageOnly
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
        Publishers.CombineLatest3(
            appState.poller.$notifications,
            appState.settings.$badgeStyle,
            appState.poller.$connectionStatus
        )
            .sink { [weak self] notifications, style, status in
                self?.updateIcon(
                    unreadCount: notifications.filter(\.isUnread).count,
                    style: style,
                    status: status
                )
            }
            .store(in: &cancellables)
    }

    // MARK: - Icon

    private func updateIcon(unreadCount: Int, style: BadgeStyle, status: ConnectionStatus) {
        guard let button = statusItem.button else { return }
        button.image = BadgeRenderer.image(
            unreadCount: unreadCount,
            style: style,
            status: status
        )
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
