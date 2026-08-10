import Foundation

/// The kinds of GitHub notifications this MVP surfaces. Mapped from the GitHub
/// Notifications API `reason` field (plus the subject type).
enum NotificationType: String, Codable, CaseIterable {
    case reviewRequest
    case reviewComment
    case issueComment
    case issueMention
    case assigned
    case authored
    case subscribed
    case ciActivity
    case securityAlert
    case stateChange
    case approvalRequest
    case other

    /// SF Symbol name used in the dropdown row.
    var symbolName: String {
        switch self {
        case .reviewRequest: return "checklist"
        case .reviewComment: return "text.bubble"
        case .issueComment: return "bubble.left"
        case .issueMention: return "at"
        case .assigned: return "person.crop.circle.badge.checkmark"
        case .authored: return "person.crop.circle"
        case .subscribed: return "eye"
        case .ciActivity: return "checkmark.circle"
        case .securityAlert: return "exclamationmark.shield"
        case .stateChange: return "arrow.triangle.2.circlepath"
        case .approvalRequest: return "checkmark.seal"
        case .other: return "bell"
        }
    }

    var label: String {
        switch self {
        case .reviewRequest: return "Review requested"
        case .reviewComment: return "Review comment"
        case .issueComment: return "Issue comment"
        case .issueMention: return "Mention"
        case .assigned: return "Assigned"
        case .authored: return "Your thread"
        case .subscribed: return "Subscribed thread"
        case .ciActivity: return "Workflow activity"
        case .securityAlert: return "Security alert"
        case .stateChange: return "State changed"
        case .approvalRequest: return "Approval requested"
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
        case "assign":
            return .assigned
        case "author":
            return .authored
        case "subscribed":
            return .subscribed
        case "ci_activity":
            return .ciActivity
        case "security_alert":
            return .securityAlert
        case "state_change":
            return .stateChange
        case "approval_requested":
            return .approvalRequest
        case "comment":
            // A comment on a PR review thread vs. an issue thread.
            return subjectType == "PullRequest" ? .reviewComment : .issueComment
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
    let isPullRequest: Bool           // subject.type == "PullRequest"
    var isUnread: Bool
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
