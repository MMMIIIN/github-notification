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
    func resolveCommentHTMLURL(commentAPIURL: String) async -> String? {
        guard let url = URL(string: commentAPIURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitHubNotifier/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, http) = try? await send(request), http.statusCode == 200 else { return nil }
        struct CommentRef: Decodable { let html_url: String? }
        return (try? JSONDecoder().decode(CommentRef.self, from: data))?.html_url
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
        let browserURL = APINotification.htmlURL(
            apiURL: subject.latest_comment_url ?? subject.url,
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
