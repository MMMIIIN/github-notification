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
        HStack(spacing: 8) {
            Text("Notifications")
                .font(.headline)
            if app.poller.unreadCount > 0 {
                Text("\(app.poller.unreadCount)")
                    .font(.caption2).monospacedDigit().bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
            }
            Spacer()
            IconButton(system: "arrow.clockwise", help: "Refresh now") {
                app.poller.refreshNow()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(color.opacity(0.12))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if app.poller.notifications.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 1, pinnedViews: [.sectionHeaders]) {
                    ForEach(repositoryGroups) { group in
                        Section {
                            ForEach(group.notifications) { item in
                                NotificationRowView(
                                    notification: item,
                                    preview: app.notificationPreviews[item.id],
                                    isResolving: app.resolvingNotificationIDs.contains(item.id),
                                    showsRepository: false,
                                    onTap: {
                                        app.openNotification(item)
                                    },
                                    onDelete: item.isUnread ? nil : {
                                        app.dismissReadNotification(item)
                                    }
                                )
                            }
                        } header: {
                            repositoryHeader(group)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private struct RepositoryGroup: Identifiable {
        let name: String
        let notifications: [GitHubNotification]
        var id: String { name }
        var unreadCount: Int { notifications.filter(\.isUnread).count }
        var newestDate: Date { notifications.first?.updatedAt ?? .distantPast }
    }

    private var repositoryGroups: [RepositoryGroup] {
        Dictionary(grouping: app.poller.notifications, by: \.repositoryName)
            .map { name, items in
                RepositoryGroup(
                    name: name,
                    notifications: items.sorted { $0.updatedAt > $1.updatedAt }
                )
            }
            .sorted { $0.newestDate > $1.newestDate }
    }

    private func repositoryHeader(_ group: RepositoryGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
            Text(group.name)
                .font(.caption).bold()
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if group.unreadCount > 0 {
                Text("\(group.unreadCount) unread")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(group.notifications.count)")
                .font(.caption2).monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("You're all caught up")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("New review requests, comments, and mentions\nwill show up here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            IconButton(system: "gearshape", help: "Settings") {
                showingSettings = true
            }
            Spacer()
            Button("Open on GitHub") {
                app.openInBrowser("https://github.com/notifications")
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A borderless icon button with a hover highlight, used in the header/footer.
struct IconButton: View {
    let system: String
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
