import SwiftUI

/// A single notification row: a tinted type icon, the title with unread emphasis,
/// and a secondary line (repo · author · relative time). Highlights on hover.
struct NotificationRowView: View {
    let notification: GitHubNotification
    var preview: String? = nil
    var isResolving = false
    var showsRepository = true
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            iconBadge

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
                    if let author = notification.author {
                        Text("·"); Text("@\(author)").lineLimit(1)
                    }
                    if showsRepository || notification.author != nil { Text("·") }
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
            } else if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Remove this read notification")
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
        .onTapGesture { if !isResolving { onTap() } }
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

    private var typeLabel: some View {
        Text(notification.notificationType.label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.13)))
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
