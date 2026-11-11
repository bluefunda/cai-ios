import Foundation

// MARK: - GitHub Service
// trm/src/apiCalls/githubApis.js on the app's client: GitHub App installations, the repos
// bound to a project (contract C4) and the issues linked to a change request (C6). All
// trm-bff routes, so no /rest/trm/v1 prefix. The install callback isn't here: the App's
// setup URL points at the trm web, which finishes the install.

protocol GitHubServicing {
    /// GET /github/app → `{appSlug, installUrl}`.
    func app() async throws -> GitHubApp
    /// GET /github/installations.
    func installations() async throws -> [GitHubInstallation]
    /// DELETE /github/installations/{id} (admin, super-admin). Unbinds in BlueRequests
    /// only; the App stays installed on GitHub.
    func deleteInstallation(id: Int64) async throws
    /// GET /github/installations/{id}/repos.
    func installationRepos(installationId: Int64) async throws -> [GitHubRepo]
    /// GET /projects/{id}/repos.
    func projectRepos(projectId: String) async throws -> [ProjectRepo]
    /// POST /projects/{id}/repos (admin, super-admin, release-manager). nil when the
    /// binding was made but the answer didn't carry it: reload.
    func addProjectRepo(projectId: String, _ payload: AddProjectRepoPayload) async throws -> ProjectRepo?
    /// DELETE /projects/{id}/repos/{bindingId} (admin, super-admin, release-manager).
    func deleteProjectRepo(projectId: String, bindingId: String) async throws
    /// GET /change-requests/{id}/issues.
    func issues(changeRequestId: String) async throws -> [GitHubIssueLink]
    /// POST /change-requests/{id}/issues — create or link. Waits on a worker workflow, so
    /// it can take several seconds (the gateway allows 20). nil: made, reload to see it.
    func addIssue(changeRequestId: String, _ payload: IssueLinkPayload) async throws -> GitHubIssueLink?
    /// DELETE /change-requests/{id}/issues/{linkId}. Unlinks in BlueRequests only; the
    /// issue is unchanged on GitHub.
    func unlinkIssue(changeRequestId: String, linkId: String) async throws
}

struct GitHubService: GitHubServicing {
    let client: RequestsAPIClient

    func app() async throws -> GitHubApp {
        try await client.get("/github/app")
    }

    func installations() async throws -> [GitHubInstallation] {
        let list: GitHubList<GitHubInstallation> = try await client.get("/github/installations")
        return list.items
    }

    func deleteInstallation(id: Int64) async throws {
        try await client.deleteDiscardingResponse("/github/installations/\(id)")
    }

    func installationRepos(installationId: Int64) async throws -> [GitHubRepo] {
        let list: GitHubList<GitHubRepo> = try await client.get("/github/installations/\(installationId)/repos")
        return list.items
    }

    func projectRepos(projectId: String) async throws -> [ProjectRepo] {
        let list: GitHubList<ProjectRepo> = try await client.get("/projects/\(Self.escaped(projectId))/repos")
        return list.items
    }

    func addProjectRepo(projectId: String, _ payload: AddProjectRepoPayload) async throws -> ProjectRepo? {
        let repo: ProjectRepo? = try await client.postDecodingIfPresent(
            "/projects/\(Self.escaped(projectId))/repos", body: payload)
        return repo.flatMap { $0.id.isEmpty ? nil : $0 }
    }

    func deleteProjectRepo(projectId: String, bindingId: String) async throws {
        try await client.deleteDiscardingResponse(
            "/projects/\(Self.escaped(projectId))/repos/\(Self.escaped(bindingId))")
    }

    func issues(changeRequestId: String) async throws -> [GitHubIssueLink] {
        let list: GitHubList<GitHubIssueLink> = try await client.get(
            "/change-requests/\(Self.escaped(changeRequestId))/issues")
        return list.items
    }

    func addIssue(changeRequestId: String, _ payload: IssueLinkPayload) async throws -> GitHubIssueLink? {
        let link: GitHubIssueLink? = try await client.postDecodingIfPresent(
            "/change-requests/\(Self.escaped(changeRequestId))/issues", body: payload)
        return link.flatMap { $0.id.isEmpty ? nil : $0 }
    }

    func unlinkIssue(changeRequestId: String, linkId: String) async throws {
        try await client.deleteDiscardingResponse(
            "/change-requests/\(Self.escaped(changeRequestId))/issues/\(Self.escaped(linkId))")
    }

    /// The web's encodeURIComponent for a path segment.
    static func escaped(_ segment: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }
}

// MARK: - Fixtures

/// For `-requests_fixtures` runs: one connected organization with two repos, one bound to
/// every project, and no linked issues until some are made.
final class FixtureGitHubService: GitHubServicing {
    private var linked: [String: [GitHubIssueLink]] = [:]
    private let repos = [
        GitHubRepo(nodeId: "R_1", fullName: "bluefunda/trm-backend-go", defaultBranch: "main", isPrivate: true),
        GitHubRepo(nodeId: "R_2", fullName: "bluefunda/trm", defaultBranch: "main"),
    ]

    func app() async throws -> GitHubApp {
        GitHubApp(appSlug: "bluerequests", installUrl: "https://github.com/apps/bluerequests/installations/new")
    }

    func installations() async throws -> [GitHubInstallation] {
        [GitHubInstallation(installationId: 1, accountLogin: "bluefunda", createdAt: Date(timeIntervalSince1970: 1_790_000_000))]
    }

    func deleteInstallation(id: Int64) async throws {}

    func installationRepos(installationId: Int64) async throws -> [GitHubRepo] { repos }

    func projectRepos(projectId: String) async throws -> [ProjectRepo] {
        [ProjectRepo(id: "pr-1", installationId: 1, repoNodeId: "R_1", fullName: repos[0].fullName, defaultBranch: "main")]
    }

    func addProjectRepo(projectId: String, _ payload: AddProjectRepoPayload) async throws -> ProjectRepo? {
        ProjectRepo(id: UUID().uuidString, installationId: payload.installationId, repoNodeId: payload.repoNodeId,
                    fullName: payload.fullName, defaultBranch: "main")
    }

    func deleteProjectRepo(projectId: String, bindingId: String) async throws {}

    func issues(changeRequestId: String) async throws -> [GitHubIssueLink] { linked[changeRequestId] ?? [] }

    func addIssue(changeRequestId: String, _ payload: IssueLinkPayload) async throws -> GitHubIssueLink? {
        let number = payload.number ?? (linked[changeRequestId]?.count ?? 0) + 101
        let link = GitHubIssueLink(
            id: UUID().uuidString, repoFullName: repos[0].fullName, number: number,
            url: "https://github.com/\(repos[0].fullName)/issues/\(number)",
            title: payload.title ?? "Issue #\(number)", state: "open",
            origin: payload.mode == "link" ? "linked" : "created", linkedAt: Date())
        linked[changeRequestId, default: []].append(link)
        return link
    }

    func unlinkIssue(changeRequestId: String, linkId: String) async throws {
        linked[changeRequestId]?.removeAll { $0.id == linkId }
    }
}
