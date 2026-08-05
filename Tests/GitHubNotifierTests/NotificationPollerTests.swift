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
}
