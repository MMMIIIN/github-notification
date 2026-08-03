import Foundation
import Combine

/// Drives the ~60s polling loop against the GitHub Notifications API, applies the
/// user's repo/type filters, and publishes results for the UI and menu bar.
///
/// Read-only: it never mutates GitHub state. Read/unread comes straight from the
/// API, so marking something read on github.com is reflected on the next poll.
@MainActor
final class NotificationPoller: ObservableObject {
    /// Recent notifications (read + unread), newest first, already filtered.
    @Published private(set) var notifications: [GitHubNotification] = []
    @Published private(set) var connectionStatus: ConnectionStatus = .connected
    @Published private(set) var lastUpdated: Date?

    /// Emits the set of newly-arrived unread notifications each poll, so the
    /// AppDelegate can raise system notification banners for them.
    let newNotifications = PassthroughSubject<[GitHubNotification], Never>()

    private let settings: SettingsStore
    private var token: String?
    private var pollTask: Task<Void, Never>?
    private var seenUnreadIDs: Set<String> = []
    private var consecutiveFailures = 0

    private let defaultInterval: TimeInterval = 60
    private let maxBackoff: TimeInterval = 300
    /// How many recent items the dropdown keeps.
    private let recentLimit = 50

    init(settings: SettingsStore = .shared) {
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start(token: String) {
        self.token = token
        seenUnreadIDs = []          // first poll seeds the baseline, no banner spam
        consecutiveFailures = 0
        restart()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        token = nil
        notifications = []
        seenUnreadIDs = []
    }

    /// Forces an immediate poll (e.g. after the user changes their subscriptions).
    func refreshNow() {
        restart()
    }

    private func restart() {
        pollTask?.cancel()
        guard token != nil else { return }
        pollTask = Task { [weak self] in
            await self?.loop()
        }
    }

    // MARK: - Loop

    private func loop() async {
        var firstPoll = true
        while !Task.isCancelled {
            let interval = await pollOnce(isFirstPoll: firstPoll)
            firstPoll = false
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                break   // cancelled
            }
        }
    }

    /// Performs one poll; returns the number of seconds to wait before the next.
    private func pollOnce(isFirstPoll: Bool) async -> TimeInterval {
        guard let token else { return defaultInterval }
        let client = GitHubAPIClient(token: token)
        do {
            let result = try await client.pollNotifications(etag: settings.notificationsETag)
            consecutiveFailures = 0
            connectionStatus = .connected
            lastUpdated = Date()

            if !result.notModified {
                settings.notificationsETag = result.etag
                applyFiltered(result.notifications, isFirstPoll: isFirstPoll)
            }

            let advised = result.pollIntervalSeconds.map(TimeInterval.init) ?? defaultInterval
            return max(advised, defaultInterval)
        } catch GitHubAPIError.unauthorized {
            connectionStatus = .authError
            return defaultInterval
        } catch {
            // Network or transient error: keep the last data, back off, retry silently.
            consecutiveFailures += 1
            if consecutiveFailures >= 2 {
                connectionStatus = .networkError
            }
            let backoff = min(defaultInterval * Double(consecutiveFailures), maxBackoff)
            return backoff
        }
    }

    // MARK: - Filtering & diffing

    private func applyFiltered(_ incoming: [GitHubNotification], isFirstPoll: Bool) {
        let subscribed = Set(settings.subscribedRepositories)
        let allowedTypes: Set<NotificationType> = [.reviewRequest, .reviewComment, .issueMention]

        let filtered = incoming
            .filter { subscribed.isEmpty ? false : subscribed.contains($0.repositoryName) }
            .filter { allowedTypes.contains($0.notificationType) }
            .sorted { $0.updatedAt > $1.updatedAt }

        let trimmed = Array(filtered.prefix(recentLimit))

        // Detect newly-arrived unread items for banners.
        let currentUnread = trimmed.filter(\.isUnread)
        let fresh = currentUnread.filter { !seenUnreadIDs.contains($0.id) }
        seenUnreadIDs.formUnion(currentUnread.map(\.id))

        notifications = trimmed

        if !isFirstPoll, !fresh.isEmpty {
            newNotifications.send(fresh)
        }
    }

    var unreadCount: Int {
        notifications.filter(\.isUnread).count
    }
}
