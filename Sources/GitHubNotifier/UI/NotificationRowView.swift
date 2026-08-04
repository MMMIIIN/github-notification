import SwiftUI

/// A single notification row: a tinted type icon, the title with unread emphasis,
/// and a secondary line (repo · author · relative time). Highlights on hover.
struct NotificationRowView: View {
    let notification: GitHubNotification
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 11) {
                iconBadge

                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.callout)
                        .fontWeight(notification.isUnread ? .semibold : .regular)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 5) {
                        Text(notification.repositoryName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let author = notification.author {
                            Text("·"); Text("@\(author)").lineLimit(1)
                        }
                        Text("·"); Text(RelativeTime.string(for: notification.updatedAt))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if notification.isUnread {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var iconBadge: some View {
        Image(systemName: notification.notificationType.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }

    private var headline: String {
        if let number = notification.number {
            return "#\(number)  \(notification.title)"
        }
        return notification.title
    }

    private var tint: Color {
        switch notification.notificationType {
        case .reviewRequest: return .green
        case .reviewComment: return .blue
        case .issueMention:  return .purple
        case .other:         return .secondary
        }
    }
}

/// Compact relative-time formatting ("3m", "2h", "yesterday").
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func string(for date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}
