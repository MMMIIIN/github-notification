import Foundation
import Combine
import Network

/// Drives the ~60s polling loop against the GitHub Notifications API, applies the
/// GitHub's notification threads, and publishes results for the UI and menu bar.
///
/// Read-only: it never mutates GitHub state. Read/unread comes straight from the
/// API, so marking something read on github.com is reflected on the next poll.
@MainActor
final class NotificationPoller: ObservableObject {
    /// Recent notifications (read + unread), newest first, already filtered.
    @Published private(set) var notifications: [GitHubNotification] = []
    @Published private(set) var connectionStatus: ConnectionStatus = .connected
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    /// Emits the set of newly-arrived unread notifications each poll, so the
    /// AppDelegate can raise system notification banners for them.
    let newNotifications = PassthroughSubject<[GitHubNotification], Never>()

    private let settings: SettingsStore
    private var token: String?
    private var pollTask: Task<Void, Never>?
    private var seenUnreadVersions: [String: Date] = [:]
    private var hasEstablishedBaseline = false
    private var activeRefreshID: UUID?
    private var consecutiveFailures = 0
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.ghnotifier.network-monitor")
    private var networkAvailable = true

    private let defaultInterval: TimeInterval = 60
    private let maxBackoff: TimeInterval = 300
    /// How many recent items the dropdown keeps.
    private let recentLimit = 50

    init(settings: SettingsStore = .shared) {
        self.settings = settings
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handleNetworkPathChange(available: available)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    deinit {
        pathMonitor.cancel()
    }

    // MARK: - Lifecycle

    func start(token: String) {
        self.token = token
        seenUnreadVersions = [:]    // first poll seeds the baseline, no banner spam
        hasEstablishedBaseline = false
        consecutiveFailures = 0
        restart(bypassETagOnFirstPoll: true)
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        token = nil
        notifications = []
        seenUnreadVersions = [:]
        hasEstablishedBaseline = false
        isRefreshing = false
    }

    /// Forces an immediate poll.
    func refreshNow() {
        restart(bypassETagOnFirstPoll: true)
    }

    /// Hides a read item locally; the persisted id prevents it returning on the
    /// next poll. This does not delete the GitHub notification.
    func dismissReadNotification(id: String) {
        guard let item = notifications.first(where: { $0.id == id }), !item.isUnread else { return }
        settings.dismiss(item)
        notifications.removeAll { $0.id == id }
    }

    /// Hides every currently visible item locally, including unread items.
    /// Nothing is changed on GitHub.
    func dismissAllNotifications() {
        notifications.forEach(settings.dismiss)
        notifications = []
    }

    /// Injects one in-memory notification through the same publisher used by a
    /// real poll. This exercises the list, badge, banner, and sound without
    /// changing anything on GitHub.
    func sendTestNotification() {
        let repository = "GitHubNotifier/Test"
        let item = GitHubNotification(
            id: "test-\(UUID().uuidString)",
            repositoryName: repository,
            organizationName: repository.split(separator: "/").first.map(String.init) ?? "GitHubNotifier",
            notificationType: .reviewRequest,
            title: "Test notification — review requested",
            number: nil,
            author: "github-notifier",
            url: "https://github.com/notifications",
            commentAPIURL: nil,
            isPullRequest: true,
            isUnread: true,
            updatedAt: Date()
        )
        notifications.insert(item, at: 0)
        seenUnreadVersions[item.id] = item.updatedAt
        newNotifications.send([item])
    }

    func setNotificationUnreadState(id: String, isUnread: Bool) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        var updated = notifications
        updated[index].isUnread = isUnread
        notifications = updated
        if isUnread {
            seenUnreadVersions[id] = notifications[index].updatedAt
        } else {
            seenUnreadVersions[id] = nil
        }
    }

