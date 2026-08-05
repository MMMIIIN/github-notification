import Foundation

enum GitHubAPIError: Error, Equatable {
    case notAuthenticated
    case unauthorized          // 401/403 — token invalid or revoked
    case network(String)       // transport-level failure
    case decoding(String)
    case http(Int)
}

/// Result of a conditional `/notifications` poll.
struct NotificationsPollResult {
    let notifications: [GitHubNotification]
    let etag: String?
    /// Server-advised minimum seconds until the next poll (X-Poll-Interval).
    let pollIntervalSeconds: Int?
    /// True when the server returned 304 Not Modified (nothing changed).
    let notModified: Bool
}

/// Browser destination and optional plain-text content fetched while resolving it.
struct NotificationTarget {
    let url: String
    let preview: String?
    let author: String?
}

/// A repository the user can subscribe to during onboarding.
struct RepositorySummary: Identifiable, Hashable {
    var id: String { fullName }
    let fullName: String       // "org/repo"
    let isPrivate: Bool
    let ownerLogin: String
}

/// Thin async GitHub REST client. Read-only (GET only) per the app's design.
struct GitHubAPIClient {
    let token: String
    private let baseURL = URL(string: "https://api.github.com")!
    private let session: URLSession

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: - Request plumbing

    private func makeRequest(path: String, query: [URLQueryItem] = [], etag: String? = nil) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitHubNotifier/1.0", forHTTPHeaderField: "User-Agent")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GitHubAPIError.network("Non-HTTP response")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                // 403 can be rate-limit; distinguish via header.
                if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                    throw GitHubAPIError.http(403)
                }
                throw GitHubAPIError.unauthorized
            }
            return (data, http)
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.network(error.localizedDescription)
        }
    }

    // MARK: - Authenticated user (token validation)

    /// Validates the token by fetching the login of the authenticated user.
    func fetchAuthenticatedUserLogin() async throws -> String {
        let (data, http) = try await send(makeRequest(path: "user"))
        guard http.statusCode == 200 else { throw GitHubAPIError.http(http.statusCode) }
        struct User: Decodable { let login: String }
        do {
            return try JSONDecoder().decode(User.self, from: data).login
        } catch {
            throw GitHubAPIError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Repositories (onboarding subscription list)

    /// Fetches repositories the user can access (includes private with `repo` scope).
    /// Paginates up to `maxPages` of 100.
    func fetchRepositories(maxPages: Int = 4) async throws -> [RepositorySummary] {
        var results: [RepositorySummary] = []
        for page in 1...maxPages {
            let query = [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member")
            ]
            let (data, http) = try await send(makeRequest(path: "user/repos", query: query))
            guard http.statusCode == 200 else { throw GitHubAPIError.http(http.statusCode) }

            struct Repo: Decodable {
                let full_name: String
                let `private`: Bool
                struct Owner: Decodable { let login: String }
                let owner: Owner
            }
            let repos: [Repo]
            do {
                repos = try JSONDecoder().decode([Repo].self, from: data)
            } catch {
                throw GitHubAPIError.decoding(error.localizedDescription)
            }
            results.append(contentsOf: repos.map {
                RepositorySummary(fullName: $0.full_name, isPrivate: $0.private, ownerLogin: $0.owner.login)
            })
            if repos.count < 100 { break }   // last page
        }
        return results
    }

    // MARK: - Comment deep-link resolution

    /// Resolves a comment's API URL (e.g. the notification's `latest_comment_url`)
    /// to its browser `html_url`, which carries the exact `#discussion_r…` /
    /// `#issuecomment-…` anchor so the browser scrolls straight to the comment.
    /// Returns nil on any failure so the caller can fall back to the thread URL.
    func resolveCommentTarget(commentAPIURL: String) async -> NotificationTarget? {
        guard let url = URL(string: commentAPIURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitHubNotifier/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, http) = try? await send(request), http.statusCode == 200 else { return nil }
        struct CommentRef: Decodable {
            let html_url: String?
            let body: String?
            let user: User?
            struct User: Decodable { let login: String }
        }
        guard let comment = try? JSONDecoder().decode(CommentRef.self, from: data),
              let htmlURL = comment.html_url else { return nil }
        return NotificationTarget(
            url: htmlURL,
            preview: Self.previewText(comment.body),
            author: comment.user?.login
        )
    }

    /// Builds the exact browser anchor without a network round-trip for issue
    /// comments. The Notifications API gives both the thread URL and a stable
    /// comment id, so this remains reliable even when resolving the API URL
    /// fails temporarily.
    static func localCommentHTMLURL(commentAPIURL: String, threadHTMLURL: String) -> String? {
        guard let components = URLComponents(string: commentAPIURL) else { return nil }
        let parts = components.path.split(separator: "/")
        guard parts.count >= 3 else { return nil }

        if parts.dropLast().suffix(2).elementsEqual(["issues", "comments"]),
           let id = parts.last, id.allSatisfy(\.isNumber) {
            return "\(threadHTMLURL)#issuecomment-\(id)"
        }
        return nil
    }

    /// Review requests do not identify a comment. Open the PR's review surface
    /// rather than the conversation header, which previously looked like a
    /// failed scroll.
    static func reviewURL(from threadHTMLURL: String) -> String {
        guard var components = URLComponents(string: threadHTMLURL),
              components.path.contains("/pull/") else { return threadHTMLURL }
        components.fragment = nil
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/files"
        components.path = "/" + components.path
        return components.url?.absoluteString ?? threadHTMLURL
    }

    /// Finds the exact comment to scroll to when the notification's
    /// `latest_comment_url` doesn't point at a real comment (GitHub often returns
    /// the PR/issue itself). Scans the thread's issue comments, PR review
    /// comments, and reviews, and returns the `html_url` (with its `#anchor`) of
    /// the most recent one that @mentions `login` — or the most recent overall.
    /// Returns nil if nothing usable is found.
    func findScrollTarget(repoFullName: String, number: Int?, isPR: Bool,
                          login: String?, preferMention: Bool,
                          notificationDate: Date) async -> NotificationTarget? {
        guard let number else { return nil }
        let parts = repoFullName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let owner = String(parts[0]), repo = String(parts[1])

        async let issueComments = fetchThreadComments(
            path: "repos/\(owner)/\(repo)/issues/\(number)/comments",
            dateKey: .created
        )

        var candidates = await issueComments
        if isPR {
            async let reviewComments = fetchThreadComments(
                path: "repos/\(owner)/\(repo)/pulls/\(number)/comments",
                dateKey: .created
            )
            async let reviews = fetchThreadComments(
                path: "repos/\(owner)/\(repo)/pulls/\(number)/reviews",
                dateKey: .submitted
            )
            candidates += await reviewComments
            candidates += await reviews
        }
        guard !candidates.isEmpty else { return nil }

        if preferMention, let login {
            let needle = "@\(login)".lowercased()
            let mentions = candidates.filter { $0.body.lowercased().contains(needle) }
            if let best = Self.closestComment(in: mentions, to: notificationDate) {
                return NotificationTarget(
                    url: best.htmlURL,
                    preview: Self.previewText(best.body),
                    author: best.author
                )
            }
        }
        guard let best = Self.closestComment(in: candidates, to: notificationDate) else { return nil }
        return NotificationTarget(
            url: best.htmlURL,
            preview: Self.previewText(best.body),
            author: best.author
        )
    }

    /// Prefer a comment at or just before the notification timestamp. This
    /// avoids jumping farther down to a newer comment added after the alert.
    private static func closestComment(in candidates: [ThreadComment], to date: Date) -> ThreadComment? {
        let tolerance: TimeInterval = 60
        let eligible = candidates.filter { $0.date <= date.addingTimeInterval(tolerance) }
        if !eligible.isEmpty {
            return eligible.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        return candidates.min { $0.date < $1.date }
    }

    /// Fetches the PR/issue description used as the preview for review requests.
    func fetchThreadPreview(repoFullName: String, number: Int?, isPR: Bool) async -> String? {
        guard let number else { return nil }
        let parts = repoFullName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let kind = isPR ? "pulls" : "issues"
        let path = "repos/\(parts[0])/\(parts[1])/\(kind)/\(number)"
        guard let (data, http) = try? await send(makeRequest(path: path)), http.statusCode == 200 else {
            return nil
        }
        struct Thread: Decodable { let body: String? }
        return (try? JSONDecoder().decode(Thread.self, from: data)).flatMap { Self.previewText($0.body) }
    }

    /// Finds who requested the review from the PR timeline event nearest to the
    /// notification. The Notifications API itself does not include this actor.
    func fetchReviewRequester(repoFullName: String, number: Int?, login: String?,
                              notificationDate: Date) async -> String? {
        guard let number else { return nil }
        let parts = repoFullName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let path = "repos/\(parts[0])/\(parts[1])/issues/\(number)/timeline"
        guard let data = await fetchLastPageData(path: path) else { return nil }

        struct Event: Decodable {
            let event: String?
            let created_at: Date?
            let actor: User?
            let requested_reviewer: User?
            struct User: Decodable { let login: String }
        }
        let events = (try? Self.decoder.decode([Event].self, from: data)) ?? []
        let matching = events.filter { event in
            guard event.event == "review_requested", event.created_at != nil else { return false }
            guard let login else { return true }
            return event.requested_reviewer?.login.caseInsensitiveCompare(login) == .orderedSame
                || event.requested_reviewer == nil
        }
        return matching.min {
            abs(($0.created_at ?? .distantPast).timeIntervalSince(notificationDate))
                < abs(($1.created_at ?? .distantPast).timeIntervalSince(notificationDate))
        }?.actor?.login
    }

    /// Converts a Markdown body into a compact, single-line preview.
    static func previewText(_ body: String?, limit: Int = 180) -> String? {
        guard var text = body?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        let replacements = [
            (#"(?s)```.*?```"#, " "),
            (#"!\[[^\]]*\]\([^\)]*\)"#, " "),
            (#"\[([^\]]+)\]\([^\)]*\)"#, "$1"),
            (#"[`*_>#~|]"#, " "),
            (#"\s+"#, " ")
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.count > limit {
            return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return text
    }

    private struct ThreadComment {
        let date: Date
        let htmlURL: String
        let body: String
        let author: String?
    }

    private enum CommentDateKey { case created, submitted }

    /// Fetches the most recent page of a paginated comment/review list.
    private func fetchThreadComments(path: String, dateKey: CommentDateKey) async -> [ThreadComment] {
        guard let data = await fetchLastPageData(path: path) else { return [] }
        struct Raw: Decodable {
            let html_url: String?
            let body: String?
            let created_at: Date?
            let submitted_at: Date?
            let user: User?
            struct User: Decodable { let login: String }
        }
        let raw = (try? Self.decoder.decode([Raw].self, from: data)) ?? []
        return raw.compactMap { item in
            guard let html = item.html_url else { return nil }
            let date = (dateKey == .created ? item.created_at : item.submitted_at)
            guard let date else { return nil }
            return ThreadComment(
                date: date,
                htmlURL: html,
                body: item.body ?? "",
                author: item.user?.login
            )
        }
    }

    /// GETs page 1 (per_page=100) and, if the Link header advertises more pages,
    /// the last page — so we see the newest comments regardless of thread length.
    private func fetchLastPageData(path: String) async -> Data? {
        let firstQuery = [URLQueryItem(name: "per_page", value: "100")]
        guard let (data1, http1) = try? await send(makeRequest(path: path, query: firstQuery)),
              http1.statusCode == 200 else { return nil }

        if let link = http1.value(forHTTPHeaderField: "Link"),
           let last = Self.lastPage(fromLinkHeader: link), last > 1 {
            let lastQuery = [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(last))
            ]
            if let (dataN, httpN) = try? await send(makeRequest(path: path, query: lastQuery)),
               httpN.statusCode == 200 {
                return dataN
            }
        }
        return data1
    }

    /// Parses the `page=N` of the `rel="last"` entry from a Link header.
    static func lastPage(fromLinkHeader link: String) -> Int? {
        for part in link.split(separator: ",") {
            guard part.contains("rel=\"last\"") else { continue }
            guard let range = part.range(of: "page=") else { continue }
            let tail = part[range.upperBound...]
            let digits = tail.prefix { $0.isNumber }
            return Int(digits)
        }
        return nil
    }

    // MARK: - Notifications (conditional poll)

    /// Polls `/notifications` with an ETag conditional request. Returns 304-aware result.
    func pollNotifications(etag: String?, includeRead: Bool = true) async throws -> NotificationsPollResult {
        let query = [
            URLQueryItem(name: "all", value: includeRead ? "true" : "false"),
            URLQueryItem(name: "per_page", value: "50")
        ]
        let request = makeRequest(path: "notifications", query: query, etag: etag)
        let (data, http) = try await send(request)

        let newETag = http.value(forHTTPHeaderField: "ETag")
        let pollInterval = http.value(forHTTPHeaderField: "X-Poll-Interval").flatMap { Int($0) }

        if http.statusCode == 304 {
            return NotificationsPollResult(notifications: [], etag: etag, pollIntervalSeconds: pollInterval, notModified: true)
        }
        guard http.statusCode == 200 else { throw GitHubAPIError.http(http.statusCode) }

        let decoded: [APINotification]
        do {
            decoded = try Self.decoder.decode([APINotification].self, from: data)
        } catch {
            throw GitHubAPIError.decoding(error.localizedDescription)
        }
        let mapped = decoded.compactMap { $0.toDomain() }
        return NotificationsPollResult(notifications: mapped, etag: newETag, pollIntervalSeconds: pollInterval, notModified: false)
    }

    /// Marks one GitHub notification thread as read.
    func markNotificationRead(id: String) async throws {
        var request = makeRequest(path: "notifications/threads/\(id)")
        request.httpMethod = "PATCH"
        let (_, http) = try await send(request)
        guard [200, 204, 205].contains(http.statusCode) else {
            throw GitHubAPIError.http(http.statusCode)
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - GitHub API DTOs

private struct APINotification: Decodable {
    let id: String
    let reason: String
    let unread: Bool
    let updated_at: Date
    let subject: Subject
    let repository: Repository

    struct Subject: Decodable {
        let title: String
        let url: String?
        let latest_comment_url: String?
        let type: String   // "PullRequest", "Issue", ...
    }
    struct Repository: Decodable {
        let full_name: String
        let owner: Owner
        struct Owner: Decodable { let login: String }
    }

    func toDomain() -> GitHubNotification? {
        let type = NotificationType.from(reason: reason, subjectType: subject.type)
        // Keep the canonical thread URL as the fallback. A latest-comment API
        // URL such as `/issues/comments/123` does not contain the issue number
        // and cannot be converted into a valid thread URL on its own.
        let browserURL = APINotification.htmlURL(
            apiURL: subject.url,
            fallbackRepo: repository.full_name
        )
        let number = APINotification.extractNumber(from: subject.url)
        return GitHubNotification(
            id: id,
            repositoryName: repository.full_name,
            organizationName: repository.owner.login,
            notificationType: type,
            title: subject.title,
            number: number,
            author: nil,
            url: browserURL,
            commentAPIURL: subject.latest_comment_url,
            isPullRequest: subject.type == "PullRequest",
            isUnread: unread,
            updatedAt: updated_at
        )
    }

    /// Best-effort conversion of an api.github.com subject URL into a browser URL.
    /// Avoids an extra network round-trip per notification.
    static func htmlURL(apiURL: String?, fallbackRepo: String) -> String {
        guard let apiURL, apiURL.contains("api.github.com") else {
            return "https://github.com/\(fallbackRepo)"
        }
        var url = apiURL.replacingOccurrences(of: "https://api.github.com/repos", with: "https://github.com")
        url = url.replacingOccurrences(of: "/pulls/", with: "/pull/")
        // Comment endpoints look like .../issues/comments/123 — collapse to the thread anchor.
        if let range = url.range(of: "/comments/") {
            let commentID = String(url[range.upperBound...])
            let base = String(url[..<range.lowerBound])
            let thread = base.replacingOccurrences(of: "/issues/comments", with: "")
            url = "\(thread)#issuecomment-\(commentID)"
        }
        return url
    }

    static func extractNumber(from apiURL: String?) -> Int? {
        guard let apiURL else { return nil }
        let parts = apiURL.split(separator: "/")
        for (idx, part) in parts.enumerated() where part == "pulls" || part == "issues" {
            if idx + 1 < parts.count { return Int(parts[idx + 1]) }
        }
        return nil
    }
}
