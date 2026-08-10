import XCTest
@testable import GitHubNotifier

@MainActor
final class NotificationPollerTests: XCTestCase {
    func testTestNotificationCanBeMarkedReadLocally() {
        let poller = NotificationPoller()

        poller.sendTestNotification()
        let id = poller.notifications[0].id
        XCTAssertTrue(poller.notifications[0].isUnread)
        XCTAssertEqual(poller.unreadCount, 1)

        poller.setNotificationUnreadState(id: id, isUnread: false)

        XCTAssertFalse(poller.notifications[0].isUnread)
        XCTAssertEqual(poller.unreadCount, 0)
    }

    func testUpdatedThreadWithSameIDIsNewAgain() {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        let updated = notification(id: "thread-1", updatedAt: newDate)

        let fresh = NotificationPoller.newUnreadNotifications(
            in: [updated],
            seenVersions: ["thread-1": oldDate]
        )

        XCTAssertEqual(fresh, [updated])
    }

    func testUnchangedThreadIsNotNewAgain() {
        let date = Date(timeIntervalSince1970: 1_000)
        let unchanged = notification(id: "thread-1", updatedAt: date)

        let fresh = NotificationPoller.newUnreadNotifications(
            in: [unchanged],
            seenVersions: ["thread-1": date]
        )

        XCTAssertTrue(fresh.isEmpty)
    }

    func testGitHubReasonsMapToVisibleTypes() {
        XCTAssertEqual(NotificationType.from(reason: "comment", subjectType: "Issue"), .issueComment)
        XCTAssertEqual(NotificationType.from(reason: "mention", subjectType: "Issue"), .issueMention)
        XCTAssertEqual(NotificationType.from(reason: "assign", subjectType: "Issue"), .assigned)
        XCTAssertEqual(NotificationType.from(reason: "ci_activity", subjectType: "CheckSuite"), .ciActivity)
        XCTAssertEqual(NotificationType.from(reason: "security_alert", subjectType: "RepositoryVulnerabilityAlert"), .securityAlert)
        XCTAssertEqual(NotificationType.from(reason: "subscribed", subjectType: "Issue"), .subscribed)
    }

    private func notification(id: String, updatedAt: Date) -> GitHubNotification {
        GitHubNotification(
            id: id,
            repositoryName: "owner/repo",
            organizationName: "owner",
            notificationType: .reviewComment,
            title: "Update",
            number: 1,
            author: nil,
            url: "https://github.com/owner/repo/pull/1",
            commentAPIURL: nil,
            isPullRequest: true,
            isUnread: true,
            updatedAt: updatedAt
        )
    }
}
