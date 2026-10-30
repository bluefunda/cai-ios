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

    func testAdvancedFiltersDefaultToMine() {
        let model = ChangeRequestListViewModel(
            service: MockChangeRequestService(), currentUserId: "u-me"
        )

        XCTAssertTrue(model.advancedFilters.ownerIsMe)
        XCTAssertTrue(model.advancedFilters.assigneeIsMe)
    }
}
