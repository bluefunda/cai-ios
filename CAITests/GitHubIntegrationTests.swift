import XCTest
@testable import CAI

// MARK: - GitHub Integration Tests
// The trm web's githubIntegration.js helpers (error codes, load failures, issue numbers,
// timeouts), the trm-bff routes GitHubService calls (githubApis.js), and the view models
// behind the Git destination, a project's Repositories, a request's GitHub tab and New
// request's "Create GitHub issue".

// MARK: - Helpers

final class GitHubIntegrationHelperTests: XCTestCase {
    private func rejected(_ status: Int, _ code: String, _ message: String = "") -> Error {
        RequestsAPIError.rejected(status: status, code: code, message: message.isEmpty ? "HTTP \(status)" : message)
    }

    func test_errorCode_readsEnvelopeBareAndEmbeddedCodes() {
        XCTAssertEqual(GitHubIntegration.errorCode(rejected(409, "already_bound")), "already_bound")
        XCTAssertEqual(GitHubIntegration.errorCode(RequestsAPIError.serverError(422, "not_tech_template")), "not_tech_template")
        XCTAssertEqual(GitHubIntegration.errorCode(RequestsAPIError.serverError(500, "failed: binding_in_use (2 links)")),
                       "binding_in_use")
        XCTAssertEqual(GitHubIntegration.errorCode(RequestsAPIError.serverError(404, "{\"error\":\"issue_not_found\"}")),
                       "issue_not_found", "the longer code wins over not_found")
        XCTAssertNil(GitHubIntegration.errorCode(RequestsAPIError.serverError(500, "Something broke")))
        XCTAssertNil(GitHubIntegration.errorCode(RequestsAPIError.requestsUnavailable(statusCode: 403)))
        XCTAssertNil(GitHubIntegration.errorCode(URLError(.timedOut)))
    }

    func test_loadFailureKind() {
        XCTAssertEqual(GitHubIntegration.loadFailureKind(rejected(403, "not_available_in_public_tenant")), .publicTenant)
        XCTAssertEqual(GitHubIntegration.loadFailureKind(rejected(500, "github_not_configured")), .unavailable)
        for status in [404, 501, 502, 503] {
            XCTAssertEqual(GitHubIntegration.loadFailureKind(RequestsAPIError.serverError(status, "HTTP \(status)")),
                           .unavailable, "HTTP \(status)")
        }
        XCTAssertEqual(GitHubIntegration.loadFailureKind(RequestsAPIError.requestsUnavailable(statusCode: 403)), .forbidden)
        XCTAssertEqual(GitHubIntegration.loadFailureKind(rejected(403, "forbidden")), .forbidden)
        XCTAssertEqual(GitHubIntegration.loadFailureKind(RequestsAPIError.requestsUnavailable(statusCode: 401)), .error)
        XCTAssertEqual(GitHubIntegration.loadFailureKind(RequestsAPIError.serverError(500, "HTTP 500")), .error)
        XCTAssertEqual(GitHubIntegration.loadFailureKind(RequestsAPIError.networkError(URLError(.timedOut))), .error)
    }

    func test_errorMessage_overridesKnownCodesUnavailableForbiddenServerMessageAndFallback() {
        let fallback = "Could not add the repository. Please try again."
        XCTAssertEqual(GitHubIntegration.errorMessage(rejected(409, "already_bound"), fallback: fallback,
                                                      overrides: GitHubIntegration.repoErrorOverrides),
                       "This repository is already bound to this project.")
        XCTAssertEqual(GitHubIntegration.errorMessage(rejected(409, "already_bound"), fallback: fallback),
                       "This GitHub installation is already connected to another organization.")
        XCTAssertEqual(GitHubIntegration.errorMessage(rejected(409, "binding_in_use"), fallback: fallback),
                       "This repository is linked to change requests and cannot be removed yet.")
        XCTAssertEqual(GitHubIntegration.errorMessage(RequestsAPIError.serverError(503, "HTTP 503"), fallback: fallback),
                       GitHubIntegration.unavailableMessage)
        XCTAssertEqual(GitHubIntegration.errorMessage(RequestsAPIError.requestsUnavailable(statusCode: 403), fallback: fallback),
                       "You do not have permission to do this.")
        XCTAssertEqual(GitHubIntegration.errorMessage(rejected(400, "bad_input", "Title is too long"), fallback: fallback),
                       "Title is too long")
        XCTAssertEqual(GitHubIntegration.errorMessage(rejected(400, "bad_input"), fallback: fallback), fallback)
        XCTAssertEqual(GitHubIntegration.errorMessage(RequestsAPIError.serverError(500, "boom!"), fallback: fallback), fallback)
    }

    func test_parseIssueNumber() {
        XCTAssertEqual(GitHubIntegration.parseIssueNumber("15"), 15)
        XCTAssertEqual(GitHubIntegration.parseIssueNumber("#15"), 15)
        XCTAssertEqual(GitHubIntegration.parseIssueNumber("  #42 "), 42)
        for invalid in ["", "#", "0", "#0", "-3", "1.5", "12a", "abc", "# 4", "١٢", "99999999999999999999"] {
            XCTAssertNil(GitHubIntegration.parseIssueNumber(invalid), invalid)
        }
    }

