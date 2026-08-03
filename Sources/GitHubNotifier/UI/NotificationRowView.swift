import SwiftUI

/// A single notification row: type icon + repo/number/title + author + relative
/// time, with unread emphasis.
struct NotificationRowView: View {
    let notification: GitHubNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                // Unread dot keeps the leading edge scannable.
                Circle()
                    .fill(notification.isUnread ? Color.accentColor : Color.clear)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)

                Image(systemName: notification.notificationType.symbolName)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.callout)
                        .fontWeight(notification.isUnread ? .semibold : .regular)
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(notification.repositoryName)
                            .lineLimit(1)
                        if let author = notification.author {
                            Text("@\(author)")
                        }
                        Text("· \(RelativeTime.string(for: notification.updatedAt))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headline: String {
        if let number = notification.number {
            return "#\(number): \(notification.title)"
        }
        return notification.title
    }

    private var iconColor: Color {
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
