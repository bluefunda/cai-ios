import XCTest
@testable import CAI

// MARK: - Requests State Tests
// No services (no entitlement) → no view models, so nothing can call trm-gw; a
// different user drops the previous user's recently viewed requests.

@MainActor
final class RequestsStateTests: XCTestCase {
    private nonisolated static let suiteName = "RequestsStateTests"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    private func makeState() -> RequestsState {
        RequestsState(recents: RecentRequestsStore(defaults: UserDefaults(suiteName: Self.suiteName)!))
    }

    private var fixtureServices: RequestsServices {
        RequestsServices(authManager: AuthManager(), useFixtures: true)
    }

    func test_withoutServices_noViewModels() {
        let state = makeState()
        state.configure(services: nil, currentUserId: "u-1")

        XCTAssertNil(state.changeRequests)
        XCTAssertNil(state.projects)
        XCTAssertNil(state.makeNewRequestModel())
    }

    func test_withServices_buildsViewModels_andKeepsThemForSameUser() {
        let state = makeState()
        state.configure(services: fixtureServices, currentUserId: "u-1")
        let first = state.changeRequests
        XCTAssertNotNil(first)
        XCTAssertNotNil(state.teams)

        state.configure(services: fixtureServices, currentUserId: "u-1")
        XCTAssertTrue(state.changeRequests === first, "Same user: loaded data survives")
    }

    func test_userChange_clearsRecentsAndPath() {
        let state = makeState()
        state.configure(services: fixtureServices, currentUserId: "u-1")
        state.recents.record(RecentRequest(id: "32", number: "CR-1042", title: "Index"))
        state.openRequest(id: "32")
        XCTAssertEqual(state.requestsPath, ["32"])

        state.configure(services: fixtureServices, currentUserId: "u-2")
        XCTAssertTrue(state.recents.items.isEmpty)
        XCTAssertTrue(state.requestsPath.isEmpty)
    }

    func test_userChange_clearsTheProjectsPath() {
        let state = makeState()
        state.configure(services: fixtureServices, currentUserId: "u-1")
        state.projectsPath.append("32")
        state.configure(services: fixtureServices, currentUserId: "u-2")
        XCTAssertTrue(state.projectsPath.isEmpty)
    }

    // MARK: After a delete (web #320, #322)

    func test_deletingAnArchivedRequest_opensTheListOnArchive() async throws {
        let state = makeState()
        state.configure(services: fixtureServices, currentUserId: "u-1")
        let list = try XCTUnwrap(state.changeRequests)
        state.recents.record(RecentRequest(id: "32", number: "CR-1042", title: "Index"))

        await state.didDeleteRequest(id: "32", wasArchived: true, origin: .requests)

        XCTAssertEqual(list.archiveTab, .archived)
        XCTAssertTrue(state.recents.items.isEmpty)
        XCTAssertEqual(state.requestsChanged, 1, "a project's list reloads too")
    }

    func test_deletingAnActiveRequest_staysOnActive() async throws {
        let state = makeState()
        state.configure(services: fixtureServices, currentUserId: "u-1")
        let list = try XCTUnwrap(state.changeRequests)

        await state.didDeleteRequest(id: "32", wasArchived: false, origin: .requests)

        XCTAssertEqual(list.archiveTab, .active)
    }

    func test_deletingFromAProject_returnsToTheProjectNotTheArchive() async throws {
        let state = makeState()
        state.configure(services: fixtureServices, currentUserId: "u-1")
        let list = try XCTUnwrap(state.changeRequests)

        await state.didDeleteRequest(id: "32", wasArchived: true, origin: .project)

        XCTAssertEqual(list.archiveTab, .active, "the Requests list isn't where it returns")
        XCTAssertEqual(state.requestsChanged, 1, "the project's list reloads")
    }

    func test_newRequestModel_keepsADraftPerUserAndProject() {
        let state = makeState()
        state.draftDefaults = UserDefaults(suiteName: Self.suiteName)!
        state.configure(services: fixtureServices, currentUserId: "u-1")

        XCTAssertEqual(state.draftStore(projectId: nil)?.key, "requests.newRequestDraft.u-1.any")
        XCTAssertEqual(state.draftStore(projectId: "28")?.key, "requests.newRequestDraft.u-1.28")
        state.configure(services: nil, currentUserId: nil)
        XCTAssertNil(state.draftStore(projectId: nil), "no draft without a user")
    }

    func test_losingEntitlement_dropsViewModels() {
        let state = makeState()
        state.configure(services: fixtureServices, currentUserId: "u-1")
        state.configure(services: nil, currentUserId: "u-1")
        XCTAssertNil(state.changeRequests)
    }

    func test_stageRailSegments_clampAndHideWithoutData() {
        XCTAssertNil(StageRail.segments(stage: nil, totalStages: 3))
        XCTAssertNil(StageRail.segments(stage: 2, totalStages: nil))
        XCTAssertNil(StageRail.segments(stage: 1, totalStages: 0))
        XCTAssertEqual(StageRail.segments(stage: 2, totalStages: 3)?.current, 2)
        XCTAssertEqual(StageRail.segments(stage: 0, totalStages: 3)?.current, 1)
        XCTAssertEqual(StageRail.segments(stage: 9, totalStages: 3)?.current, 3)
    }
}
