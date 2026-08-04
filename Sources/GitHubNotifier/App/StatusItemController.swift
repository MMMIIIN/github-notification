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
        updateIcon()
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = "GitHub Notifier"
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        let root = RootView().environmentObject(appState)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 380, height: 480)
    }

    private func observeState() {
        // Icon reflects unread count, badge style, and connection status.
        appState.poller.$notifications
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
        appState.poller.$connectionStatus
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
        appState.settings.$badgeStyle
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = BadgeRenderer.image(
            unreadCount: appState.poller.unreadCount,
            style: appState.settings.badgeStyle,
            status: appState.poller.connectionStatus
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
