import Foundation

// MARK: - GitHub Integration
// The GitHub App installations, the repositories bound to a project and the GitHub issues
// linked to a change request — trm's contracts C4 and C6, on trm-bff's routes (no
// /rest/trm/v1 prefix). Ported from trm/src/apiCalls/githubApis.js and
// src/utilities/githubIntegration.js, as the cai web's requests/githubApis.js mirrors them.

/// GET /github/app → `{appSlug, installUrl}`. The install URL carries a signed state that
/// expires after 10 minutes, so it's fetched fresh on every Connect.
struct GitHubApp: Decodable, Equatable {
    let appSlug: String?
    let installUrl: String?

    /// The install URL, only when it's a real https link.
    var installURL: URL? {
        guard let installUrl, installUrl.lowercased().hasPrefix("https://") else { return nil }
        return URL(string: installUrl)
    }
}

/// One connected GitHub account (an App installation bound to the organization).
struct GitHubInstallation: Identifiable, Decodable, Hashable {
    let installationId: Int64
    let accountLogin: String
    /// "Organization" or "User".
    let accountType: String
    /// "active", "suspended" or "deleted".
    let status: String
    let createdAt: Date?

    var id: Int64 { installationId }

    init(installationId: Int64, accountLogin: String, accountType: String = "Organization",
         status: String = "active", createdAt: Date? = nil) {
        self.installationId = installationId
        self.accountLogin = accountLogin
        self.accountType = accountType
        self.status = status
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case installationId, accountLogin, accountType, status, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installationId = c.lenientInt64(.installationId) ?? 0
        accountLogin = c.lenient(.accountLogin) ?? ""
        accountType = c.lenient(.accountType) ?? ""
        status = c.lenient(.status) ?? ""
        createdAt = (c.lenient(.createdAt) as String?).flatMap(GitHubDate.parse)
    }

    var accountTypeLabel: String { accountType == "User" ? "User" : "Organization" }
    var statusLabel: String { GitHubIntegration.accountStatusLabels[status] ?? status }
    /// A missing status counts as active, as the web's Add repository filter reads it.
    var isActive: Bool { status.isEmpty || status == "active" }
}

/// A repository the App can see: GET /github/installations/{id}/repos.
struct GitHubRepo: Identifiable, Decodable, Hashable {
    let nodeId: String
    let fullName: String
    let defaultBranch: String
    let isPrivate: Bool

    var id: String { nodeId.isEmpty ? fullName : nodeId }

    init(nodeId: String, fullName: String, defaultBranch: String = "main", isPrivate: Bool = false) {
        self.nodeId = nodeId
        self.fullName = fullName
        self.defaultBranch = defaultBranch
        self.isPrivate = isPrivate
    }

    private enum CodingKeys: String, CodingKey { case nodeId, fullName, defaultBranch, `private` }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodeId = c.lenient(.nodeId) ?? ""
        fullName = c.lenient(.fullName) ?? ""
        defaultBranch = c.lenient(.defaultBranch) ?? ""
        isPrivate = c.lenient(.private) ?? false
    }
}

/// A repository bound to a project: GET /projects/{id}/repos.
struct ProjectRepo: Identifiable, Decodable, Hashable {
    let id: String
    let installationId: Int64?
    let repoNodeId: String
    let fullName: String
    let defaultBranch: String

    init(id: String, installationId: Int64? = nil, repoNodeId: String = "", fullName: String,
         defaultBranch: String = "") {
        self.id = id
        self.installationId = installationId
        self.repoNodeId = repoNodeId
        self.fullName = fullName
        self.defaultBranch = defaultBranch
    }

    private enum CodingKeys: String, CodingKey { case id, installationId, repoNodeId, fullName, defaultBranch }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        installationId = c.lenientInt64(.installationId)
        repoNodeId = c.lenient(.repoNodeId) ?? ""
        fullName = c.lenient(.fullName) ?? ""
        defaultBranch = c.lenient(.defaultBranch) ?? ""
    }

    var githubURL: URL? { URL(string: "https://github.com/\(fullName)") }
}

