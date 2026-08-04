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

    /// High-level screen the popover should show.
    enum Screen: Equatable {
        case login
        case onboarding      // mandatory repo subscription
        case notifications
    }

    @Published private(set) var screen: Screen = .login

    private var cancellables: Set<AnyCancellable> = []

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

        // A review request has no triggering comment to scroll to. GitHub's
        // useful destination for that notification is the Files changed view.
        if notification.notificationType == .reviewRequest {
            openInBrowser(GitHubAPIClient.reviewURL(from: notification.url))
            return
        }

        let login = auth.currentLogin
        Task {
            let client = GitHubAPIClient(token: token)

            if let commentURL = notification.commentAPIURL,
               let html = GitHubAPIClient.localCommentHTMLURL(
                   commentAPIURL: commentURL,
                   threadHTMLURL: notification.url
               ) {
                openInBrowser(html)
                return
            }

            if let commentURL = notification.commentAPIURL,
               let html = await client.resolveCommentHTMLURL(commentAPIURL: commentURL),
               URL(string: html)?.fragment?.isEmpty == false {
                openInBrowser(html)
                return
            }

            if let html = await client.findScrollTarget(
                repoFullName: notification.repositoryName,
                number: notification.number,
                isPR: notification.isPullRequest,
                login: login,
                preferMention: notification.notificationType == .issueMention
            ) {
                openInBrowser(html)
                return
            }

            openInBrowser(notification.url)
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

    /// Called from Settings when the subscription list changes while signed in.
    func applySubscriptionChange(_ repos: [String]) {
        settings.subscribedRepositories = repos
        poller.refreshNow()
    }
}
