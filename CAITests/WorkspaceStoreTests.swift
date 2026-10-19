import XCTest
@testable import CAI

// MARK: - Workspace Store Tests
// The Requests space exists only with the feature flag on AND `trm` org
// membership; everyone else sees exactly one space (no switcher, no Requests UI).

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private nonisolated static let suiteName = "WorkspaceStoreTests"
    private var defaults: UserDefaults { UserDefaults(suiteName: Self.suiteName)! }

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    private func makeStore(flag: Bool) -> WorkspaceStore {
        WorkspaceStore(defaults: defaults, isRequestsFeatureEnabled: { flag }, isRequestsFixturesEnabled: { false })
    }

    func test_availableSpaces_matrix() {
        XCTAssertEqual(WorkspaceStore.availableSpaces(organizations: [], requestsFeatureEnabled: false), [.assistant])
        XCTAssertEqual(WorkspaceStore.availableSpaces(organizations: [], requestsFeatureEnabled: true), [.assistant])
        XCTAssertEqual(
            WorkspaceStore.availableSpaces(organizations: ["trm"], requestsFeatureEnabled: false),
            [.assistant]
        )
        XCTAssertEqual(
            WorkspaceStore.availableSpaces(organizations: ["trm"], requestsFeatureEnabled: true),
            [.assistant, .requests]
        )
        // Membership anywhere in the claim counts, not just the effective (first) org.
        XCTAssertEqual(
            WorkspaceStore.availableSpaces(organizations: ["acme", "trm"], requestsFeatureEnabled: true),
            [.assistant, .requests]
        )
        XCTAssertEqual(
            WorkspaceStore.availableSpaces(organizations: ["acme"], requestsFeatureEnabled: true),
            [.assistant]
        )
    }

    func test_fixtures_unlockRequestsWithoutMembership_onlyWithFlag() {
        XCTAssertEqual(
            WorkspaceStore.availableSpaces(organizations: [], requestsFeatureEnabled: true, requestsFixturesEnabled: true),
            [.assistant, .requests]
        )
        XCTAssertEqual(
            WorkspaceStore.availableSpaces(organizations: [], requestsFeatureEnabled: false, requestsFixturesEnabled: true),
            [.assistant]
        )
    }

    func test_personalOnlyUser_seesOnlyAssistant() {
        let store = makeStore(flag: true)
        store.update(organizations: ["acme"])
        XCTAssertEqual(store.availableSpaces, [.assistant])
        XCTAssertFalse(store.isRequestsAvailable)
        XCTAssertEqual(store.activeSpace, .assistant)
    }

    func test_activeSpace_cannotBeSetToUnavailableSpace() {
        let store = makeStore(flag: false)
        store.update(organizations: ["trm"])
        store.activeSpace = .requests
        XCTAssertEqual(store.activeSpace, .assistant)
        XCTAssertNil(defaults.string(forKey: WorkspaceStore.activeSpaceKey))
    }

    func test_activeSpace_persistsAndSurvivesTransientLossOfEntitlement() {
        let store = makeStore(flag: true)
        store.update(organizations: ["trm"])
        store.activeSpace = .requests
        XCTAssertEqual(store.activeSpace, .requests)

        // e.g. signed out: falls back to Assistant without forgetting the choice.
        store.update(organizations: [])
        XCTAssertEqual(store.activeSpace, .assistant)
        store.update(organizations: ["trm"])
        XCTAssertEqual(store.activeSpace, .requests)

        let relaunched = makeStore(flag: true)
        relaunched.update(organizations: ["trm"])
        XCTAssertEqual(relaunched.activeSpace, .requests)
    }

    func test_lastDestination_isPerSpaceAndPersisted() {
        let store = makeStore(flag: true)
        XCTAssertNil(store.lastDestination(for: .assistant))
        store.setLastDestination("code", for: .assistant)
        store.setLastDestination("releases", for: .requests)

        let relaunched = makeStore(flag: true)
        XCTAssertEqual(relaunched.lastDestination(for: .assistant), "code")
        XCTAssertEqual(relaunched.lastDestination(for: .requests), "releases")
    }
}