/// A GitHub issue linked to a change request: GET /change-requests/{id}/issues.
struct GitHubIssueLink: Identifiable, Decodable, Hashable {
    let id: String
    let repoFullName: String
    let number: Int
    let url: String
    let title: String
    /// "open" or "closed".
    let state: String
    /// "created" (made from BlueRequests) or "linked" (an existing issue).
    let origin: String
    /// The user id that made the link.
    let linkedBy: String?
    let linkedAt: Date?

    init(id: String, repoFullName: String, number: Int, url: String = "", title: String = "",
         state: String = "open", origin: String = "created", linkedBy: String? = nil, linkedAt: Date? = nil) {
        self.id = id
        self.repoFullName = repoFullName
        self.number = number
        self.url = url
        self.title = title
        self.state = state
        self.origin = origin
        self.linkedBy = linkedBy
        self.linkedAt = linkedAt
    }

    private enum CodingKeys: String, CodingKey { case id, repoFullName, number, url, title, state, origin, linkedBy, linkedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        repoFullName = c.lenient(.repoFullName) ?? ""
        number = c.lenient(.number) ?? 0
        url = c.lenient(.url) ?? ""
        title = c.lenient(.title) ?? ""
        state = c.lenient(.state) ?? ""
        origin = c.lenient(.origin) ?? ""
        linkedBy = (c.lenient(.linkedBy) as String?).flatMap { $0.isEmpty ? nil : $0 }
        linkedAt = (c.lenient(.linkedAt) as String?).flatMap(GitHubDate.parse)
    }

    var isOpen: Bool { state == "open" }
    var stateLabel: String { GitHubIntegration.issueStateLabels[state] ?? state }
    var originLabel: String { GitHubIntegration.issueOriginLabels[origin] ?? origin }
    var issueURL: URL? { url.isEmpty ? nil : URL(string: url) }
}

/// GET lists answer an array; tolerate null, a blank body or a non-array body (the web's `asList`).
struct GitHubList<Element: Decodable>: Decodable, EmptyDecodableResponse {
    let items: [Element]

    static var empty: GitHubList<Element> { GitHubList(items: []) }

    init(items: [Element]) { self.items = items }

    init(from decoder: Decoder) throws {
        items = (try? decoder.singleValueContainer().decode([Element].self)) ?? []
    }
}

/// POST /projects/{id}/repos.
struct AddProjectRepoPayload: Encodable, Equatable {
    let installationId: Int64
    let repoNodeId: String
    let fullName: String
}

/// POST /change-requests/{id}/issues: create `{projectRepoId, mode: "create", title?, body?}`
/// or link `{projectRepoId, mode: "link", number}`. An empty title or body is left out,
/// so the backend uses the change request's title.
struct IssueLinkPayload: Encodable, Equatable {
    let projectRepoId: String
    let mode: String
    var title: String?
    var body: String?
    var number: Int?

    static func create(projectRepoId: String, title: String? = nil, body: String? = nil) -> IssueLinkPayload {
        IssueLinkPayload(projectRepoId: projectRepoId, mode: "create",
                         title: title.flatMap { $0.isEmpty ? nil : $0 },
                         body: body.flatMap { $0.isEmpty ? nil : $0 })
    }

    static func link(projectRepoId: String, number: Int) -> IssueLinkPayload {
        IssueLinkPayload(projectRepoId: projectRepoId, mode: "link", number: number)
    }
}

// MARK: - Dates

/// Go's time.Time arrives as RFC 3339 with up to nine fractional digits, which
/// ISO8601DateFormatter doesn't always read: trim them to milliseconds first.
enum GitHubDate {
    static func parse(_ string: String) -> Date? {
        if let date = Date.fromISO8601(string) { return date }
        guard let dot = string.firstIndex(of: ".") else { return nil }
        let afterDot = string[string.index(after: dot)...]
        let digits = afterDot.prefix { $0.isNumber }
        let rest = afterDot.dropFirst(digits.count)
        let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return Date.fromISO8601(String(string[..<dot]) + "." + millis + String(rest))
    }
}

