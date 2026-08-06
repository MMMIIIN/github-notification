import SwiftUI

/// Settings: badge style, launch-at-login, testing, and logout.
struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    accountSection
                    Divider().padding(.vertical, 16)
                    badgeSection
                    Divider().padding(.vertical, 16)
                    startupSection
                    Divider().padding(.vertical, 16)
                    testNotificationSection
                }
                .padding(18)
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

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Startup")
            Toggle("Launch at login", isOn: Binding(
                get: { app.settings.autoLaunch },
                set: { app.settings.autoLaunch = $0 }
            ))
        }
    }

    private var testNotificationSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Test notification")
            Text("Preview the menu bar badge, list, and macOS notification banner.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                app.sendTestNotification()
            } label: {
                Label("Send test notification", systemImage: "bell.badge")
            }
            .buttonStyle(.bordered)
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
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.tertiary)
            .tracking(0.4)
    }

    private var accountLabel: String {
        if case let .signedIn(login) = app.auth.state {
            return login
        }
        return "Signed in"
    }
}
