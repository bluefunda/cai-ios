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
