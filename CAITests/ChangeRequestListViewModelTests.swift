import XCTest
@testable import CAI

@MainActor
final class ChangeRequestListViewModelTests: XCTestCase {
    private func makeChangeRequest(
        id: String, status: ChangeRequestStatus, requestedByUserId: String? = nil
    ) -> ChangeRequest {
        ChangeRequest(
            id: id, requestNumber: "CR-\(id)", title: "Test", description: nil,
            status: status, severity: nil, requestTypeLabel: nil,
            requestedByUserId: requestedByUserId, createdByName: nil,
            projectId: nil, projectName: nil, platforms: [], timeline: [], createdAt: nil,
            stage: nil, totalStages: nil, stageStatus: nil
        )
    }

    func testLoadPopulatesChangeRequests() async {
        let cr = makeChangeRequest(id: "1", status: .planned)
        let service = MockChangeRequestService(listResult: .success([cr]))
        let model = ChangeRequestListViewModel(service: service, currentUserId: nil)

        await model.load()

        XCTAssertEqual(model.changeRequests.count, 1)
        XCTAssertNil(model.error)
    }

    func testLoadSurfacesError() async {
        let service = MockChangeRequestService(
            listResult: .failure(RequestsAPIError.requestsUnavailable(statusCode: 401))
        )
        let model = ChangeRequestListViewModel(service: service, currentUserId: nil)

        await model.load()

        XCTAssertTrue(model.changeRequests.isEmpty)
        XCTAssertNotNil(model.error)
    }

    func testStatusFilterIsAppliedClientSide() async {
        let requests = [
            makeChangeRequest(id: "1", status: .planned),
            makeChangeRequest(id: "2", status: .completed)
        ]
        let service = MockChangeRequestService(listResult: .success(requests))
        let model = ChangeRequestListViewModel(service: service, currentUserId: nil)

        await model.load()
        model.setStatusFilter(.completed)

        XCTAssertEqual(model.filteredChangeRequests.map(\.id), ["2"])

        model.setStatusFilter(nil)
        XCTAssertEqual(model.filteredChangeRequests.count, 2)
    }

    func testArchiveTabChangeRefetches() async {
        let requests = [makeChangeRequest(id: "1", status: .planned)]
        let service = MockChangeRequestService(listResult: .success(requests))
        let model = ChangeRequestListViewModel(service: service, currentUserId: nil)

        await model.load()
        XCTAssertEqual(model.archiveTab, .active)

        model.archiveTab = .archived
        // `didSet` kicks off an async Task; give it a tick to run.
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(model.changeRequests.count, 1)
    }

    // MARK: Server-side search and status

    private final class FilterRecordingService: ChangeRequestServicing {
        var filters: [ChangeRequestFilter] = []
        var rows: [ChangeRequest] = []

        func listChangeRequests(filter: ChangeRequestFilter) async throws -> [ChangeRequest] {
            filters.append(filter)
            return rows
        }
        func changeRequest(id: String) async throws -> ChangeRequest { rows[0] }
        func create(_ payload: NewChangeRequestPayload) async throws -> ChangeRequest { rows[0] }
        func update(_ payload: ChangeRequestUpdatePayload) async throws {}
        func delete(id: String, updatedBy: String) async throws {}
    }

