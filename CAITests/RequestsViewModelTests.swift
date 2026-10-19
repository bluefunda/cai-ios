import XCTest
@testable import CAI

// MARK: - Requests View Model Tests
// The list, detail and new-request flows against the fixture services
// (RequestsFixtures), plus the load-once behaviour RequestsState relies on.

private final class CountingChangeRequestService: ChangeRequestServicing {
    var listCalls = 0
    var updates: [ChangeRequestUpdatePayload] = []

    func listChangeRequests(filter: ChangeRequestFilter) async throws -> [ChangeRequest] {
        listCalls += 1
        return RequestsFixtures.changeRequests
    }

    func changeRequest(id: String) async throws -> ChangeRequest {
        try await FixtureChangeRequestService().changeRequest(id: id)
    }

    func create(_ payload: NewChangeRequestPayload) async throws -> ChangeRequest {
        RequestsFixtures.changeRequests[0]
    }

    func update(_ payload: ChangeRequestUpdatePayload) async throws {
        updates.append(payload)
    }
}

@MainActor
final class RequestsViewModelTests: XCTestCase {
    // MARK: List

    func test_list_loadIfNeeded_fetchesOnce() async {
        let service = CountingChangeRequestService()
        let model = ChangeRequestListViewModel(service: service, currentUserId: "u-1")

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        XCTAssertEqual(service.listCalls, 1)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.changeRequests.count, RequestsFixtures.changeRequests.count)

        await model.load()
        XCTAssertEqual(service.listCalls, 2, "An explicit load (pull to refresh, ⌘R) always fetches")
    }

    func test_list_searchMatchesTitleAndNumber() async {
        let model = ChangeRequestListViewModel(service: FixtureChangeRequestService(), currentUserId: "u-1")
        await model.load()

        model.searchText = "tls"
        XCTAssertEqual(model.filteredChangeRequests.map(\.id), ["31"])
        model.searchText = "CR-1030"
        XCTAssertEqual(model.filteredChangeRequests.map(\.id), ["29"])
    }

    // MARK: Detail

    private func makeDetail(
        id: String = "32",
        service: ChangeRequestServicing = FixtureChangeRequestService()
    ) -> ChangeRequestDetailViewModel {
        ChangeRequestDetailViewModel(
            changeRequestId: id,
            changeRequestService: service,
            commentService: FixtureCommentService(),
            attachmentService: FixtureAttachmentService(),
            crFileService: FixtureCRFileService(),
            currentUserId: "u-1"
        )
    }

    func test_detail_loadsRequestAndComments() async {
        let model = makeDetail()
        await model.load()

        XCTAssertEqual(model.changeRequest?.requestNumber, "CR-1042")
        XCTAssertEqual(model.comments.count, 2)
        XCTAssertEqual(model.attachments.map(\.fileName), ["migration_plan.pdf"])
        XCTAssertNil(model.error)
    }

    func test_detail_missingRequest_surfacesError() async {
        let model = makeDetail(id: "does-not-exist")
        await model.load()

        XCTAssertNil(model.changeRequest)
        XCTAssertNotNil(model.error)
    }

    func test_detail_setStatusAndArchive_sendPartialUpdates() async {
        let service = CountingChangeRequestService()
        let model = makeDetail(service: service)
        await model.load()

        await model.setStatus(.completed)
        await model.setArchived(true)

        XCTAssertEqual(service.updates.map(\.status), ["completed", nil])
        XCTAssertEqual(service.updates.map(\.archive), [nil, true])
        XCTAssertEqual(service.updates.first?.updatedBy, "u-1")
        XCTAssertFalse(model.isSaving)
    }

    func test_detail_postComment_appends() async {
        let model = makeDetail()
        await model.load()

        await model.postComment("Ship it")
        XCTAssertEqual(model.comments.last?.plainTextBody, "Ship it")

        await model.postComment("   ")
        XCTAssertEqual(model.comments.count, 3, "A blank comment isn't posted")
    }

    // MARK: New request

    private func makeNewRequest(lockedProjectId: String? = nil) -> NewChangeRequestViewModel {
        NewChangeRequestViewModel(
            changeRequestService: FixtureChangeRequestService(),
            projectService: FixtureProjectService(),
            referenceDataService: FixtureReferenceDataService(),
            currentUserId: "u-1",
            lockedProjectId: lockedProjectId
        )
    }

    func test_newRequest_validationAndSubmit() async {
        let model = makeNewRequest()
        await model.loadOptions()

        XCTAssertFalse(model.isValid)
        XCTAssertEqual(model.selectedOwnerId, "u-1", "Owner defaults to the signed-in user")

        model.requestName = "Add index"
        model.description = "Nightly report times out."
        model.selectedProjectId = "28"
        model.selectedRequestTypeId = "1"
        XCTAssertFalse(model.isValid, "Priority is still required")
        model.selectedSeverityId = "3"
        XCTAssertTrue(model.isValid)

        let created = await model.submit()
        XCTAssertNotNil(created)
        XCTAssertNil(model.error)
    }

    func test_newRequest_lockedProject() async {
        let model = makeNewRequest(lockedProjectId: "14")
        await model.loadOptions()
        XCTAssertEqual(model.selectedProjectId, "14")
    }

    // MARK: Projects / Teams

    func test_projects_filterAndSearch() async {
        let model = ProjectsListViewModel(service: FixtureProjectService())
        await model.loadIfNeeded()

        XCTAssertEqual(model.filteredProjects.count, 3)
        model.searchText = "procure"
        XCTAssertEqual(model.filteredProjects.map(\.id), ["14"])
        model.searchText = ""
        model.filters.owner = "Nobody"
        XCTAssertTrue(model.filteredProjects.isEmpty)
    }

    func test_teams_search() async {
        let model = TeamsListViewModel(service: FixtureTeamService())
        await model.loadIfNeeded()

        XCTAssertEqual(model.teams.count, 2)
        model.searchText = "finance"
        XCTAssertEqual(model.filteredTeams.map(\.name), ["Finance Core"])
    }

    // MARK: Profile

    func test_profile_notificationToggle() async {
        let model = ProfileViewModel(service: FixtureProfileService(), userId: "u-1")
        await model.load()
        XCTAssertEqual(model.profile?.teamName, "Platform")
        XCTAssertTrue(model.notificationsEnabled)

        await model.setNotificationsEnabled(false)
        XCTAssertFalse(model.notificationsEnabled)
    }
}
