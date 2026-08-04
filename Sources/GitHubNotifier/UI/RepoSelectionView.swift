import SwiftUI

/// Repository subscription picker. Used as the mandatory onboarding step and,
/// in `.settings` mode, for editing subscriptions later.
struct RepoSelectionView: View {
    enum Mode { case onboarding, settings }

    let mode: Mode
    var onDone: (() -> Void)? = nil

    @EnvironmentObject private var app: AppState
    @State private var selected: Set<String> = []
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            if app.isLoadingRepos {
                Spacer()
                ProgressView("Loading repositories…")
                Spacer()
            } else if let error = app.repoLoadError {
                errorState(error)
            } else {
                repoList
            }

            footer
        }
        .task {
            if app.availableRepos.isEmpty { await app.loadRepositories() }
            selected = Set(app.settings.subscribedRepositories)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 4) {
            Text(mode == .onboarding ? "Choose repositories to watch" : "Edit subscriptions")
                .font(.headline)
            Text("You'll get notifications for these repositories only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var repoList: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter repositories", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.045)))
            .padding(.horizontal, 14)

            List {
                ForEach(filteredRepos) { repo in
                    Button {
                        toggle(repo.fullName)
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(repo.fullName) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selected.contains(repo.fullName) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(repo.fullName).font(.callout)
                            }
                            Spacer()
                            if repo.isPrivate {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.inset)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message).font(.callout).multilineTextAlignment(.center)
            Button("Retry") { Task { await app.loadRepositories() } }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if mode == .settings {
                Button("Cancel") { onDone?() }
                    .buttonStyle(.bordered)
            }
            Text("\(selected.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(mode == .onboarding ? "Continue" : "Save") {
                confirm()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
        .padding(12)
    }

    // MARK: - Logic

    private var filteredRepos: [RepositorySummary] {
        guard !search.isEmpty else { return app.availableRepos }
        return app.availableRepos.filter { $0.fullName.localizedCaseInsensitiveContains(search) }
    }

    private func toggle(_ name: String) {
        if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
    }

    private func confirm() {
        let repos = Array(selected).sorted()
        switch mode {
        case .onboarding:
            app.completeOnboarding(with: repos)
        case .settings:
            app.applySubscriptionChange(repos)
            onDone?()
        }
    }
}
