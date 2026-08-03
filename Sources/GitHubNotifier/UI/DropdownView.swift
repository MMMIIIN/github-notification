import SwiftUI

/// The main dropdown: recent notifications with unread emphasis, a connection
/// banner on errors, and a footer with settings + "open on GitHub".
struct DropdownView: View {
    @EnvironmentObject private var app: AppState
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            connectionBanner
            content
            Divider()
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.headline)
            if app.poller.unreadCount > 0 {
                Text("\(app.poller.unreadCount)")
                    .font(.caption2).bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
            }
            Spacer()
            Button {
                app.poller.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Connection banner

    @ViewBuilder
    private var connectionBanner: some View {
        switch app.poller.connectionStatus {
        case .connected:
            EmptyView()
        case .networkError:
            banner(text: "Can't reach GitHub — retrying…", color: .orange, icon: "wifi.exclamationmark")
        case .authError:
            banner(text: "Sign-in expired. Open Settings to sign in again.", color: .red, icon: "exclamationmark.triangle.fill")
        }
    }

    private func banner(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).font(.caption)
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(color.opacity(0.12))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if app.poller.notifications.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(app.poller.notifications) { item in
                        NotificationRowView(notification: item) {
                            app.openInBrowser(item.url)
                        }
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("You're all caught up")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                Text("Settings")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Open on GitHub") {
                app.openInBrowser("https://github.com/notifications")
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