extension KeyedDecodingContainer {
    /// An integer id that may arrive as a number or a numeric string.
    func lenientInt64(_ key: Key) -> Int64? {
        if let value: Int64 = lenient(key) { return value }
        if let string: String = lenient(key) { return Int64(string) }
        return nil
    }
}

// MARK: - Errors and wording
// trm's githubIntegration.js: error codes to messages, how a failed load renders, the
// issue-number parser and the create/link timeout handling. The words are trm's.

/// How a failed load renders (the web's `loadFailureKind`).
enum GitHubLoadFailure: Equatable {
    /// 403 not_available_in_public_tenant.
    case publicTenant
    /// The endpoint is missing or not set up (404/501/502/503, github_not_configured).
    case unavailable
    /// Any other 403.
    case forbidden
    /// Anything else.
    case error
}

/// A screen's load state: loading, loaded, or failed in one of the ways above.
enum GitHubLoadState: Equatable {
    case loading
    case ready
    case failed(GitHubLoadFailure)
}

enum GitHubIssueMode: String, Identifiable {
    case create, link
    var id: String { rawValue }
}

enum GitHubIntegration {
    static let errorMessages: [String: String] = [
        "invalid_state": "The install link is invalid or has expired. Start again with Connect GitHub.",
        "installation_not_accessible": "Your GitHub account cannot access this installation. Sign in to GitHub as an owner of the account the app was installed on, then try again.",
        "already_bound": "This GitHub installation is already connected to another organization.",
        "installation_not_bound": "This GitHub installation is not connected to your organization. Connect it again on the Git page.",
        "binding_in_use": "This repository is linked to change requests and cannot be removed yet.",
        "repo_not_in_installation": "The GitHub App does not have access to this repository.",
        "not_available_in_public_tenant": "GitHub integration is only available to organizations. Your account is not part of one.",
        "github_not_configured": "GitHub integration is not set up on this server yet.",
        "github_timeout": "GitHub did not answer in time. Please try again.",
        "github_error": "The request to GitHub failed. Please try again.",
        "forbidden": "You do not have permission to do this.",
        "not_found": "It no longer exists. Refresh the page and try again.",
        // Change request issue links (contract C6).
        "already_linked": "This issue is already linked to this change request.",
        "not_tech_template": "GitHub issues can only be linked to change requests created from a tech template.",
        "repo_not_bound_to_project": "This repository is not bound to the change request's project. Pick another repository, or bind it on the project page.",
        "issue_not_found": "No issue with this number exists in the repository. Pull requests cannot be linked as issues.",
    ]

    static let unavailableMessage = "GitHub integration is not available yet. Please try again later."

    /// On a project's repositories, already_bound means the repository, not the installation.
    static let repoErrorOverrides = ["already_bound": "This repository is already bound to this project."]

    static let accountStatusLabels = ["active": "Active", "suspended": "Suspended", "deleted": "Deleted"]
    static let issueStateLabels = ["open": "Open", "closed": "Closed"]
    static let issueOriginLabels = ["created": "Created", "linked": "Linked"]

    /// After a timeout the workflow may still finish, so a blind retry could make a second
    /// issue: say so, and the list is reloaded.
    static let issueTimeoutMessages: [GitHubIssueMode: String] = [
        .create: "GitHub did not answer in time. The issue may still have been created: check the list, which has been refreshed, before you try again.",
        .link: "GitHub did not answer in time. The issue may still have been linked: check the list, which has been refreshed, before you try again.",
    ]

    /// Create and link wait on a worker workflow; after this long the dialog says so.
    static let slowRequestDelay: TimeInterval = 4

    // MARK: Roles (admin-trm client roles)