    func test_isTimeout() {
        XCTAssertTrue(GitHubIntegration.isTimeout(rejected(504, "github_timeout")))
        XCTAssertTrue(GitHubIntegration.isTimeout(rejected(502, "github_timeout")), "the code decides")
        XCTAssertTrue(GitHubIntegration.isTimeout(RequestsAPIError.serverError(504, "HTTP 504")), "a bare gateway 504")
        XCTAssertTrue(GitHubIntegration.isTimeout(RequestsAPIError.networkError(URLError(.timedOut))), "no answer at all")
        XCTAssertTrue(GitHubIntegration.isTimeout(URLError(.networkConnectionLost)))
        XCTAssertFalse(GitHubIntegration.isTimeout(RequestsAPIError.serverError(500, "HTTP 500")))
        XCTAssertFalse(GitHubIntegration.isTimeout(rejected(422, "issue_not_found")))
        XCTAssertFalse(GitHubIntegration.isTimeout(RequestsAPIError.notSignedIn))
    }

    func test_issueErrorMessage_timeoutsWarnAndOthersFallBack() {
        let timeout = RequestsAPIError.serverError(504, "HTTP 504")
        XCTAssertEqual(GitHubIntegration.issueErrorMessage(timeout, mode: .create),
                       "GitHub did not answer in time. The issue may still have been created: check the list, which has been refreshed, before you try again.")
        XCTAssertEqual(GitHubIntegration.issueErrorMessage(timeout, mode: .link),
                       "GitHub did not answer in time. The issue may still have been linked: check the list, which has been refreshed, before you try again.")
        XCTAssertEqual(GitHubIntegration.issueErrorMessage(rejected(422, "issue_not_found"), mode: .link),
                       "No issue with this number exists in the repository. Pull requests cannot be linked as issues.")
        XCTAssertEqual(GitHubIntegration.issueErrorMessage(RequestsAPIError.serverError(500, "HTTP 500"), mode: .create),
                       "Could not create the issue. Please try again.")
        XCTAssertEqual(GitHubIntegration.issueErrorMessage(RequestsAPIError.serverError(500, "HTTP 500"), mode: .link),
                       "Could not link the issue. Please try again.")
    }

    func test_roles() {
        XCTAssertTrue(GitHubIntegration.canManage(roles: ["admin"]))
        XCTAssertTrue(GitHubIntegration.canManage(roles: ["super-admin"]))
        XCTAssertFalse(GitHubIntegration.canManage(roles: ["release-manager"]))
        XCTAssertTrue(GitHubIntegration.canBindProjectRepos(roles: ["release-manager"]))
        XCTAssertTrue(GitHubIntegration.canBindProjectRepos(roles: ["admin"]))
        XCTAssertFalse(GitHubIntegration.canBindProjectRepos(roles: ["user"]))
    }

