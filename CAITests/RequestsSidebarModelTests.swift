import XCTest
@testable import CAI

// MARK: - Requests Sidebar Model Tests
// Recently viewed (capped, de-duplicated, persisted, cleared per user) and the quick
// filter presets the Requests sidebar applies to the list.

@MainActor
final class RequestsSidebarModelTests: XCTestCase {
    private nonisolated static let suiteName = "RequestsSidebarModelTests"
    private var defaults: UserDefaults { UserDefaults(suiteName: Self.suiteName)! }

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    private func recent(_ id: Int) -> RecentRequest {
        RecentRequest(id: "\(id)", number: "CR-\(id)", title: "Request \(id)")
    }

    // MARK: Recently viewed

    func test_recents_newestFirst_deduplicated_capped() {
        let store = RecentRequestsStore(defaults: defaults)
        for id in 1...10 { store.record(recent(id)) }
        store.record(recent(5))

        XCTAssertEqual(store.items.count, RecentRequestsStore.limit)
        XCTAssertEqual(store.items.first?.id, "5")
        XCTAssertEqual(store.items.filter { $0.id == "5" }.count, 1)
        XCTAssertFalse(store.items.contains { $0.id == "1" }, "Oldest entries fall off")
    }

    func test_recents_persistAndClear() {
        let store = RecentRequestsStore(defaults: defaults)
        store.record(recent(1))
        store.record(recent(2))

        XCTAssertEqual(RecentRequestsStore(defaults: defaults).items.map(\.id), ["2", "1"])

        store.removeAll()
        XCTAssertTrue(RecentRequestsStore(defaults: defaults).items.isEmpty)
    }

    // MARK: Quick filters

    func test_quickFilters_presets() {
        XCTAssertEqual(RequestsQuickFilter.allCases.first, .all)
        XCTAssertEqual(RequestsQuickFilter.allCases.count, 2 + ChangeRequestStatus.allCases.count)

        XCTAssertTrue(RequestsQuickFilter.mine.advancedFilters.ownerIsMe)
        XCTAssertTrue(RequestsQuickFilter.mine.advancedFilters.assigneeIsMe)
        XCTAssertFalse(RequestsQuickFilter.all.advancedFilters.ownerIsMe)
        XCTAssertEqual(RequestsQuickFilter.status(.blocked).statusFilter, .blocked)
        XCTAssertNil(RequestsQuickFilter.mine.statusFilter)
    }

    func test_quickFilters_roundTripThroughListModel() {
        let model = ChangeRequestListViewModel(service: FixtureChangeRequestService(), currentUserId: "u-1")
        XCTAssertEqual(model.activeQuickFilter, .mine, "The list's default is Mine, as in trm-ios")

        for filter in RequestsQuickFilter.allCases {
            model.apply(filter)
            XCTAssertEqual(model.activeQuickFilter, filter)
        }
    }

    func test_quickFilters_noPresetForCustomFilters() {
        var custom = ChangeRequestAdvancedFilters()
        custom.severity = "High"
        XCTAssertNil(RequestsQuickFilter.matching(advanced: custom, status: nil))

        var ownerOnly = ChangeRequestAdvancedFilters()
        ownerOnly.assigneeIsMe = false
        XCTAssertNil(RequestsQuickFilter.matching(advanced: ownerOnly, status: nil))
    }
}
