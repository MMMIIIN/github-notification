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

    /// Opens a notification in the browser, scrolling to the exact comment when
    /// one is present by resolving its `#anchor` first; falls back to the thread.
    func openNotification(_ notification: GitHubNotification) {
        open(url: notification.url, commentAPIURL: notification.commentAPIURL)
    }

    func open(url: String, commentAPIURL: String?) {
        guard let commentAPIURL, let token = auth.token else {
            openInBrowser(url)
            return
        }
        Task {
            let resolved = await GitHubAPIClient(token: token).resolveCommentHTMLURL(commentAPIURL: commentAPIURL)
            openInBrowser(resolved ?? url)
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