    /// Connect / disconnect installations: admin, super-admin.
    static func canManage(roles: [String]) -> Bool {
        roles.contains("admin") || roles.contains("super-admin")
    }

    /// Bind / unbind project repos: admin, super-admin, release-manager.
    static func canBindProjectRepos(roles: [String]) -> Bool {
        canManage(roles: roles) || roles.contains("release-manager")
    }

    // MARK: Errors

    private static func isCode(_ text: String) -> Bool {
        text.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil
    }

    /// The HTTP status of a failed request, when there was an answer.
    static func status(of error: Error) -> Int? {
        switch error {
        case RequestsAPIError.rejected(let status, _, _): return status
        case RequestsAPIError.serverError(let status, _): return status
        case RequestsAPIError.requestsUnavailable(let status): return status
        default: return nil
        }
    }

    /// The error code of a failed request: the `{"error":{"code"}}` envelope's code, or a
    /// bare code (or a known code inside the text) where the body was plain.
    static func errorCode(_ error: Error) -> String? {
        switch error {
        case RequestsAPIError.rejected(_, let code, _):
            return isCode(code) ? code : nil
        case RequestsAPIError.serverError(_, let message):
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if isCode(text) { return text }
            // Longest first, so issue_not_found isn't read as not_found.
            return errorMessages.keys.sorted { ($0.count, $1) > ($1.count, $0) }.first { text.contains($0) }
        default:
            return nil
        }
    }

    static func loadFailureKind(_ error: Error) -> GitHubLoadFailure {
        let code = errorCode(error)
        if code == "not_available_in_public_tenant" { return .publicTenant }
        if code == "github_not_configured" { return .unavailable }
        let status = status(of: error)
        if let status, [404, 501, 502, 503].contains(status) { return .unavailable }
        if status == 403 { return .forbidden }
        return .error
    }

    /// A readable message for a failed request. `overrides` maps codes to messages where
    /// the same code means something else (already_bound on a project repo).
    static func errorMessage(_ error: Error, fallback: String, overrides: [String: String] = [:]) -> String {
        let code = errorCode(error)
        if let code, let message = overrides[code] { return message }
        if let code, let message = errorMessages[code] { return message }
        switch loadFailureKind(error) {
        case .unavailable: return unavailableMessage
        case .forbidden: return errorMessages["forbidden"]!
        default: break
        }
        if case RequestsAPIError.rejected(let status, _, let message) = error,
           !message.isBlank, message != "HTTP \(status)" {
            return message
        }
        return fallback
    }

    /// True when a create/link timed out: 504 github_timeout from the backend, a bare 504
    /// from the gateway, or no answer at all.
    static func isTimeout(_ error: Error) -> Bool {
        if errorCode(error) == "github_timeout" { return true }
        if let status = status(of: error) { return status == 504 }
        switch error {
        case RequestsAPIError.networkError: return true
        case is URLError: return true
        default: return false
        }
    }

    static func issueErrorMessage(_ error: Error, mode: GitHubIssueMode) -> String {
        if isTimeout(error) { return issueTimeoutMessages[mode]! }
        return errorMessage(error, fallback: mode == .create
                            ? "Could not create the issue. Please try again."
                            : "Could not link the issue. Please try again.")
    }

    /// A positive issue number typed by the user ("15" or "#15"), or nil.
    static func parseIssueNumber(_ text: String) -> Int? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(value), number > 0, number <= 9_007_199_254_740_991 else { return nil }
        return number
    }

    /// Only requests created from a tech template have GitHub issues; the backend answers
    /// 422 not_tech_template for any other.
    static func isTechRequest(_ changeRequest: ChangeRequest?) -> Bool {
        changeRequest?.templateKind == RQTemplateKind.tech.rawValue
    }

    /// New request: why the issue wasn't created, shown on the new request's detail.
    static func issueFailureNotice(_ message: String) -> String {
        "The change request was created, but the GitHub issue was not: \(message) Open the change request's GitHub tab to try again."
    }
}
