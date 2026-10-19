import XCTest
@testable import CAI

// MARK: - Sidebar Layout Tests
// Snapshot-style checks of what the sidebar renders (SidebarView draws straight from
// SidebarLayout). The key promise: a personal-only user — no `trm` org, or the
// feature flag off — sees no space switcher and no Requests UI at all
// (docs/BLUEREQUESTS_INTEGRATION.md P2, P11).

@MainActor
final class SidebarLayoutTests: XCTestCase {
    private nonisolated static let suiteName = "SidebarLayoutTests"
    private var defaults: UserDefaults { UserDefaults(suiteName: Self.suiteName)! }

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    private func makeStore(flag: Bool, organizations: [String]) -> WorkspaceStore {
        let store = WorkspaceStore(defaults: defaults, isRequestsFeatureEnabled: { flag })
        store.update(organizations: organizations)
        return store
    }

    private let assistantRows: [SidebarDestination] = [
        .assistant(.chats), .assistant(.code), .assistant(.files), .assistant(.agents)
    ]

    func test_personalOnlyUser_noSwitcherNoRequests() {
        for (flag, orgs) in [(false, [String]()), (true, []), (true, ["acme"]), (false, ["trm"])] {
            let store = makeStore(flag: flag, organizations: orgs)
            // Even a persisted Requests choice must not leak through.
            store.activeSpace = .requests
            let layout = SidebarLayout(workspace: store)

            XCTAssertFalse(layout.showsSpaceSwitcher, "flag=\(flag) orgs=\(orgs)")
            XCTAssertEqual(layout.spaces, [.assistant])
            XCTAssertEqual(layout.activeSpace, .assistant)
            XCTAssertEqual(layout.destinations, assistantRows)
            XCTAssertFalse(layout.destinations.contains { if case .requests = $0 { return true }; return false })
        }
    }

    func test_personalOnlyUser_cannotNavigateIntoRequests() {
        let store = makeStore(flag: false, organizations: ["trm"])
        store.navigate(to: .requests(.releases))
        XCTAssertEqual(store.currentDestination, .assistant(.chats))
    }

    func test_entitledUser_seesSwitcherAndRequestsDestinations() {
        let store = makeStore(flag: true, organizations: ["trm"])
        XCTAssertTrue(SidebarLayout(workspace: store).showsSpaceSwitcher)
        XCTAssertEqual(SidebarLayout(workspace: store).destinations, assistantRows)

        store.navigate(to: .requests(.projects))
        let layout = SidebarLayout(workspace: store)
        XCTAssertEqual(layout.activeSpace, .requests)
        XCTAssertEqual(layout.destinations, RequestsDestination.allCases.map { .requests($0) })
        XCTAssertEqual(store.currentDestination, .requests(.projects))
    }

    func test_eachSpaceRemembersItsLastDestination() {
        let store = makeStore(flag: true, organizations: ["trm"])
        store.navigate(to: .assistant(.files))
        store.navigate(to: .requests(.teams))

        store.activeSpace = .assistant
        XCTAssertEqual(store.currentDestination, .assistant(.files))
        store.activeSpace = .requests
        XCTAssertEqual(store.currentDestination, .requests(.teams))
    }

    func test_defaultDestinations() {
        let store = makeStore(flag: true, organizations: ["trm"])
        XCTAssertEqual(store.assistantDestination, .chats)
        XCTAssertEqual(store.requestsDestination, .requests)
    }

    // MARK: - app_mode migration

    func test_legacyCodeMode_migratesToCodeDestination() {
        defaults.set("code", forKey: AssistantDestination.legacyAppModeKey)
        let store = WorkspaceStore(defaults: defaults, isRequestsFeatureEnabled: { false })
        XCTAssertEqual(store.assistantDestination, .code)
        XCTAssertNil(defaults.string(forKey: AssistantDestination.legacyAppModeKey))
    }

    func test_legacyChatMode_migratesToChats() {
        defaults.set("chat", forKey: AssistantDestination.legacyAppModeKey)
        let store = WorkspaceStore(defaults: defaults, isRequestsFeatureEnabled: { false })
        XCTAssertEqual(store.assistantDestination, .chats)
        XCTAssertNil(defaults.string(forKey: AssistantDestination.legacyAppModeKey))
    }

    func test_storedDestination_winsOverLegacyMode() {
        defaults.set("agents", forKey: WorkspaceStore.lastDestinationKey(for: .assistant))
        defaults.set("code", forKey: AssistantDestination.legacyAppModeKey)
        let store = WorkspaceStore(defaults: defaults, isRequestsFeatureEnabled: { false })
        XCTAssertEqual(store.assistantDestination, .agents)
    }

    // MARK: - Shortcuts

    func test_commandDigitShortcuts_followDestinationOrder() {
        XCTAssertEqual(AssistantDestination.allCases, [.chats, .code, .files, .agents])
        XCTAssertEqual(ShellKeyboardShortcuts.key(forIndex: 0), "1")
        XCTAssertEqual(ShellKeyboardShortcuts.key(forIndex: 3), "4")
    }
}
