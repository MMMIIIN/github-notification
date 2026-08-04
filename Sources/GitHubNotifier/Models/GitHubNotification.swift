import Foundation

/// The kinds of GitHub notifications this MVP surfaces. Mapped from the GitHub
/// Notifications API `reason` field (plus the subject type).
enum NotificationType: String, Codable, CaseIterable {
    case reviewRequest
    case reviewComment
    case issueMention
    case other

    /// SF Symbol name used in the dropdown row.
    var symbolName: String {
        switch self {
        case .reviewRequest: return "checklist"
        case .reviewComment: return "text.bubble"
        case .issueMention: return "at"
        case .other: return "bell"
        }
    }

    var label: String {
        switch self {
        case .reviewRequest: return "Review requested"
        case .reviewComment: return "Review comment"
        case .issueMention: return "Mention"
        case .other: return "Notification"
        }
    }

    /// Maps a GitHub notification `reason` + subject type into our domain type.
    /// `reason` values: https://docs.github.com/rest/activity/notifications
    static func from(reason: String, subjectType: String) -> NotificationType {
        switch reason {
        case "review_requested":
            return .reviewRequest
        case "mention", "team_mention":
            return .issueMention
        case "comment":
            // A comment on a PR review thread vs. an issue thread.
            return subjectType == "PullRequest" ? .reviewComment : .issueMention
        default:
            return .other
        }
    }
}

/// Domain model for a single GitHub notification shown in the app.
struct GitHubNotification: Identifiable, Codable, Equatable {
    let id: String
    let repositoryName: String        // "org/repo"
    let organizationName: String
    let notificationType: NotificationType
    let title: String
    let number: Int?                  // PR/issue number, if resolvable
    let author: String?
    let url: String                   // browser-navigable URL (thread/subject)
    let commentAPIURL: String?        // latest_comment_url; resolved to a #anchor on click
    let isUnread: Bool
    let updatedAt: Date

    static func == (lhs: GitHubNotification, rhs: GitHubNotification) -> Bool {
        lhs.id == rhs.id && lhs.isUnread == rhs.isUnread && lhs.updatedAt == rhs.updatedAt
    }
}

/// Which credential the user authenticated with.
enum AuthMethod: String, Codable {
    case oauth
    case pat
}

/// Preferred menu bar badge presentation. Both are implemented; the user picks.
enum BadgeStyle: String, Codable, CaseIterable {
    case number
    case dot

    var displayName: String {
        switch self {
        case .number: return "Unread count"
        case .dot: return "Dot"
        }
    }
}

/// Network / auth health surfaced on the menu bar icon.
enum ConnectionStatus: Equatable {
    case connected
    case networkError
    case authError

    var isHealthy: Bool { self == .connected }
}
