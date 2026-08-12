import Foundation
import Combine
import AppKit

/// Central app environment: owns the auth manager, poller, and settings, and
/// wires them together. Injected into the SwiftUI views as an EnvironmentObject.
@MainActor
final class AppState: ObservableObject {
    let auth = AuthManager()
    let poller = NotificationPoller()
    let settings = SettingsStore.shared

    /// Rows currently waiting for a deep link to be resolved after a click.
    @Published private(set) var resolvingNotificationIDs: Set<String> = []
    /// Ephemeral previews; private repository content is never persisted.
    @Published private(set) var notificationPreviews: [String: String] = [:]
    @Published private(set) var notificationAuthors: [String: String] = [:]
    @Published private(set) var markingReadNotificationIDs: Set<String> = []
    @Published private(set) var recentlyMarkedReadNotificationIDs: Set<String> = []
    @Published private(set) var readActionError: String?

    /// High-level screen the popover should show.
    enum Screen: Equatable {
        case login
        case notifications
    }

    @Published private(set) var screen: Screen = .login

    private var cancellables: Set<AnyCancellable> = []
    private struct CachedDeepLink {
        let notificationDate: Date
        let url: String
        let preview: String?
        let author: String?
    }
    private var deepLinkCache: [String: CachedDeepLink] = [:]
    private var resolutionTasks: [String: Task<NotificationTarget, Never>] = [:]
    private var prefetchTask: Task<Void, Never>?

