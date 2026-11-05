import XCTest
@testable import CAI

private struct MockReleaseService: ReleaseServicing {
    var result: Result<[RQRelease], Error> = .success([])

    func listReleases(limit: Int? = nil) async throws -> [RQRelease] {
        try result.get()
    }

    func schedule(_ payload: ReleaseSchedulePayload) async throws {}
    func reschedule(_ payload: ReleaseSchedulePayload) async throws {}

    func releaseCycle() async throws -> RQReleaseCycle? { .default }
    func saveReleaseCycle(_ payload: ReleaseCyclePayload) async throws {}
    func customReleases() async throws -> [RQCustomRelease] { [] }
    func addCustomRelease(_ payload: CustomReleasePayload) async throws {}
}

@MainActor
final class ReleasesListViewModelTests: XCTestCase {
    func testGroupsByPlannedDateAndSortsUndatedLast() async {
        let day1 = Date()
        let day2 = Date().addingTimeInterval(86400)
        let releases = [
            RQRelease(
                changeRequestId: "1", requestId: "CR-1", name: nil, description: nil,
                status: .planned, plannedOn: day2
            ),
            RQRelease(
                changeRequestId: "2", requestId: "CR-2", name: nil, description: nil,
                status: .planned, plannedOn: day1
            ),
            RQRelease(
                changeRequestId: "3", requestId: "CR-3", name: nil, description: nil,
                status: .planned, plannedOn: nil
            )
        ]
        let model = ReleasesListViewModel(service: MockReleaseService(result: .success(releases)))

        await model.load()

        XCTAssertEqual(model.sections.count, 3)
        XCTAssertEqual(model.sections[0].releases.map(\.changeRequestId), ["2"])
        XCTAssertEqual(model.sections[1].releases.map(\.changeRequestId), ["1"])
        XCTAssertNil(model.sections[2].date)
        XCTAssertEqual(model.sections[2].releases.map(\.changeRequestId), ["3"])
    }

    func testScheduleSendsTheDayAndReloads() async {
        final class Recording: ReleaseServicing {
            var scheduled: [ReleaseSchedulePayload] = []
            var loads = 0
            func listReleases(limit: Int?) async throws -> [RQRelease] { loads += 1; return [] }
            func schedule(_ payload: ReleaseSchedulePayload) async throws { scheduled.append(payload) }
            func reschedule(_ payload: ReleaseSchedulePayload) async throws {}
            func releaseCycle() async throws -> RQReleaseCycle? { nil }
            func saveReleaseCycle(_ payload: ReleaseCyclePayload) async throws {}
            func customReleases() async throws -> [RQCustomRelease] { [] }
            func addCustomRelease(_ payload: CustomReleasePayload) async throws {}
        }
        let service = Recording()
        let model = ReleasesListViewModel(service: service, changeRequestService: MockChangeRequestService(), currentUserId: "u-1")
        let request = ChangeRequest(
            id: "12", requestNumber: "CR-12", title: "Index", description: nil, status: .completed,
            severity: nil, requestTypeLabel: nil, requestedByUserId: nil, createdByName: nil,
            projectId: nil, projectName: nil, platforms: [], timeline: [], createdAt: nil,
            stage: nil, totalStages: nil, stageStatus: nil)
        let day = Date()

        let error = await model.schedule(request, on: day)

        XCTAssertNil(error)
        XCTAssertEqual(service.scheduled, [ReleaseSchedulePayload(
            changeRequestId: 12, description: "Index", plannedOn: ReleaseSchedulePayload.plannedOn(day), createdBy: "u-1")])
        XCTAssertEqual(service.loads, 1, "reloaded so it moves out of Ready to schedule")
    }

    func testLoadSurfacesError() async {
        let model = ReleasesListViewModel(
            service: MockReleaseService(result: .failure(RequestsAPIError.requestsUnavailable(statusCode: 401)))
        )

        await model.load()

        XCTAssertTrue(model.sections.isEmpty)
        XCTAssertNotNil(model.error)
    }
}
