import XCTest
@testable import GitHubNotifier

/// Covers the delivery signal the menu bar badge is built on.
///
/// Regression: notifications can be marked read by another GitHub client within
/// seconds of arriving, long before this app's 60s poll sees them. Keying
/// "new" off GitHub's `unread` flag therefore lost the notification entirely —
/// no badge, no banner — even though the poll received it.
@MainActor
final class NewArrivalTests: XCTestCase {
    private var settings: SettingsStore!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.ghnotifier.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        settings = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAlreadyReadArrivalStillCountsAsNew() {
        let poller = NotificationPoller(settings: settings)
        poller.applyFiltered([], suppressNewNotifications: false)   // establish baseline

        poller.applyFiltered([notification(id: "a", isUnread: false)],
                             suppressNewNotifications: false)

        XCTAssertEqual(poller.newArrivalIDs, ["a"],
                       "a notification already marked read elsewhere is still new to this user")
    }

    func testUnreadArrivalCountsAsNew() {
        let poller = NotificationPoller(settings: settings)
        poller.applyFiltered([], suppressNewNotifications: false)

        poller.applyFiltered([notification(id: "a", isUnread: true)],
                             suppressNewNotifications: false)

        XCTAssertEqual(poller.newArrivalIDs, ["a"])
    }

    func testSameRevisionIsNotNewTwice() {
        let poller = NotificationPoller(settings: settings)
        let item = notification(id: "a", isUnread: false)
        poller.applyFiltered([], suppressNewNotifications: false)
        poller.applyFiltered([item], suppressNewNotifications: false)
        poller.acknowledgeAllArrivals()

        poller.applyFiltered([item], suppressNewNotifications: false)

        XCTAssertTrue(poller.newArrivalIDs.isEmpty,
                      "re-seeing the same revision must not re-announce it")
    }

    func testNewActivityOnSameThreadIsNewAgain() {
        let poller = NotificationPoller(settings: settings)
        poller.applyFiltered([], suppressNewNotifications: false)
        poller.applyFiltered([notification(id: "a", isUnread: false, at: 1_000)],
                             suppressNewNotifications: false)
        poller.acknowledgeAllArrivals()

        poller.applyFiltered([notification(id: "a", isUnread: false, at: 2_000)],
                             suppressNewNotifications: false)

        XCTAssertEqual(poller.newArrivalIDs, ["a"],
                       "a newer comment on the same thread is a new arrival")
    }

    func testAcknowledgingOneArrivalLeavesTheOthersNew() {
        let poller = NotificationPoller(settings: settings)
        poller.applyFiltered([], suppressNewNotifications: false)
        poller.applyFiltered(
            ["a", "b", "c"].map { notification(id: $0, isUnread: false) },
            suppressNewNotifications: false
        )

        poller.acknowledgeArrival(id: "b")

        XCTAssertEqual(poller.newArrivalIDs, ["a", "c"],
                       "opening one notification must not clear the rest")
    }

    func testAcknowledgingOneArrivalSurvivesTheNextPoll() {
        let poller = NotificationPoller(settings: settings)
        let items = ["a", "b", "c"].map { notification(id: $0, isUnread: false) }
        poller.applyFiltered([], suppressNewNotifications: false)
        poller.applyFiltered(items, suppressNewNotifications: false)
        poller.acknowledgeArrival(id: "b")

        poller.applyFiltered(items, suppressNewNotifications: false)

        XCTAssertEqual(poller.newArrivalIDs, ["a", "c"],
                       "a re-poll must not resurrect an arrival the user handled")
    }

    func testMarkAllAsSeenClearsTheBadge() {
        let poller = NotificationPoller(settings: settings)
        poller.applyFiltered([], suppressNewNotifications: false)
        poller.applyFiltered([notification(id: "a", isUnread: false)],
                             suppressNewNotifications: false)

        poller.acknowledgeAllArrivals()

        XCTAssertTrue(poller.newArrivalIDs.isEmpty)
    }

    func testFirstPollOnAFreshInstallDoesNotAnnounceTheBacklog() {
        let poller = NotificationPoller(settings: settings)

        poller.applyFiltered(
            [notification(id: "a", isUnread: false), notification(id: "b", isUnread: true)],
            suppressNewNotifications: true
        )

        XCTAssertTrue(poller.newArrivalIDs.isEmpty,
                      "seeding the baseline must not light up the badge with old items")
    }

    func testArrivalsSurviveARelaunch() {
        let first = NotificationPoller(settings: settings)
        first.applyFiltered([], suppressNewNotifications: false)
        first.applyFiltered([notification(id: "a", isUnread: false)],
                            suppressNewNotifications: false)

        // Same persisted settings, new poller — as after a reboot.
        let relaunched = NotificationPoller(settings: settings)

        XCTAssertEqual(relaunched.newArrivalIDs, ["a"])
    }

    func testBannersAreSuppressedWhileTheBadgeStillCounts() {
        let poller = NotificationPoller(settings: settings)
        var banners: [[GitHubNotification]] = []
        let token = poller.newNotifications.sink { banners.append($0) }
        defer { token.cancel() }

        poller.applyFiltered([], suppressNewNotifications: false)
        poller.applyFiltered([notification(id: "a", isUnread: false)],
                             suppressNewNotifications: true)

        XCTAssertTrue(banners.isEmpty, "no banner burst for a backlog")
        XCTAssertEqual(poller.newArrivalIDs, ["a"], "but the badge must still show it")
    }

    func testMarkingReadInThisAppClearsItFromTheBadge() {
        let poller = NotificationPoller(settings: settings)
        poller.applyFiltered([], suppressNewNotifications: false)
        poller.applyFiltered([notification(id: "a", isUnread: true)],
                             suppressNewNotifications: false)

        poller.setNotificationUnreadState(id: "a", isUnread: false)

        XCTAssertTrue(poller.newArrivalIDs.isEmpty,
                      "acting on a notification means the user has seen it")
    }

    func testDisappearedNotificationsAreDroppedFromTheBadge() {
        let poller = NotificationPoller(settings: settings)
        poller.applyFiltered([], suppressNewNotifications: false)
        poller.applyFiltered([notification(id: "a", isUnread: false)],
                             suppressNewNotifications: false)

        poller.applyFiltered([], suppressNewNotifications: false)

        XCTAssertTrue(poller.newArrivalIDs.isEmpty,
                      "the badge must not count a notification no longer in the list")
    }

    private func notification(
        id: String,
        isUnread: Bool,
        at seconds: TimeInterval = 1_000
    ) -> GitHubNotification {
        GitHubNotification(
            id: id,
            repositoryName: "owner/repo",
            organizationName: "owner",
            notificationType: .reviewRequest,
            title: "Review requested",
            number: 1,
            author: nil,
            url: "https://github.com/owner/repo/pull/1",
            commentAPIURL: nil,
            isPullRequest: true,
            isUnread: isUnread,
            updatedAt: Date(timeIntervalSince1970: seconds)
        )
    }
}