    private func restart(bypassETagOnFirstPoll: Bool = false) {
        pollTask?.cancel()
        guard token != nil else { return }
        pollTask = Task { [weak self] in
            await self?.loop(bypassETagOnFirstPoll: bypassETagOnFirstPoll)
        }
    }

    private func handleNetworkPathChange(available: Bool) {
        let wasAvailable = networkAvailable
        networkAvailable = available

        if !available {
            connectionStatus = .networkError
            pollTask?.cancel()
            pollTask = nil
        } else if !wasAvailable {
            // Do not wait for the old exponential backoff. Verify GitHub
            // connectivity immediately; pollOnce clears the warning on success.
            consecutiveFailures = 0
            restart(bypassETagOnFirstPoll: true)
        }
    }

    // MARK: - Loop

    private func loop(bypassETagOnFirstPoll: Bool) async {
        var bypassETag = bypassETagOnFirstPoll
        while !Task.isCancelled {
            let interval = await pollOnce(bypassETag: bypassETag)
            bypassETag = false
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                break   // cancelled
            }
        }
    }

    /// Performs one poll; returns the number of seconds to wait before the next.
    private func pollOnce(bypassETag: Bool) async -> TimeInterval {
        guard let token else { return defaultInterval }
        let client = GitHubAPIClient(token: token)
        let refreshID = UUID()
        activeRefreshID = refreshID
        isRefreshing = true
        defer {
            if activeRefreshID == refreshID {
                activeRefreshID = nil
                isRefreshing = false
            }
        }
        do {
            let result = try await client.pollNotifications(
                etag: bypassETag ? nil : settings.notificationsETag
            )
            consecutiveFailures = 0
            connectionStatus = .connected
            lastUpdated = Date()

            if !result.notModified {
                settings.notificationsETag = result.etag
                applyFiltered(
                    result.notifications,
                    suppressNewNotifications: !hasEstablishedBaseline
                )
            }
            hasEstablishedBaseline = true

            let advised = result.pollIntervalSeconds.map(TimeInterval.init) ?? defaultInterval
            return max(advised, defaultInterval)
        } catch GitHubAPIError.unauthorized {
            connectionStatus = .authError
            return defaultInterval
        } catch {
            // A manual refresh or network transition deliberately cancels the
            // previous request. Do not surface that as a connection failure.
            if Task.isCancelled { return defaultInterval }
            // Network or transient error: keep the last data, back off, retry silently.
            consecutiveFailures += 1
            connectionStatus = .networkError
            let backoff = min(defaultInterval * Double(consecutiveFailures), maxBackoff)
            return backoff
        }
    }

    // MARK: - Filtering & diffing

    private func applyFiltered(_ incoming: [GitHubNotification], suppressNewNotifications: Bool) {
        let filtered = incoming
            .filter { !settings.isDismissed($0) }
            .sorted { $0.updatedAt > $1.updatedAt }

        let trimmed = Array(filtered.prefix(recentLimit))

        // Detect newly-arrived unread items for banners.
        let currentUnread = trimmed.filter(\.isUnread)
        let fresh = Self.newUnreadNotifications(
            in: currentUnread,
            seenVersions: seenUnreadVersions
        )
        seenUnreadVersions = Dictionary(
            uniqueKeysWithValues: currentUnread.map { ($0.id, $0.updatedAt) }
        )

        notifications = trimmed

        if !suppressNewNotifications, !fresh.isEmpty {
            newNotifications.send(fresh)
        }
    }

    var unreadCount: Int {
        notifications.filter(\.isUnread).count
    }

    /// A GitHub notification is a thread, so new activity commonly keeps the
    /// same ID and advances `updated_at`. Compare both fields.
    static func newUnreadNotifications(
        in current: [GitHubNotification],
        seenVersions: [String: Date]
    ) -> [GitHubNotification] {
        current.filter { item in
            guard let seenDate = seenVersions[item.id] else { return true }
            return item.updatedAt > seenDate
        }
    }
}
