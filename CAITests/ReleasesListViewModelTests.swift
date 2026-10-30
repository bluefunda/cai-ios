import XCTest
@testable import CAI

private struct MockReleaseService: ReleaseServicing {
    var result: Result<[RQRelease], Error> = .success([])

    func listReleases(limit: Int? = nil) async throws -> [RQRelease] {
        try result.get()
    }
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

    func testLoadSurfacesError() async {
        let model = ReleasesListViewModel(
            service: MockReleaseService(result: .failure(RequestsAPIError.requestsUnavailable(statusCode: 401)))
        )

        await model.load()

        XCTAssertTrue(model.sections.isEmpty)
        XCTAssertNotNil(model.error)
    }
}