    init() {
        // Views observe AppState as their environment object, while polling
        // state lives in a nested ObservableObject. Forward every poller change
        // so refresh progress, timestamps, connection state, and rows redraw
        // even when GitHub returns 304 with the same notification array.
        poller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // React to auth changes: drive the screen and the poller.
        auth.$token
            .receive(on: RunLoop.main)
            .sink { [weak self] token in
                self?.handleTokenChange(token)
            }
            .store(in: &cancellables)

        // Resolve the most recent links in the background so normal clicks can
        // open immediately. Keep this bounded to avoid a burst of API traffic.
        poller.$notifications
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] notifications in
                self?.prefetchDeepLinks(for: Array(notifications.prefix(12)))
            }
            .store(in: &cancellables)

        recomputeScreen()
    }

    // MARK: - Screen routing

    private func handleTokenChange(_ token: String?) {
        if let token {
            recomputeScreen()
            poller.start(token: token)
        } else {
            poller.stop()
            prefetchTask?.cancel()
            prefetchTask = nil
            resolutionTasks.values.forEach { $0.cancel() }
            resolutionTasks = [:]
            deepLinkCache = [:]
            notificationPreviews = [:]
            notificationAuthors = [:]
            markingReadNotificationIDs = []
            recentlyMarkedReadNotificationIDs = []
            readActionError = nil
            resolvingNotificationIDs = []
            recomputeScreen()
        }
    }

    private func recomputeScreen() {
        if auth.token == nil {
            screen = .login
        } else {
            screen = .notifications
        }
    }

    // MARK: - Actions

    func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens a notification in the browser, scrolling to the exact comment.
    ///
    /// GitHub's notification often gives no real comment URL (it points at the
    /// PR/issue itself), so we resolve the precise location in two steps:
    ///   1. If `latest_comment_url` is a real comment, use its `#anchor` html_url.
    ///   2. Otherwise scan the thread for the latest comment that @mentions me
    ///      (or the latest overall) and open that.
    /// Falls back to the thread/PR page if nothing resolves.
    func openNotification(_ notification: GitHubNotification) {
        guard let token = auth.token else {
            openInBrowser(notification.url)
            return
        }

        // Opening it is the user dealing with this one notification — and only
        // this one. Done for read notifications too, since GitHub's unread flag
        // may already have been cleared by another client.
        poller.acknowledgeArrival(id: notification.id)

        if notification.isUnread {
            markNotificationAsRead(notification)
        }

        if let immediate = immediateDeepLink(for: notification) {
            openInBrowser(immediate)
            return
        }

        if let cached = cachedDeepLink(for: notification) {
            openInBrowser(cached)
            return
        }

        resolvingNotificationIDs.insert(notification.id)
        Task {
            let target = await resolveDeepLink(for: notification, token: token)
            resolvingNotificationIDs.remove(notification.id)
            openInBrowser(target.url)
        }
    }

    private func immediateDeepLink(for notification: GitHubNotification) -> String? {
        if notification.notificationType == .reviewRequest {
            return GitHubAPIClient.reviewURL(from: notification.url)
        }
        guard let commentURL = notification.commentAPIURL else { return nil }
        return GitHubAPIClient.localCommentHTMLURL(
            commentAPIURL: commentURL,
            threadHTMLURL: notification.url
        )
    }

    private func cachedDeepLink(for notification: GitHubNotification) -> String? {
        guard let cached = deepLinkCache[notification.id],
              cached.notificationDate == notification.updatedAt else { return nil }
        return cached.url
    }

    private func resolveDeepLink(for notification: GitHubNotification, token: String) async -> NotificationTarget {
        if let cached = deepLinkCache[notification.id], cached.notificationDate == notification.updatedAt {
            return NotificationTarget(url: cached.url, preview: cached.preview, author: cached.author)
        }
        if let existing = resolutionTasks[notification.id] { return await existing.value }

        let login = auth.currentLogin
        let immediate = immediateDeepLink(for: notification)
        let task = Task<NotificationTarget, Never> {
            let client = GitHubAPIClient(token: token)

            if notification.notificationType == .reviewRequest {
                async let preview = client.fetchThreadPreview(
                    repoFullName: notification.repositoryName,
                    number: notification.number,
                    isPR: notification.isPullRequest
                )
                async let requester = client.fetchReviewRequester(
                    repoFullName: notification.repositoryName,
                    number: notification.number,
                    login: login,
                    notificationDate: notification.updatedAt
                )
                return await NotificationTarget(
                    url: immediate ?? notification.url,
                    preview: preview,
                    author: requester
                )
            }

            if let commentURL = notification.commentAPIURL,
               let resolved = await client.resolveCommentTarget(commentAPIURL: commentURL) {
                let resolvedHasAnchor = URL(string: resolved.url)?.fragment?.isEmpty == false
                if resolvedHasAnchor || immediate != nil {
                    return NotificationTarget(
                        url: immediate ?? resolved.url,
                        preview: resolved.preview,
                        author: resolved.author
                    )
                }
            }
            return await client.findScrollTarget(
                repoFullName: notification.repositoryName,
                number: notification.number,
                isPR: notification.isPullRequest,
                login: login,
                preferMention: notification.notificationType == .issueMention,
                notificationDate: notification.updatedAt
            ) ?? NotificationTarget(url: immediate ?? notification.url, preview: nil, author: nil)
        }
        resolutionTasks[notification.id] = task
        let target = await task.value
        resolutionTasks[notification.id] = nil

        // The row may have been removed while its request was in flight. Do
        // not republish preview state for a notification that no longer exists.
        guard poller.notifications.contains(where: {
            $0.id == notification.id && $0.updatedAt == notification.updatedAt
        }) else {
            return target
        }
        deepLinkCache[notification.id] = CachedDeepLink(
            notificationDate: notification.updatedAt,
            url: target.url,
            preview: target.preview,
            author: target.author
        )
        if let preview = target.preview {
            notificationPreviews[notification.id] = preview
        } else {
            notificationPreviews[notification.id] = nil
        }
        if let author = target.author {
            notificationAuthors[notification.id] = author
        } else {
            notificationAuthors[notification.id] = nil
        }
        return target
    }

    private func prefetchDeepLinks(for notifications: [GitHubNotification]) {
        guard let token = auth.token else { return }
        // Removing a row also publishes the shortened notification array. Do
        // not cancel and rebuild the whole preview queue for every deletion.
        guard prefetchTask == nil else { return }
        let pending = notifications.filter {
            cachedDeepLink(for: $0) == nil && resolutionTasks[$0.id] == nil
        }
        guard !pending.isEmpty else { return }
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            defer { prefetchTask = nil }
            for notification in pending where !Task.isCancelled {
                guard cachedDeepLink(for: notification) == nil else { continue }
                _ = await resolveDeepLink(for: notification, token: token)
            }
        }
    }

    /// Opens by notification id (used by banner clicks), resolving to the exact
    /// comment when the notification is still in the current list.
    func openNotification(byID id: String, fallbackURL: String) {
        if let match = poller.notifications.first(where: { $0.id == id }) {
            openNotification(match)
        } else {
            openInBrowser(fallbackURL)
        }
    }

    func signOut() {
        auth.signOut()
    }

    func dismissReadNotification(_ notification: GitHubNotification) {
        guard !notification.isUnread else { return }
        deepLinkCache[notification.id] = nil
        notificationPreviews[notification.id] = nil
        notificationAuthors[notification.id] = nil
        resolutionTasks[notification.id]?.cancel()
        resolutionTasks[notification.id] = nil
        markingReadNotificationIDs.remove(notification.id)
        recentlyMarkedReadNotificationIDs.remove(notification.id)
        resolvingNotificationIDs.remove(notification.id)
        poller.dismissReadNotification(id: notification.id)
    }

    func dismissAllNotifications() {
        prefetchTask?.cancel()
        prefetchTask = nil
        resolutionTasks.values.forEach { $0.cancel() }
        resolutionTasks = [:]
        deepLinkCache = [:]
        notificationPreviews = [:]
        notificationAuthors = [:]
        resolvingNotificationIDs = []
        poller.dismissAllNotifications()
    }

    func sendTestNotification() {
        poller.sendTestNotification()
    }

    /// "I've dealt with this one" from the row button.
    ///
    /// Clears it from the badge and, when GitHub still considers it unread,
    /// marks it read there too. The two are separate because another GitHub
    /// client may already have cleared the unread flag while the notification
    /// is still new to this user.
    func markNotificationAsSeen(_ notification: GitHubNotification) {
        if notification.isUnread {
            markNotificationAsRead(notification)
        } else {
            poller.acknowledgeArrival(id: notification.id)
            showReadConfirmation(for: notification.id)
        }
    }

    func markNotificationAsRead(_ notification: GitHubNotification) {
        guard notification.isUnread,
              !markingReadNotificationIDs.contains(notification.id) else { return }

        if notification.id.hasPrefix("test-") {
            poller.setNotificationUnreadState(id: notification.id, isUnread: false)
            showReadConfirmation(for: notification.id)
            return
        }
        guard let token = auth.token else { return }

        DebugLog.log("markread", "app is marking id=\(notification.id) read (user action)")
        markingReadNotificationIDs.insert(notification.id)
        // Optimistic update: make the interaction immediate. Roll back if the
        // GitHub request fails.
        poller.setNotificationUnreadState(id: notification.id, isUnread: false)
        Task {
            defer { markingReadNotificationIDs.remove(notification.id) }
            do {
                try await GitHubAPIClient(token: token).markNotificationRead(id: notification.id)
                showReadConfirmation(for: notification.id)
            } catch {
                poller.setNotificationUnreadState(id: notification.id, isUnread: true)
                readActionError = "Couldn’t mark the notification as read. Please try again."
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    readActionError = nil
                }
            }
        }
    }

    private func showReadConfirmation(for id: String) {
        recentlyMarkedReadNotificationIDs.insert(id)
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            recentlyMarkedReadNotificationIDs.remove(id)
        }
    }

}
