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

    /// Repositories available for subscription (loaded during onboarding).
    @Published var availableRepos: [RepositorySummary] = []
    @Published var isLoadingRepos = false
    @Published var repoLoadError: String?
    /// Rows currently waiting for a deep link to be resolved after a click.
    @Published private(set) var resolvingNotificationIDs: Set<String> = []
    /// Ephemeral previews; private repository content is never persisted.
    @Published private(set) var notificationPreviews: [String: String] = [:]

    /// High-level screen the popover should show.
    enum Screen: Equatable {
        case login
        case onboarding      // mandatory repo subscription
        case notifications
    }

    @Published private(set) var screen: Screen = .login

    private var cancellables: Set<AnyCancellable> = []
    private struct CachedDeepLink {
        let notificationDate: Date
        let url: String
        let preview: String?
    }
    private var deepLinkCache: [String: CachedDeepLink] = [:]
    private var resolutionTasks: [String: Task<NotificationTarget, Never>] = [:]
    private var prefetchTask: Task<Void, Never>?

    init() {
        // React to auth changes: drive the screen and the poller.
        auth.$token
            .receive(on: RunLoop.main)
            .sink { [weak self] token in
                self?.handleTokenChange(token)
            }
            .store(in: &cancellables)

        settings.$hasCompletedOnboarding
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recomputeScreen() }
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
            if settings.hasCompletedOnboarding {
                poller.start(token: token)
            }
        } else {
            poller.stop()
            prefetchTask?.cancel()
            prefetchTask = nil
            resolutionTasks.values.forEach { $0.cancel() }
            resolutionTasks = [:]
            deepLinkCache = [:]
            notificationPreviews = [:]
            resolvingNotificationIDs = []
            availableRepos = []
            recomputeScreen()
        }
    }

    private func recomputeScreen() {
        if auth.token == nil {
            screen = .login
        } else if !settings.hasCompletedOnboarding {
            screen = .onboarding
        } else {
            screen = .notifications
        }
    }

    // MARK: - Onboarding

    func loadRepositories() async {
        guard let token = auth.token else { return }
        isLoadingRepos = true
        repoLoadError = nil
        defer { isLoadingRepos = false }
        do {
            let repos = try await GitHubAPIClient(token: token).fetchRepositories()
            availableRepos = repos.sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
        } catch {
            repoLoadError = (error as? LocalizedError)?.errorDescription ?? "Could not load repositories."
        }
    }

    /// Completes onboarding with the chosen repositories and starts polling.
    func completeOnboarding(with repos: [String]) {
        settings.subscribedRepositories = repos
        settings.hasCompletedOnboarding = true
        recomputeScreen()
        if let token = auth.token {
            poller.start(token: token)
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
            return NotificationTarget(url: cached.url, preview: cached.preview)
        }
        if let existing = resolutionTasks[notification.id] { return await existing.value }

        let login = auth.currentLogin
        let immediate = immediateDeepLink(for: notification)
        let task = Task<NotificationTarget, Never> {
            let client = GitHubAPIClient(token: token)

            if notification.notificationType == .reviewRequest {
                let preview = await client.fetchThreadPreview(
                    repoFullName: notification.repositoryName,
                    number: notification.number,
                    isPR: notification.isPullRequest
                )
                return NotificationTarget(url: immediate ?? notification.url, preview: preview)
            }

            if let commentURL = notification.commentAPIURL,
               let resolved = await client.resolveCommentTarget(commentAPIURL: commentURL) {
                let resolvedHasAnchor = URL(string: resolved.url)?.fragment?.isEmpty == false
                if resolvedHasAnchor || immediate != nil {
                    return NotificationTarget(
                        url: immediate ?? resolved.url,
                        preview: resolved.preview
                    )
                }
            }
            return await client.findScrollTarget(
                repoFullName: notification.repositoryName,
                number: notification.number,
                isPR: notification.isPullRequest,
                login: login,
                preferMention: notification.notificationType == .issueMention
            ) ?? NotificationTarget(url: immediate ?? notification.url, preview: nil)
        }
        resolutionTasks[notification.id] = task
        let target = await task.value
        resolutionTasks[notification.id] = nil
        deepLinkCache[notification.id] = CachedDeepLink(
            notificationDate: notification.updatedAt,
            url: target.url,
            preview: target.preview
        )
        if let preview = target.preview {
            notificationPreviews[notification.id] = preview
        } else {
            notificationPreviews[notification.id] = nil
        }
        return target
    }

    private func prefetchDeepLinks(for notifications: [GitHubNotification]) {
        guard let token = auth.token else { return }
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            for notification in notifications where !Task.isCancelled {
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
        resolutionTasks[notification.id]?.cancel()
        resolutionTasks[notification.id] = nil
        resolvingNotificationIDs.remove(notification.id)
        poller.dismissReadNotification(id: notification.id)
    }

    /// Called from Settings when the subscription list changes while signed in.
    func applySubscriptionChange(_ repos: [String]) {
        settings.subscribedRepositories = repos
        poller.refreshNow()
    }
}
