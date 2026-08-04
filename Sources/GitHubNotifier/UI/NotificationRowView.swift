import SwiftUI

/// A compact notification row with a quiet, native macOS visual hierarchy.
struct NotificationRowView: View {
    let notification: GitHubNotification
    var preview: String? = nil
    var resolvedAuthor: String? = nil
    var isResolving = false
    var showsRepository = true
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            typeIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.callout)
                    .fontWeight(notification.isUnread ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 5) {
                    typeLabel
                    if showsRepository {
                        Text(notification.repositoryName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let author = resolvedAuthor ?? notification.author {
                        Text("·"); Text("@\(author)").lineLimit(1)
                    }
                    if showsRepository || resolvedAuthor != nil || notification.author != nil { Text("·") }
                    Text(RelativeTime.string(for: notification.updatedAt))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isResolving {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
            } else if notification.isUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
            } else if let onDelete, hovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Remove this read notification")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            Rectangle()
                .fill(hovering ? Color.primary.opacity(0.035) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isResolving { onTap() } }
        .onHover { hovering = $0 }
    }

    private var typeIcon: some View {
        Image(systemName: notification.notificationType.symbolName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(notification.isUnread ? Color.primary : Color.secondary)
            .frame(width: 18, height: 20)
            .padding(.top, 1)
    }

    private var typeLabel: some View {
        Text(notification.notificationType.label)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var headline: String {
        if let number = notification.number {
            return "#\(number)  \(notification.title)"
        }
        return notification.title
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
