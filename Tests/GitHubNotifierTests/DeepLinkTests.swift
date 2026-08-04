import XCTest
@testable import GitHubNotifier

final class DeepLinkTests: XCTestCase {
    func testIssueCommentBuildsExactAnchor() {
        let result = GitHubAPIClient.localCommentHTMLURL(
            commentAPIURL: "https://api.github.com/repos/acme/widget/issues/comments/4900127954",
            threadHTMLURL: "https://github.com/acme/widget/pull/5"
        )

        XCTAssertEqual(result, "https://github.com/acme/widget/pull/5#issuecomment-4900127954")
    }

    func testPullReviewCommentWaitsForAPIResolution() {
        let result = GitHubAPIClient.localCommentHTMLURL(
            commentAPIURL: "https://api.github.com/repos/acme/widget/pulls/comments/1234",
            threadHTMLURL: "https://github.com/acme/widget/pull/5"
        )

        XCTAssertNil(result)
    }

    func testReviewRequestOpensFilesChanged() {
        XCTAssertEqual(
            GitHubAPIClient.reviewURL(from: "https://github.com/acme/widget/pull/5"),
            "https://github.com/acme/widget/pull/5/files"
        )
    }
}
