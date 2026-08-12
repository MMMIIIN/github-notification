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

    /// Notifications that have arrived since the user last opened the dropdown.
    /// This — not GitHub's `unread` flag — drives the menu bar badge: another
    /// GitHub client (mobile app, browser, a script sharing the token) can mark
    /// a thread read within seconds of it arriving, long before this app's 60s
    /// poll runs, which would otherwise hide the notification completely.
    @Published private(set) var newArrivalIDs: Set<String> = []

    /// Emits notifications that arrived since the previous poll, so the
    /// AppDelegate can raise system notification banners for them.
    let newNotifications = PassthroughSubject<[GitHubNotification], Never>()

    private let settings: SettingsStore
    private var token: String?
    private var pollTask: Task<Void, Never>?
    /// Every revision already shown to the user, as `id -> updated_at`.
    private var seenVersions: [String: Date] = [:]
    /// False only until the very first poll for this account completes.
    private var hasSeededBaseline = false
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
        // Restore what the user has already seen so a relaunch neither forgets
        // pending arrivals nor re-announces the whole backlog.
        self.seenVersions = settings.seenNotificationVersions
            .mapValues(Date.init(timeIntervalSince1970:))
        self.newArrivalIDs = settings.newArrivalIDs
        self.hasSeededBaseline = settings.hasSeededNotificationBaseline
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
        // Keep the persisted baseline: the first poll should announce what
        // arrived while the app was closed, but never raise a burst of banners.
        hasEstablishedBaseline = false
        consecutiveFailures = 0
        restart(bypassETagOnFirstPoll: true)
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        token = nil
        notifications = []
        seenVersions = [:]
        newArrivalIDs = []
        // The next account starts fresh and must seed its own baseline.
        hasSeededBaseline = false
        persistSeenState()
        hasEstablishedBaseline = false
        isRefreshing = false
    }

    /// Drops one notification from the badge, because the user acted on it.
    ///
    /// Per-item rather than wholesale: opening a notification launches the
    /// browser, which deactivates this app and closes the popover on its own.
    /// Treating that close as "the whole list has been seen" would silently
    /// clear every other new arrival.
    func acknowledgeArrival(id: String) {
        guard newArrivalIDs.contains(id) else { return }
        DebugLog.log("ack", "acted on id=\(id); \(newArrivalIDs.count - 1) new arrival(s) left")
        newArrivalIDs.remove(id)
        persistSeenState()
    }

    /// Clears the badge outright — only ever from an explicit "mark all as seen".
    func acknowledgeAllArrivals() {
        guard !newArrivalIDs.isEmpty else { return }
        DebugLog.log("ack", "marked all \(newArrivalIDs.count) new arrival(s) as seen")
        newArrivalIDs = []
        persistSeenState()
    }

    private func persistSeenState() {
        settings.seenNotificationVersions = seenVersions.mapValues(\.timeIntervalSince1970)
        settings.newArrivalIDs = newArrivalIDs
        settings.hasSeededNotificationBaseline = hasSeededBaseline
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
        newArrivalIDs.remove(id)
        persistSeenState()
    }

    /// Hides every currently visible item locally, including unread items.
    /// Nothing is changed on GitHub.
    func dismissAllNotifications() {
        notifications.forEach(settings.dismiss)
        notifications = []
        newArrivalIDs = []
        persistSeenState()
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
        seenVersions[item.id] = item.updatedAt
        newArrivalIDs.insert(item.id)
        persistSeenState()
        newNotifications.send([item])
    }

    func setNotificationUnreadState(id: String, isUnread: Bool) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        var updated = notifications
        updated[index].isUnread = isUnread
        notifications = updated
        seenVersions[id] = notifications[index].updatedAt
        if !isUnread {
            // Acting on a notification in this app means the user has seen it.
            newArrivalIDs.remove(id)
        }
        persistSeenState()
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

            DebugLog.log("poll", result.notModified
                ? "304 not modified (etag unchanged)"
                : "200 received=\(result.notifications.count) unread=\(result.notifications.filter(\.isUnread).count)")

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

    /// Applies a poll result: hides locally dismissed revisions, publishes the
    /// list, and works out what is new to the user.
    ///
    /// Internal rather than private so the delivery signal can be tested without
    /// a network round-trip.
    func applyFiltered(_ incoming: [GitHubNotification], suppressNewNotifications: Bool) {
        let filtered = incoming
            .filter { !settings.isDismissed($0) }
            .sorted { $0.updatedAt > $1.updatedAt }

        let trimmed = Array(filtered.prefix(recentLimit))

        logDelivery(incoming: incoming, filtered: filtered, trimmed: trimmed)

        // Newness is judged against every revision already shown, read or not.
        // A thread marked read elsewhere seconds after it arrived is still the
        // first time *this user* has been told about it.
        let isSeedingBaseline = !hasSeededBaseline
        hasSeededBaseline = true
        let fresh = Self.newArrivals(in: trimmed, seenVersions: seenVersions)
        seenVersions = Dictionary(
            uniqueKeysWithValues: trimmed.map { ($0.id, $0.updatedAt) }
        )

        notifications = trimmed

        if isSeedingBaseline {
            // A fresh install (or a first run after sign-out) should not light
            // up the badge with a backlog the user never asked about.
            newArrivalIDs = []
        } else {
            newArrivalIDs.formUnion(fresh.map(\.id))
            // Drop anything no longer listed, so the badge can never outlive
            // the notifications it is counting.
            let visible = Set(trimmed.map(\.id))
            newArrivalIDs.formIntersection(visible)
        }
        persistSeenState()

        DebugLog.log("apply", "unreadInList=\(trimmed.filter(\.isUnread).count) "
            + "fresh=\(fresh.count) badge=\(newArrivalIDs.count) "
            + "banners=\(suppressNewNotifications || isSeedingBaseline ? "suppressed(baseline)" : "\(fresh.count)")")

        if !suppressNewNotifications, !isSeedingBaseline, !fresh.isEmpty {
            newNotifications.send(fresh)
        }
    }

    /// Records what each poll did to every notification, so an item that arrives
    /// already-read — or gets dropped by the dismissed-versions filter — is
    /// visible in the log instead of silently vanishing before the badge.
    private func logDelivery(
        incoming: [GitHubNotification],
        filtered: [GitHubNotification],
        trimmed: [GitHubNotification]
    ) {
        let dropped = incoming.count - filtered.count
        DebugLog.log("filter", "incoming=\(incoming.count) hiddenByDismiss=\(dropped) "
            + "kept=\(trimmed.count) unreadIncoming=\(incoming.filter(\.isUnread).count)")

        let previous = Dictionary(uniqueKeysWithValues: notifications.map { ($0.id, $0) })
        for item in trimmed {
            guard let old = previous[item.id] else {
                DebugLog.log("arrival", "NEW id=\(item.id) unread=\(item.isUnread) "
                    + "updated=\(item.updatedAt) type=\(item.notificationType) "
                    + "title=\(item.title.prefix(48))")
                continue
            }
            if old.updatedAt != item.updatedAt {
                DebugLog.log("arrival", "UPDATED id=\(item.id) unread=\(item.isUnread) "
                    + "\(old.updatedAt) -> \(item.updatedAt) title=\(item.title.prefix(48))")
            }
            if old.isUnread != item.isUnread {
                DebugLog.log("readstate", "id=\(item.id) unread \(old.isUnread) -> \(item.isUnread) "
                    + "(changed outside a tap in this app unless a 'markread' line precedes it)")
            }
        }
    }

    var unreadCount: Int {
        notifications.filter(\.isUnread).count
    }

    /// How many notifications the user has not looked at yet — what the menu
    /// bar badge shows.
    var newArrivalCount: Int {
        newArrivalIDs.count
    }

    /// A GitHub notification is a thread, so new activity commonly keeps the
    /// same ID and advances `updated_at`. Compare both fields.
    ///
    /// Deliberately independent of `isUnread`: the read flag is shared across
    /// every GitHub client, so relying on it makes delivery depend on whether
    /// something else got there first.
    static func newArrivals(
        in current: [GitHubNotification],
        seenVersions: [String: Date]
    ) -> [GitHubNotification] {
        current.filter { item in
            guard let seenDate = seenVersions[item.id] else { return true }
            return item.updatedAt > seenDate
        }
    }
}