    func test_isTechRequest_readsTemplateDataKind() throws {
        func decode(_ template: String) throws -> ChangeRequest {
            let json = #"{"changeRequest":{"id":7,"shortDescription":"Fix"}\#(template)}"#
            return try RequestsAPIClient.makeDecoder().decode(ChangeRequest.self, from: Data(json.utf8))
        }
        XCTAssertTrue(GitHubIntegration.isTechRequest(try decode(#","templateData":{"kind":"tech","name":"Tech"}"#)))
        XCTAssertFalse(GitHubIntegration.isTechRequest(try decode(#","templateData":{"kind":"standard"}"#)))
        XCTAssertFalse(GitHubIntegration.isTechRequest(try decode("")))
        XCTAssertFalse(GitHubIntegration.isTechRequest(nil))
    }

    func test_models_decodeLeniently() throws {
        let decoder = RequestsAPIClient.makeDecoder()
        let installation = try decoder.decode(GitHubInstallation.self, from: Data(
            #"{"installationId":4242,"accountLogin":"bluefunda","accountType":"User","status":"suspended","createdAt":"2026-11-01T10:20:30.123456789Z"}"#.utf8))
        XCTAssertEqual(installation.installationId, 4242)
        XCTAssertEqual(installation.accountTypeLabel, "User")
        XCTAssertEqual(installation.statusLabel, "Suspended")
        XCTAssertFalse(installation.isActive)
        XCTAssertNotNil(installation.createdAt, "nine fractional digits still parse")

        let linkJSON = #"""
            {"id":"l-1","repoFullName":"acme/api","number":15,
             "url":"https://github.com/acme/api/issues/15","title":"Crash","state":"closed",
             "origin":"linked","linkedBy":"u-1","linkedAt":"2026-11-01T10:20:30Z"}
            """#
        let link = try decoder.decode(GitHubIssueLink.self, from: Data(linkJSON.utf8))
        XCTAssertEqual(link.stateLabel, "Closed")
        XCTAssertEqual(link.originLabel, "Linked")
        XCTAssertFalse(link.isOpen)
        XCTAssertNotNil(link.linkedAt)

        let list = try decoder.decode(GitHubList<GitHubRepo>.self, from: Data(#"{"unexpected":true}"#.utf8))
        XCTAssertTrue(list.items.isEmpty, "a non-array body is an empty list")

        XCTAssertNil(GitHubApp(appSlug: "x", installUrl: "http://github.com/apps/x").installURL)
        XCTAssertNotNil(GitHubApp(appSlug: "x", installUrl: "https://github.com/apps/x/installations/new").installURL)
    }

    func test_issueLinkPayload_omitsEmptyTitleAndBody() throws {
        let create = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(IssueLinkPayload.create(projectRepoId: "pr-1", title: "", body: ""))) as? [String: Any]
        XCTAssertEqual(create?["mode"] as? String, "create")
        XCTAssertEqual(create?["projectRepoId"] as? String, "pr-1")
        XCTAssertNil(create?["title"])
        XCTAssertNil(create?["body"])
        XCTAssertNil(create?["number"])

        let link = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(IssueLinkPayload.link(projectRepoId: "pr-1", number: 15))) as? [String: Any]
        XCTAssertEqual(link?["mode"] as? String, "link")
        XCTAssertEqual(link?["number"] as? Int, 15)
    }
}

// MARK: - API Mapping

@MainActor
final class GitHubServiceTests: XCTestCase {
    private class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        static var requests: [URLRequest] = []
        static var bodies: [Data] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            MockURLProtocol.requests.append(request)
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    guard read > 0 else { break }
                    body.append(buffer, count: read)
                }
            }
            MockURLProtocol.bodies.append(body)
            guard let handler = MockURLProtocol.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeService() -> GitHubService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return GitHubService(client: RequestsAPIClient(
            baseURL: AppConfig.requestsBaseURL, tokenProvider: { "test-token" },
            session: URLSession(configuration: config)))
    }

    private func respond(status: Int, body: String = "") {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
    }

    private func path(_ route: String) -> String {
        (URL(string: AppConfig.requestsBaseURL)?.path ?? "") + route
    }

    private var last: URLRequest { MockURLProtocol.requests.last! }

    private func lastBody() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: MockURLProtocol.bodies.last ?? Data()) as? [String: Any])
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.requests = []
        MockURLProtocol.bodies = []
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func test_app_andInstallations_areTrmBffRoutes() async throws {
        respond(status: 200, body: #"{"appSlug":"bluerequests","installUrl":"https://github.com/apps/bluerequests/installations/new?state=s"}"#)
        let app = try await makeService().app()
        XCTAssertEqual(last.url?.path, path("/github/app"))
        XCTAssertEqual(last.httpMethod, "GET")
        XCTAssertEqual(last.value(forHTTPHeaderField: "Access-Token"), "test-token")
        XCTAssertNotNil(app.installURL)

        respond(status: 200, body: #"[{"installationId":7,"accountLogin":"acme","accountType":"Organization","status":"active","createdAt":"2026-10-01T00:00:00Z"}]"#)
        let installations = try await makeService().installations()
        XCTAssertEqual(last.url?.path, path("/github/installations"))
        XCTAssertEqual(installations.map(\.accountLogin), ["acme"])

        respond(status: 200, body: "null")
        let none = try await makeService().installations()
        XCTAssertTrue(none.isEmpty, "a null body is an empty list")
    }

    func test_installationRepos_andDisconnect() async throws {
        respond(status: 200, body: #"[{"nodeId":"R_1","fullName":"acme/api","defaultBranch":"main","private":true}]"#)
        let repos = try await makeService().installationRepos(installationId: 7)
        XCTAssertEqual(last.url?.path, path("/github/installations/7/repos"))
        XCTAssertEqual(repos.first?.isPrivate, true)
        XCTAssertEqual(repos.first?.defaultBranch, "main")

        respond(status: 204)
        try await makeService().deleteInstallation(id: 7)
        XCTAssertEqual(last.httpMethod, "DELETE")
        XCTAssertEqual(last.url?.path, path("/github/installations/7"))
    }

    func test_projectRepos_listAddRemove() async throws {
        respond(status: 200, body: "")
        let empty = try await makeService().projectRepos(projectId: "28")
        XCTAssertEqual(last.url?.path, path("/projects/28/repos"))
        XCTAssertTrue(empty.isEmpty, "a blank body is an empty list")

        respond(status: 201, body: #"{"id":"pr-9","projectId":28,"installationId":7,"repoNodeId":"R_1","fullName":"acme/api","defaultBranch":"main"}"#)
        let added = try await makeService().addProjectRepo(
            projectId: "28", AddProjectRepoPayload(installationId: 7, repoNodeId: "R_1", fullName: "acme/api"))
        XCTAssertEqual(last.httpMethod, "POST")
        XCTAssertEqual(last.url?.path, path("/projects/28/repos"))
        let body = try lastBody()
        XCTAssertEqual(body["installationId"] as? Int, 7)
        XCTAssertEqual(body["repoNodeId"] as? String, "R_1")
        XCTAssertEqual(body["fullName"] as? String, "acme/api")
        XCTAssertEqual(added?.id, "pr-9")

        respond(status: 201, body: "")
        let unknown = try await makeService().addProjectRepo(
            projectId: "28", AddProjectRepoPayload(installationId: 7, repoNodeId: "R_2", fullName: "acme/web"))
        XCTAssertNil(unknown, "bound, but the answer didn't carry it: reload")

        respond(status: 204)
        try await makeService().deleteProjectRepo(projectId: "28", bindingId: "pr-9")
        XCTAssertEqual(last.httpMethod, "DELETE")
        XCTAssertEqual(last.url?.path, path("/projects/28/repos/pr-9"))
    }

    func test_issues_listCreateLinkUnlink() async throws {
        respond(status: 200, body: #"[{"id":"l-1","repoFullName":"acme/api","number":3,"state":"open","origin":"created"}]"#)
        let links = try await makeService().issues(changeRequestId: "32")
        XCTAssertEqual(last.url?.path, path("/change-requests/32/issues"))
        XCTAssertEqual(links.map(\.number), [3])

        respond(status: 201, body: #"{"id":"l-2","repoFullName":"acme/api","number":4,"state":"open","origin":"created"}"#)
        let created = try await makeService().addIssue(
            changeRequestId: "32", .create(projectRepoId: "pr-1", title: "Crash on save", body: ""))
        XCTAssertEqual(last.httpMethod, "POST")
        XCTAssertEqual(last.url?.path, path("/change-requests/32/issues"))
        var body = try lastBody()
        XCTAssertEqual(body["mode"] as? String, "create")
        XCTAssertEqual(body["title"] as? String, "Crash on save")
        XCTAssertNil(body["body"])
        XCTAssertEqual(created?.number, 4)

        respond(status: 201, body: #"{"id":"l-3","number":15}"#)
        _ = try await makeService().addIssue(changeRequestId: "32", .link(projectRepoId: "pr-1", number: 15))
        body = try lastBody()
        XCTAssertEqual(body["mode"] as? String, "link")
        XCTAssertEqual(body["number"] as? Int, 15)
        XCTAssertEqual(body["projectRepoId"] as? String, "pr-1")

        respond(status: 204)
        try await makeService().unlinkIssue(changeRequestId: "32", linkId: "l-1")
        XCTAssertEqual(last.httpMethod, "DELETE")
        XCTAssertEqual(last.url?.path, path("/change-requests/32/issues/l-1"))
    }

    func test_coded403_keepsItsCode() async {
        respond(status: 403, body: #"{"error":{"code":"not_available_in_public_tenant","message":"organizations only"}}"#)
        do {
            _ = try await makeService().installations()
            XCTFail("Expected a throw")
        } catch {
            XCTAssertEqual(GitHubIntegration.loadFailureKind(error), .publicTenant)
        }

        respond(status: 403, body: #"{"error":"forbidden"}"#)
        do {
            _ = try await makeService().installations()
            XCTFail("Expected a throw")
        } catch RequestsAPIError.requestsUnavailable(let status) {
            XCTAssertEqual(status, 403, "an uncoded 403 is still 'unavailable', never a sign-out")
        } catch {
            XCTFail("Expected requestsUnavailable, got \(error)")
        }
    }

    func test_issueErrors_carryTheirCodes() async {
        respond(status: 504, body: #"{"error":{"code":"github_timeout","message":"timed out"}}"#)
        do {
            _ = try await makeService().addIssue(changeRequestId: "32", .create(projectRepoId: "pr-1"))
            XCTFail("Expected a throw")
        } catch {
            XCTAssertTrue(GitHubIntegration.isTimeout(error))
        }

        respond(status: 422, body: #"{"error":{"code":"not_tech_template","message":"x"}}"#)
        do {
            _ = try await makeService().addIssue(changeRequestId: "32", .link(projectRepoId: "pr-1", number: 2))
            XCTFail("Expected a throw")
        } catch {
            XCTAssertEqual(GitHubIntegration.issueErrorMessage(error, mode: .link),
                           "GitHub issues can only be linked to change requests created from a tech template.")
        }
    }
}

// MARK: - View Models

/// Records calls and answers with whatever each test sets.
final class MockGitHubService: GitHubServicing {
    var appResult: Result<GitHubApp, Error> = .success(GitHubApp(appSlug: "app", installUrl: "https://github.com/apps/app/installations/new"))
    var installationsResult: Result<[GitHubInstallation], Error> = .success([])
    var reposResult: [Int64: Result<[GitHubRepo], Error>] = [:]
    var projectReposResult: Result<[ProjectRepo], Error> = .success([])
    var addProjectRepoResult: Result<ProjectRepo?, Error> = .success(nil)
    var deleteProjectRepoError: Error?
    var deleteInstallationError: Error?
    var issuesResult: Result<[GitHubIssueLink], Error> = .success([])
    var addIssueResult: Result<GitHubIssueLink?, Error> = .success(nil)
    var addIssueDelay: TimeInterval = 0
    var unlinkError: Error?

    private(set) var appCalls = 0
    private(set) var issuesCalls = 0
    private(set) var addedIssues: [(changeRequestId: String, payload: IssueLinkPayload)] = []
    private(set) var addedRepos: [AddProjectRepoPayload] = []

    func app() async throws -> GitHubApp { appCalls += 1; return try appResult.get() }
    func installations() async throws -> [GitHubInstallation] { try installationsResult.get() }
    func deleteInstallation(id: Int64) async throws { if let deleteInstallationError { throw deleteInstallationError } }
    func installationRepos(installationId: Int64) async throws -> [GitHubRepo] {
        try (reposResult[installationId] ?? .success([])).get()
    }
    func projectRepos(projectId: String) async throws -> [ProjectRepo] { try projectReposResult.get() }
    func addProjectRepo(projectId: String, _ payload: AddProjectRepoPayload) async throws -> ProjectRepo? {
        addedRepos.append(payload)
        return try addProjectRepoResult.get()
    }
    func deleteProjectRepo(projectId: String, bindingId: String) async throws {
        if let deleteProjectRepoError { throw deleteProjectRepoError }
    }
    func issues(changeRequestId: String) async throws -> [GitHubIssueLink] { issuesCalls += 1; return try issuesResult.get() }
    func addIssue(changeRequestId: String, _ payload: IssueLinkPayload) async throws -> GitHubIssueLink? {
        addedIssues.append((changeRequestId, payload))
        if addIssueDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(addIssueDelay * 1_000_000_000)) }
        return try addIssueResult.get()
    }
    func unlinkIssue(changeRequestId: String, linkId: String) async throws { if let unlinkError { throw unlinkError } }
}

@MainActor
final class GitHubViewModelTests: XCTestCase {
    private let acme = GitHubInstallation(installationId: 1, accountLogin: "acme")
    private let suspended = GitHubInstallation(installationId: 2, accountLogin: "old", status: "suspended")
    private let repoA = GitHubRepo(nodeId: "R_A", fullName: "acme/api")
    private let repoB = GitHubRepo(nodeId: "R_B", fullName: "acme/web")

    // MARK: Git destination

    func test_integration_adminLoadsAppAndInstallations() async {
        let service = MockGitHubService()
        service.installationsResult = .success([acme])
        let model = GitHubIntegrationViewModel(service: service, roles: ["admin"])
        await model.load()
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.installations, [acme])
        XCTAssertEqual(service.appCalls, 1)
        XCTAssertNil(model.appError)
    }

    func test_integration_nonAdminSkipsTheApp() async {
        let service = MockGitHubService()
        let model = GitHubIntegrationViewModel(service: service, roles: ["release-manager"])
        await model.load()
        XCTAssertFalse(model.canManage)
        XCTAssertEqual(service.appCalls, 0)
        XCTAssertEqual(model.state, .ready)
    }

    func test_integration_appFailureDisablesConnectOnly() async {
        let service = MockGitHubService()
        service.appResult = .failure(RequestsAPIError.serverError(500, "HTTP 500"))
        service.installationsResult = .success([acme])
        let model = GitHubIntegrationViewModel(service: service, roles: ["admin"])
        await model.load()
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.appError, "Connecting a GitHub account is not available right now.")
    }

    func test_integration_loadFailures() async {
        let service = MockGitHubService()
        let publicTenant = RequestsAPIError.rejected(status: 403, code: "not_available_in_public_tenant", message: "x")
        service.appResult = .failure(publicTenant)
        service.installationsResult = .failure(RequestsAPIError.serverError(500, "HTTP 500"))
        let model = GitHubIntegrationViewModel(service: service, roles: ["admin"])
        await model.load()
        XCTAssertEqual(model.state, .failed(.publicTenant), "the App's public-tenant answer explains the list failing")

        service.appResult = .success(GitHubApp(appSlug: nil, installUrl: nil))
        service.installationsResult = .failure(RequestsAPIError.serverError(503, "HTTP 503"))
        await model.load()
        XCTAssertEqual(model.state, .failed(.unavailable))

        service.installationsResult = .failure(RequestsAPIError.serverError(500, "HTTP 500"))
        await model.load()
        XCTAssertEqual(model.state, .failed(.error))
    }

    func test_integration_connectReturnsInstallURLThenRefreshClearsTheNote() async {
        let service = MockGitHubService()
        let model = GitHubIntegrationViewModel(service: service, roles: ["super-admin"])
        await model.load()
        let url = await model.connect()
        XCTAssertEqual(url?.host, "github.com")
        XCTAssertTrue(model.awaitingInstall)
        await model.refresh()
        XCTAssertFalse(model.awaitingInstall)

        service.appResult = .success(GitHubApp(appSlug: "x", installUrl: "javascript:alert(1)"))
        let none = await model.connect()
        XCTAssertNil(none)
        XCTAssertEqual(model.error, "Could not start the GitHub install. Please try again.")
        XCTAssertFalse(model.awaitingInstall)
    }

    func test_integration_disconnectAndRepos() async {
        let service = MockGitHubService()
        service.installationsResult = .success([acme, suspended])
        service.reposResult = [1: .success([repoA]), 2: .failure(RequestsAPIError.serverError(500, "HTTP 500"))]
        let model = GitHubIntegrationViewModel(service: service, roles: ["admin"])
        await model.load()
        await model.loadRepos(for: 1)
        await model.loadRepos(for: 2)
        XCTAssertEqual(model.repos[1], .loaded([repoA]))
        XCTAssertEqual(model.repos[2], .failed("Could not load the repositories."))

        await model.disconnect(acme)
        XCTAssertEqual(model.installations, [suspended])
        XCTAssertNil(model.repos[1])

        service.deleteInstallationError = RequestsAPIError.requestsUnavailable(statusCode: 403)
        await model.disconnect(suspended)
        XCTAssertEqual(model.installations, [suspended])
        XCTAssertEqual(model.error, "You do not have permission to do this.")
    }

    // MARK: Project repositories

    func test_projectRepos_hiddenWhileTheAPIIsMissing() async {
        let service = MockGitHubService()
        service.projectReposResult = .failure(RequestsAPIError.serverError(404, "HTTP 404"))
        let model = ProjectReposViewModel(projectId: "28", service: service, roles: ["admin"])
        XCTAssertEqual(model.state, .loading)
        await model.load()
        XCTAssertTrue(model.isHidden)
    }

    func test_projectRepos_rolesDecideChanges() {
        let service = MockGitHubService()
        XCTAssertTrue(ProjectReposViewModel(projectId: "1", service: service, roles: ["release-manager"]).canBind)
        XCTAssertFalse(ProjectReposViewModel(projectId: "1", service: service, roles: []).canBind)
    }

    func test_projectRepos_addPicksTheOnlyActiveAccountAndHidesBoundRepos() async {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", repoNodeId: "R_A", fullName: "acme/api")])
        service.installationsResult = .success([acme, suspended])
        service.reposResult = [1: .success([repoA, repoB])]
        let model = ProjectReposViewModel(projectId: "28", service: service, roles: ["admin"])
        await model.load()

        await model.prepareAdd()
        XCTAssertEqual(model.addInstallations, [acme], "suspended accounts aren't offered")
        XCTAssertEqual(model.selectedInstallationId, 1, "a single active account is picked")
        XCTAssertEqual(model.repoOptions, [repoB], "already bound repos are left out")
        XCTAssertEqual(model.repoOptions(matching: "API"), [])
        XCTAssertEqual(model.repoOptions(matching: "WEB"), [repoB])

        service.addProjectRepoResult = .success(ProjectRepo(id: "pr-2", repoNodeId: "R_B", fullName: "acme/web"))
        let added = await model.add(repoB)
        XCTAssertTrue(added)
        XCTAssertEqual(service.addedRepos, [AddProjectRepoPayload(installationId: 1, repoNodeId: "R_B", fullName: "acme/web")])
        XCTAssertEqual(model.bindings.map(\.id), ["pr-1", "pr-2"])
    }

    func test_projectRepos_addAndRemoveErrors() async {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", repoNodeId: "R_A", fullName: "acme/api")])
        service.installationsResult = .success([acme])
        service.reposResult = [1: .success([repoB])]
        let model = ProjectReposViewModel(projectId: "28", service: service, roles: ["admin"])
        await model.load()
        await model.prepareAdd()

        service.addProjectRepoResult = .failure(RequestsAPIError.rejected(status: 409, code: "already_bound", message: "x"))
        let added = await model.add(repoB)
        XCTAssertFalse(added)
        XCTAssertEqual(model.addError, "This repository is already bound to this project.")

        service.deleteProjectRepoError = RequestsAPIError.rejected(status: 409, code: "binding_in_use", message: "x")
        await model.remove(model.bindings[0])
        XCTAssertEqual(model.bindings.count, 1)
        XCTAssertEqual(model.error, "This repository is linked to change requests and cannot be removed yet.")
    }

    func test_projectRepos_noAccounts() async {
        let service = MockGitHubService()
        let model = ProjectReposViewModel(projectId: "28", service: service, roles: ["admin"])
        await model.prepareAdd()
        XCTAssertEqual(model.addInstallations, [])
        XCTAssertNil(model.selectedInstallationId)
        XCTAssertFalse(model.isAddLoading)
    }

    // MARK: Change request GitHub tab

    private func makeIssues(_ service: MockGitHubService, slowDelay: TimeInterval = 4) -> GitHubIssuesViewModel {
        GitHubIssuesViewModel(changeRequestId: "32", projectId: "28", defaultTitle: "Nightly report times out",
                              service: service, users: { [UserOption(id: "u-1", name: "Priya Shah")] },
                              slowDelay: slowDelay)
    }

    func test_issues_loadAndDialogDefaults() async {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", fullName: "acme/api")])
        service.issuesResult = .success([GitHubIssueLink(id: "l-1", repoFullName: "acme/api", number: 3, linkedBy: "u-1")])
        let model = makeIssues(service)
        await model.load()
        XCTAssertEqual(model.state, .ready)
        XCTAssertTrue(model.hasRepos)
        XCTAssertEqual(model.userName("u-1"), "Priya Shah")

        model.openDialog(.create)
        XCTAssertEqual(model.draftRepoId, "pr-1", "the only repo is preselected")
        XCTAssertEqual(model.draftTitle, "Nightly report times out")
        XCTAssertTrue(model.canSubmit)

        model.openDialog(.link)
        XCTAssertFalse(model.canSubmit, "link needs an issue number")
        model.draftNumber = "#15"
        XCTAssertTrue(model.canSubmit)
        model.draftNumber = "abc"
        XCTAssertTrue(model.isDraftNumberInvalid)
        XCTAssertFalse(model.canSubmit)
    }

    func test_issues_severalReposAreNotPreselected_andNoReposShowsHint() async {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", fullName: "a/a"), ProjectRepo(id: "pr-2", fullName: "a/b")])
        let model = makeIssues(service)
        await model.load()
        model.openDialog(.create)
        XCTAssertEqual(model.draftRepoId, "")
        XCTAssertFalse(model.canSubmit)

        service.projectReposResult = .failure(RequestsAPIError.serverError(500, "HTTP 500"))
        await model.load()
        XCTAssertEqual(model.repos, [])
        XCTAssertFalse(model.hasRepos)
        XCTAssertEqual(model.reposError, "Could not load the project's repositories.")
    }

    func test_issues_createAddsTheLinkAndClosesTheDialog() async {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", fullName: "acme/api")])
        let model = makeIssues(service)
        await model.load()
        model.openDialog(.create)
        model.draftTitle = "  Crash on save "
        service.addIssueResult = .success(GitHubIssueLink(id: "l-9", repoFullName: "acme/api", number: 9))
        await model.submit()
        XCTAssertNil(model.dialogMode)
        XCTAssertEqual(model.links.map(\.id), ["l-9"])
        XCTAssertEqual(service.addedIssues.first?.payload, .create(projectRepoId: "pr-1", title: "Crash on save", body: ""))
    }

    func test_issues_timeoutWarnsAndReloadsTheList() async {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", fullName: "acme/api")])
        let model = makeIssues(service)
        await model.load()
        let loadsBefore = service.issuesCalls
        model.openDialog(.link)
        model.draftNumber = "15"
        service.addIssueResult = .failure(RequestsAPIError.serverError(504, "HTTP 504"))
        await model.submit()
        XCTAssertEqual(model.dialogMode, .link, "the dialog stays open with the warning")
        XCTAssertEqual(model.dialogError, GitHubIntegration.issueTimeoutMessages[.link])
        XCTAssertEqual(service.issuesCalls, loadsBefore + 1, "the list is reloaded")
        XCTAssertFalse(model.isSaving)
    }

    func test_issues_slowRequestSaysSo() async {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", fullName: "acme/api")])
        service.addIssueDelay = 0.4
        let model = makeIssues(service, slowDelay: 0.05)
        await model.load()
        model.openDialog(.create)
        let submit = Task { await model.submit() }
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(model.isSaving)
        XCTAssertTrue(model.isSlow)
        await submit.value
        XCTAssertFalse(model.isSlow)
    }

    func test_issues_unlinkAndItsError() async {
        let service = MockGitHubService()
        let link = GitHubIssueLink(id: "l-1", repoFullName: "acme/api", number: 3)
        service.issuesResult = .success([link, GitHubIssueLink(id: "l-2", repoFullName: "acme/api", number: 4)])
        let model = makeIssues(service)
        await model.load()
        await model.unlink(link)
        XCTAssertEqual(model.links.map(\.id), ["l-2"])

        service.unlinkError = RequestsAPIError.serverError(500, "HTTP 500")
        await model.unlink(model.links[0])
        XCTAssertEqual(model.links.count, 1)
        XCTAssertEqual(model.error, "Could not unlink the issue. Please try again.")
    }

    func test_issues_loadFailureKinds() async {
        let service = MockGitHubService()
        service.issuesResult = .failure(RequestsAPIError.rejected(status: 403, code: "not_available_in_public_tenant", message: "x"))
        let model = makeIssues(service)
        await model.load()
        XCTAssertEqual(model.state, .failed(.publicTenant))
        service.issuesResult = .success([])
        await model.retry()
        XCTAssertEqual(model.state, .ready)
    }

    // MARK: New request: Create GitHub issue

    private func techTemplate() -> RQRequestTemplate {
        let json = #"{"id":"t-tech","name":"Tech","status":true,"kind":"tech","workflow":[{"order":1,"description":"Development","statusCode":"DEV"}]}"#
        return try! JSONDecoder().decode(RQRequestTemplate.self, from: Data(json.utf8))
    }

    private func standardTemplate() -> RQRequestTemplate {
        let json = #"{"id":"t-std","name":"Standard","status":true,"workflow":[]}"#
        return try! JSONDecoder().decode(RQRequestTemplate.self, from: Data(json.utf8))
    }

    private func makeNewRequest(_ service: MockGitHubService,
                                notice: @escaping (String, String) -> Void = { _, _ in }) -> NewChangeRequestViewModel {
        let templates = [techTemplate(), standardTemplate()]
        return NewChangeRequestViewModel(
            changeRequestService: FixtureChangeRequestService(),
            projectService: FixtureProjectService(),
            referenceDataService: FixtureReferenceDataService(),
            sources: NewRequestFormSources(templates: { templates }),
            currentUserId: "u-1",
            githubService: service,
            onGitHubIssueNotice: notice
        )
    }

    private func fillRequired(_ model: NewChangeRequestViewModel) {
        model.requestName = "Add index"
        model.description = "Nightly report times out."
        model.selectedProjectId = "28"
        model.selectedRequestTypeId = "1"
        model.selectedSeverityId = "3"
    }

    private func waitForRepos(_ model: NewChangeRequestViewModel) async {
        for _ in 0..<100 where model.isLoadingGitHubRepos {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func test_newRequest_optionOnlyForTechTemplateWithBoundRepos() async {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", fullName: "a/a"), ProjectRepo(id: "pr-2", fullName: "a/b")])
        let model = makeNewRequest(service)
        await model.loadOptions()
        fillRequired(model)

        model.selectedTemplateId = "t-std"
        XCTAssertFalse(model.isLoadingGitHubRepos)
        XCTAssertFalse(model.showsGitHubIssueOption)

        model.selectedTemplateId = "t-tech"
        XCTAssertTrue(model.isLoadingGitHubRepos, "a loader while the repos are checked")
        await waitForRepos(model)
        XCTAssertTrue(model.showsGitHubIssueOption)
        model.createGitHubIssue = true
        XCTAssertEqual(model.githubIssueRepoId, "pr-1", "the first repo until another is picked")

        model.selectedTemplateId = "t-std"
        XCTAssertFalse(model.showsGitHubIssueOption)
        XCTAssertFalse(model.createGitHubIssue, "hiding the option turns it off")

        service.projectReposResult = .success([])
        model.selectedTemplateId = "t-tech"
        await waitForRepos(model)
        XCTAssertFalse(model.showsGitHubIssueOption, "no bound repos, no option")
    }

    func test_newRequest_createsTheIssueAfterTheRequest() async {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", fullName: "a/a"), ProjectRepo(id: "pr-2", fullName: "a/b")])
        var notices: [String: String] = [:]
        let model = makeNewRequest(service) { notices[$0] = $1 }
        await model.loadOptions()
        fillRequired(model)
        model.selectedTemplateId = "t-tech"
        await waitForRepos(model)
        model.createGitHubIssue = true
        model.githubIssueRepoId = "pr-2"

        let created = await model.submit()
        XCTAssertNotNil(created)
        XCTAssertEqual(service.addedIssues.count, 1)
        XCTAssertEqual(service.addedIssues.first?.changeRequestId, created?.id)
        XCTAssertEqual(service.addedIssues.first?.payload, .create(projectRepoId: "pr-2"))
        XCTAssertNil(model.githubIssueNotice)
        XCTAssertTrue(notices.isEmpty)
    }

    func test_newRequest_issueFailureNeverBlocksTheSave() async throws {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", fullName: "a/a")])
        service.addIssueResult = .failure(RequestsAPIError.serverError(504, "HTTP 504"))
        var notices: [String: String] = [:]
        let model = makeNewRequest(service) { notices[$0] = $1 }
        await model.loadOptions()
        fillRequired(model)
        model.selectedTemplateId = "t-tech"
        await waitForRepos(model)
        model.createGitHubIssue = true

        let result = await model.submit()
        let created = try XCTUnwrap(result, "the request is saved")
        XCTAssertNil(model.error)
        let expected = GitHubIntegration.issueFailureNotice(GitHubIntegration.issueTimeoutMessages[.create]!)
        XCTAssertEqual(model.githubIssueNotice, expected)
        XCTAssertEqual(notices[created.id], expected, "handed to the new request's detail")
        XCTAssertTrue(expected.hasPrefix("The change request was created, but the GitHub issue was not: "))
    }

    func test_newRequest_noIssueWhenTheOptionIsOff() async {
        let service = MockGitHubService()
        service.projectReposResult = .success([ProjectRepo(id: "pr-1", fullName: "a/a")])
        let model = makeNewRequest(service)
        await model.loadOptions()
        fillRequired(model)
        model.selectedTemplateId = "t-tech"
        await waitForRepos(model)
        _ = await model.submit()
        XCTAssertTrue(service.addedIssues.isEmpty)
    }
}