    private func waitForLoad(_ service: FilterRecordingService, count: Int) async {
        for _ in 0..<100 where service.filters.count < count {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func query(_ filter: ChangeRequestFilter?) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (filter?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testServerSearchMapping() {
        XCTAssertEqual(ChangeRequestListViewModel.serverSearch(for: "  ").description, "")
        XCTAssertEqual(ChangeRequestListViewModel.serverSearch(for: "login bug").description, "login bug")
        XCTAssertEqual(ChangeRequestListViewModel.serverSearch(for: "32").id, "32")
        XCTAssertEqual(ChangeRequestListViewModel.serverSearch(for: "32").description, "")
        let number = ChangeRequestListViewModel.serverSearch(for: "CR-1030")
        XCTAssertEqual(number.description, "")
        XCTAssertNil(number.id, "display numbers stay an in-memory filter")
    }

    func testStatusFilter_requeriesServerWithStatus() async {
        let service = FilterRecordingService()
        let model = ChangeRequestListViewModel(service: service, currentUserId: nil)
        await model.load()

        model.setStatusFilter(.completed)
        await waitForLoad(service, count: 2)
        XCTAssertEqual(query(service.filters.last)["status"], "completed")

        model.setStatusFilter(.completed)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(service.filters.count, 2, "the same status again doesn't refetch")
    }

    func testSearch_isDebouncedThenSentAsDescription() async {
        let service = FilterRecordingService()
        let model = ChangeRequestListViewModel(service: service, currentUserId: nil)

        model.searchText = "lo"
        model.searchText = "login"
        await waitForLoad(service, count: 1)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(service.filters.count, 1, "typing quickly sends one query")
        XCTAssertEqual(query(service.filters.last)["description"], "login")
    }

    func testSearchByDigits_queriesById() async {
        let service = FilterRecordingService()
        let model = ChangeRequestListViewModel(service: service, currentUserId: nil)
        model.searchText = "32"
        await waitForLoad(service, count: 1)
        XCTAssertEqual(query(service.filters.last)["id"], "32")
        XCTAssertNil(query(service.filters.last)["description"])
    }

    func testServerResultsMatchedByDescriptionOrIdAreKept() async {
        let byDescription = ChangeRequest(
            id: "5", requestNumber: "CR-5", title: "Unrelated title", description: "Fix the login flow",
            status: .planned, severity: nil, requestTypeLabel: nil, requestedByUserId: nil,
            createdByName: nil, projectId: nil, projectName: nil, platforms: [], timeline: [],
            createdAt: nil, stage: nil, totalStages: nil, stageStatus: nil
        )
        let service = FilterRecordingService()
        service.rows = [byDescription]
        let model = ChangeRequestListViewModel(service: service, currentUserId: nil)
        await model.load()

        model.searchText = "login"
        XCTAssertEqual(model.filteredChangeRequests.map(\.id), ["5"])
        model.searchText = "5"
        XCTAssertEqual(model.filteredChangeRequests.map(\.id), ["5"])
    }

    func testFilterSheetFieldsAreSentAsTheWebSendsThem() {
        let model = ChangeRequestListViewModel(service: MockChangeRequestService(), currentUserId: "u-me")
        var filters = ChangeRequestAdvancedFilters(ownerIsMe: false, assigneeIsMe: true)
        filters.ownerId = "u-ann"
        filters.severity = "sv-high"
        filters.requestTypeId = "rt-bug"
        model.advancedFilters = filters

        let sent = query(model.filter(offset: 0))
        XCTAssertEqual(sent["reqOwner"], "u-ann", "a specific owner")
        XCTAssertEqual(sent["user"], "u-me", "assignee Me")
        XCTAssertEqual(sent["severity"], "sv-high", "severity goes as its id; the backend parses a UUID")
        XCTAssertEqual(sent["requestType"], "rt-bug")

        filters.ownerIsMe = true
        model.advancedFilters = filters
        XCTAssertEqual(query(model.filter(offset: 0))["reqOwner"], "u-me", "Me wins over a remembered person")
        filters.ownerIsMe = false
        filters.ownerId = nil
        model.advancedFilters = filters
        XCTAssertNil(query(model.filter(offset: 0))["reqOwner"], "Anyone")
    }

    func testAdvancedFiltersDefaultToMine() {
        let model = ChangeRequestListViewModel(
            service: MockChangeRequestService(), currentUserId: "u-me"
        )

        XCTAssertTrue(model.advancedFilters.ownerIsMe)
        XCTAssertTrue(model.advancedFilters.assigneeIsMe)
    }
}
