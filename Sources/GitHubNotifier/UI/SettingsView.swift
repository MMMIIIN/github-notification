import SwiftUI

/// Settings: badge style, subscription editing, launch-at-login, and logout.
struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @Binding var isPresented: Bool
    @State private var editingRepos = false

    var body: some View {
        if editingRepos {
            RepoSelectionView(mode: .settings, onDone: { editingRepos = false })
        } else {
            settingsBody
        }
    }

    private var settingsBody: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    accountSection
                    badgeSection
                    subscriptionsSection
                    startupSection
                }
                .padding(16)
            }

            Divider()
            footer
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .buttonStyle(.borderless)
            Spacer()
            Text("Settings").font(.headline)
            Spacer()
            // Balance the back button.
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Account")
            HStack {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Text(accountLabel)
                    .font(.callout)
                Spacer()
            }
        }
    }

    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Menu bar badge")
            Picker("", selection: Binding(
                get: { app.settings.badgeStyle },
                set: { app.settings.badgeStyle = $0 }
            )) {
                ForEach(BadgeStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Show the unread count, or a simple dot.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var subscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Subscribed repositories")
            Text("\(app.settings.subscribedRepositories.count) repositories")
                .font(.callout)
            Button("Edit subscriptions…") {
                editingRepos = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Startup")
            Toggle("Launch at login", isOn: Binding(
                get: { app.settings.autoLaunch },
                set: { app.settings.autoLaunch = $0 }
            ))
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                app.signOut()
                isPresented = false
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2).bold()
            .foregroundStyle(.secondary)
    }

    private var accountLabel: String {
        if case let .signedIn(login) = app.auth.state {
            return login
        }
        return "Signed in"
    }
}
