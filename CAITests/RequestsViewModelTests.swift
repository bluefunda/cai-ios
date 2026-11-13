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

    var deletes: [(id: String, updatedBy: String)] = []

    func delete(id: String, updatedBy: String) async throws {
        deletes.append((id, updatedBy))
    }
}

/// A request at stage 2 of 3, and a log of every write in the order it was made.
private final class StageFlowServices: ChangeRequestServicing, ChangeRequestWorkflowServicing, CommentServicing {
    var log: [String] = []
    var stagePayloads: [StageUpdatePayload] = []
    var moveError: Error?
    var decideError: Error?
    var workflowLoads = 0
    var workflowResult = RQWorkflow(enforced: false, steps: [])

    var request: ChangeRequest {
        let stages = (1...3).map { RQStage(order: $0, description: "S\($0)", current: $0 == 2) }
        var cr = ChangeRequest(
            id: "32", requestNumber: "CR-32", title: "x", description: nil, status: .inProgress,
            severity: nil, requestTypeLabel: nil, requestedByUserId: nil, createdByName: nil,
            projectId: nil, projectName: nil, platforms: [], timeline: [], createdAt: nil,
            stage: 2, totalStages: 3, stageStatus: nil)
        cr.stages = stages
        cr.currentStage = stages[1]
        return cr
    }

    func listChangeRequests(filter: ChangeRequestFilter) async throws -> [ChangeRequest] { [request] }
    func changeRequest(id: String) async throws -> ChangeRequest { log.append("fetch"); return request }
    func create(_ payload: NewChangeRequestPayload) async throws -> ChangeRequest { request }
    var onUpdate: (@MainActor () -> Void)?
    var updateError: Error?
    func update(_ payload: ChangeRequestUpdatePayload) async throws {
        log.append("status:\(payload.status ?? "")")
        if let onUpdate { await onUpdate() }
        if let updateError { throw updateError }
    }
    func delete(id: String, updatedBy: String) async throws {}

    func moveStage(_ payload: StageUpdatePayload) async throws {
        if let moveError { throw moveError }
        stagePayloads.append(payload)
        log.append("stage:\(payload.order)")
    }
    func workflow(changeRequestId: String) async throws -> RQWorkflow { workflowLoads += 1; return workflowResult }
    func decide(changeRequestId: String, order: Int, _ payload: WorkflowDecisionPayload) async throws {
        if let decideError { throw decideError }
        log.append("decide:\(order):\(payload.decision.rawValue)")
    }

    func comments(forChangeRequestId id: String) async throws -> [RQComment] { [] }
    func postComment(_ body: String, attachments: [RQAttachment], mentions: [String], forChangeRequestId id: String) async throws -> RQComment {
        log.append("comment")
        return RQComment(bodyHTML: body, authorName: "Me", createdAt: Date(), attachments: [])
    }
    func markSeen(changeRequestId: String, userId: String) async throws {}
    func mentionCandidates(projectId: String) async throws -> [ProjectTeamMember] { [] }
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

    // MARK: Files

    private final class FilesService: CRFileServicing {
        var files = [CRFile(name: "a.txt", size: 1, uploaderName: nil, url: "https://x/a"),
                     CRFile(name: "b.txt", size: 1, uploaderName: nil, url: "https://x/b")]
        var deleteError: Error?
        var deleted: [String] = []
        func list(projectId: String, changeRequestId: String) async throws -> [CRFile] { files }
        func upload(projectId: String, changeRequestId: String, fileURL: URL) async throws -> CRFile { files[0] }
        func delete(projectId: String, changeRequestId: String, fileName: String) async throws {
            if let deleteError { throw deleteError }
            deleted.append("\(projectId)/\(changeRequestId)/\(fileName)")
        }
    }

    private func detailWithFiles(_ files: FilesService) -> ChangeRequestDetailViewModel {
        ChangeRequestDetailViewModel(
            changeRequestId: "32", changeRequestService: FixtureChangeRequestService(),
            workflowService: FixtureChangeRequestWorkflowService(), commentService: FixtureCommentService(),
            attachmentService: FixtureAttachmentService(), crFileService: files, currentUserId: "u-1")
    }

    func test_deleteFile_removesItFromTheList() async throws {
        let files = FilesService()
        let model = detailWithFiles(files)
        await model.load()
        let projectId = try XCTUnwrap(model.changeRequest?.projectId)
        XCTAssertEqual(model.crFiles.count, 2)

        await model.deleteFile(model.crFiles[0])

        XCTAssertEqual(model.crFiles.map(\.name), ["b.txt"])
        XCTAssertEqual(files.deleted, ["\(projectId)/32/a.txt"])
        XCTAssertNil(model.error)
    }

    func test_deleteFile_failureKeepsTheFile() async {
        let files = FilesService()
        files.deleteError = RequestsAPIError.serverError(500, "nope")
        let model = detailWithFiles(files)
        await model.load()

        await model.deleteFile(model.crFiles[0])

        XCTAssertEqual(model.crFiles.count, 2)
        XCTAssertNotNil(model.error)
    }

    func test_failedDelete_retryRepeatsThatDeleteNotAReload() async {
        let files = FilesService()
        files.deleteError = RequestsAPIError.serverError(500, "nope")
        let model = detailWithFiles(files)
        await model.load()
        await model.deleteFile(model.crFiles[0])
        XCTAssertNotNil(model.error)

        files.deleteError = nil
        files.files = []  // a reload would empty the list
        await model.retryAfterError()

        XCTAssertNil(model.error)
        XCTAssertEqual(model.crFiles.map(\.name), ["b.txt"], "only the file's delete ran again")
        XCTAssertEqual(files.deleted.count, 1)
    }

    func test_errorBanner_canBeDismissed() async {
        let files = FilesService()
        files.deleteError = RequestsAPIError.serverError(500, "nope")
        let model = detailWithFiles(files)
        await model.load()
        await model.deleteFile(model.crFiles[0])

        model.dismissError()
        XCTAssertNil(model.error)
        files.deleteError = nil
        model.error = "Something else"
        await model.retryAfterError()
        XCTAssertTrue(files.deleted.isEmpty, "a different error reloads instead of repeating the delete")
    }

    // MARK: Delete eligibility (web #320)

    func test_canDelete_atTheFirstStageOrOnceArchived() {
        var cr = RequestsFixtures.changeRequests[0]
        let stages = (1...3).map { RQStage(order: $0, description: "S\($0)", current: $0 == 2) }
        cr.stages = stages
        cr.currentStage = stages[0]
        cr.isArchived = false
        XCTAssertTrue(cr.canDelete, "first stage")
        cr.currentStage = stages[1]
        XCTAssertFalse(cr.canDelete, "past the first stage")
        cr.isArchived = true
        XCTAssertTrue(cr.canDelete, "archived, any stage")
        XCTAssertFalse(cr.isAtFirstStage, "Edit still isn't offered")
    }

    // MARK: Project filters (web #322)

    func test_projectList_startsWithEveryonesRequestsAndFiltersOnTheServer() {
        let model = ChangeRequestListViewModel(service: FixtureChangeRequestService(), currentUserId: "u-me", projectId: "28")
        var sent = model.filter(offset: 0).queryItems
        XCTAssertNil(sent.first { $0.name == "reqOwner" })
        XCTAssertNil(sent.first { $0.name == "user" })
        XCTAssertFalse(model.isFiltered)

        var filters = model.advancedFilters
        filters.assigneeIsMe = true
        filters.ownerId = "u-ann"
        filters.severity = "sv-high"
        filters.requestTypeId = "rt-bug"
        model.advancedFilters = filters
        sent = model.filter(offset: 0).queryItems
        let query = Dictionary(sent.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(query["projectId"], "28")
        XCTAssertEqual(query["reqOwner"], "u-ann")
        XCTAssertEqual(query["user"], "u-me")
        XCTAssertEqual(query["severity"], "sv-high")
        XCTAssertEqual(query["requestType"], "rt-bug")
        XCTAssertTrue(model.isFiltered)

        let requests = ChangeRequestListViewModel(service: FixtureChangeRequestService(), currentUserId: "u-me")
        XCTAssertFalse(requests.isFiltered, "the Requests list still starts on Me/Me")
        XCTAssertTrue(requests.advancedFilters.ownerIsMe)
    }

    func test_projectFilterPeople_areTheTeamWithoutMe() async {
        let model = ProjectDetailViewModel(
            projectId: "28", projectService: FixtureProjectService(),
            changeRequestService: FixtureChangeRequestService(), currentUserId: "u-1")
        await model.load()
        let team = model.project?.team ?? []
        XCTAssertEqual(model.filterPeople.map(\.id), team.map(\.id).filter { $0 != "u-1" })
        XCTAssertFalse(model.filterPeople.contains { $0.id == "u-1" }, "Me covers you")
    }

    // MARK: New project

    func test_newProject_requiresFieldsAndDefaultsTheOwnerToMe() async {
        let model = ProjectFormViewModel(
            projectService: FixtureProjectService(),
            projectTypes: { [] },
            users: { [UserOption(id: "u-1", name: "Me"), UserOption(id: "u-2", name: "Ann")] },
            currentUserId: "u-1")
        await model.loadOptions()
        XCTAssertEqual(model.ownerId, "u-1")
        XCTAssertFalse(model.isValid)

        model.name = "  Payments "
        model.description = "Card flows"
        XCTAssertFalse(model.isValid, "a project type is required")
        model.projectTypeId = "t-2"
        XCTAssertTrue(model.isValid)
        XCTAssertEqual(model.makePayload()?.name, "Payments")
        XCTAssertEqual(model.makePayload()?.repos, [])
        let saved = await model.save()
        XCTAssertTrue(saved)
    }

    func test_editProject_startsFromTheProjectAndSendsAnUpdate() async {
        let project = ProjectDetail(id: "28", name: "Tech Stack", description: "Old", jira: "https://t/1",
                                    projectTypeLabel: "Enhancement", ownerName: "Me", requestCount: 2, team: [],
                                    ownerId: "u-1", projectTypeId: "t-1")
        let model = ProjectFormViewModel(projectService: FixtureProjectService(), projectTypes: { [] },
                                         users: { [] }, currentUserId: "u-1", editing: project)
        XCTAssertEqual(model.name, "Tech Stack")
        XCTAssertEqual(model.ticketUrl, "https://t/1")
        XCTAssertTrue(model.isValid)
        model.description = "New"
        XCTAssertEqual(model.makeUpdatePayload(), ProjectUpdatePayload(
            id: 28, name: "Tech Stack", description: "New", owner: "u-1", projectType: "t-1",
            jira: "https://t/1", updatedBy: "u-1"))
        let saved = await model.save()
        XCTAssertTrue(saved)
    }

    // MARK: Board drag and drop

    func test_boardDrop_updatesStatusThenMovesToTheColumnsStage() async {
        let services = StageFlowServices()
        let model = ChangeRequestListViewModel(service: services, workflowService: services, currentUserId: "u-1")
        await model.load()

        await model.move("32", to: .completed)

        XCTAssertEqual(services.log, ["status:completed", "stage:3"])
        XCTAssertEqual(services.stagePayloads.first?.current, true, "the board sends current: true, as the web does")
        XCTAssertEqual(services.stagePayloads.first?.changeRequestId, 32)

        services.log = []
        await model.move("32", to: .planned)
        XCTAssertEqual(services.log, ["status:planned", "stage:1"])
    }

    func test_boardDrop_showsTheCardMovingUntilTheSaveFinishes() async {
        let services = StageFlowServices()
        let model = ChangeRequestListViewModel(service: services, workflowService: services, currentUserId: "u-1")
        await model.load()
        var duringSave: [String: ChangeRequestStatus] = [:]
        services.onUpdate = { duringSave = model.moving }

        await model.move("32", to: .completed)

        XCTAssertEqual(duringSave, ["32": .completed])
        XCTAssertTrue(model.moving.isEmpty)
    }

    func test_boardDrop_failedSaveClearsTheSpinnerAndShowsTheError() async {
        let services = StageFlowServices()
        services.updateError = RequestsAPIError.serverError(500, "nope")
        let model = ChangeRequestListViewModel(service: services, workflowService: services, currentUserId: "u-1")
        await model.load()

        await model.move("32", to: .completed)

        XCTAssertTrue(model.moving.isEmpty)
        XCTAssertNotNil(model.error)
    }

    func test_boardDrop_toBlockedMovesNoStage() async {
        let services = StageFlowServices()
        let model = ChangeRequestListViewModel(service: services, workflowService: services, currentUserId: "u-1")
        await model.load()

        await model.move("32", to: .blocked)

        XCTAssertEqual(services.log, ["status:blocked"])
    }

    func test_boardDrop_enforcedWorkflowRefusalIsIgnored() async {
        let services = StageFlowServices()
        services.moveError = RequestsAPIError.rejected(status: 409, code: "workflow_enforced", message: "enforced")
        let model = ChangeRequestListViewModel(service: services, workflowService: services, currentUserId: "u-1")
        await model.load()

        await model.move("32", to: .completed)

        XCTAssertNil(model.error)
        XCTAssertEqual(services.log, ["status:completed"])
    }

    func test_boardStageTarget() {
        let request = StageFlowServices().request  // at stage 2 of 3
        XCTAssertEqual(request.boardStageTarget(for: .planned)?.order, 1)
        XCTAssertNil(request.boardStageTarget(for: .inProgress), "already at the second stage")
        XCTAssertEqual(request.boardStageTarget(for: .completed)?.order, 3)
        XCTAssertNil(request.boardStageTarget(for: .blocked))
    }

    // MARK: Detail

    private func makeDetail(
        id: String = "32",
        service: ChangeRequestServicing = FixtureChangeRequestService(),
        workflowService: ChangeRequestWorkflowServicing = FixtureChangeRequestWorkflowService(),
        commentService: CommentServicing = FixtureCommentService()
    ) -> ChangeRequestDetailViewModel {
        ChangeRequestDetailViewModel(
            changeRequestId: id,
            changeRequestService: service,
            workflowService: workflowService,
            commentService: commentService,
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

    func test_detail_delete_sendsIdAndActor() async {
        let service = CountingChangeRequestService()
        let model = makeDetail(service: service)

        let deleted = await model.delete()

        XCTAssertTrue(deleted)
        XCTAssertEqual(service.deletes.map(\.id), ["32"])
        XCTAssertEqual(service.deletes.map(\.updatedBy), ["u-1"])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isSaving)
    }

    func test_detail_deleteFailure_keepsRequestAndShowsError() async {
        var service = MockChangeRequestService(listResult: .success(RequestsFixtures.changeRequests))
        service.deleteResult = .failure(RequestsAPIError.serverError(500, "boom"))
        let model = makeDetail(service: service)
        await model.load()

        let deleted = await model.delete()

        XCTAssertFalse(deleted)
        XCTAssertNotNil(model.error)
        XCTAssertNotNil(model.changeRequest)
    }

    func test_detail_postComment_appends() async {
        let model = makeDetail()
        await model.load()

        await model.postComment("Ship it")
        XCTAssertEqual(model.comments.last?.plainTextBody, "Ship it")

        await model.postComment("   ")
        XCTAssertEqual(model.comments.count, 3, "A blank comment isn't posted")
    }

    // MARK: Stage flow

    private func makeStageDetail(_ services: StageFlowServices) -> ChangeRequestDetailViewModel {
        makeDetail(service: services, workflowService: services, commentService: services)
    }

    func test_savedChanges_countsSavesSoTheListReloads() async throws {
        let services = StageFlowServices()
        let model = makeStageDetail(services)
        await model.load()
        XCTAssertEqual(model.savedChanges, 0, "opening a request isn't a change")

        await model.setArchived(false)
        XCTAssertEqual(model.savedChanges, 1)

        let forward = try XCTUnwrap(model.stageActions.forward)
        _ = await model.moveStage(forward, comment: "")
        XCTAssertEqual(model.savedChanges, 2)

        services.updateError = RequestsAPIError.serverError(500, "nope")
        await model.setArchived(true)
        XCTAssertEqual(model.savedChanges, 2, "a failed save leaves the list alone")
    }

    func test_moveStage_postsCommentThenStageThenStatus() async throws {
        let services = StageFlowServices()
        let model = makeStageDetail(services)
        await model.load()
        let forward = try XCTUnwrap(model.stageActions.forward)
        XCTAssertEqual(forward.kind, .complete)
        services.log.removeAll()

        let moved = await model.moveStage(forward, comment: "Ready for prod")

        XCTAssertTrue(moved)
        XCTAssertEqual(services.log, ["comment", "stage:3", "status:completed", "fetch"])
        XCTAssertEqual(services.stagePayloads.first?.updatedBy, "u-1")
        XCTAssertEqual(services.stagePayloads.first?.changeRequestId, 32)
        XCTAssertEqual(model.comments.count, 1)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isMovingStage)
    }

    func test_moveStage_blankCommentIsNotPosted() async throws {
        let services = StageFlowServices()
        let model = makeStageDetail(services)
        await model.load()
        services.log.removeAll()

        await model.moveStage(try XCTUnwrap(model.stageActions.revert), comment: "  ")

        XCTAssertEqual(services.log, ["stage:1", "status:planned", "fetch"])
    }

    func test_moveStage_failureShowsErrorAndRefetches() async throws {
        let services = StageFlowServices()
        services.moveError = RequestsAPIError.rejected(status: 409, code: "workflow_enforced", message: "Workflow enforcement is on")
        let model = makeStageDetail(services)
        await model.load()
        services.log.removeAll()

        let moved = await model.moveStage(try XCTUnwrap(model.stageActions.forward), comment: "")

        XCTAssertFalse(moved)
        XCTAssertEqual(model.error, "Workflow enforcement is on")
        XCTAssertEqual(services.log, ["fetch"], "no status update after a failed move")
    }

    func test_moveStage_refusesAMoveThatNeedsTheWeb() async throws {
        let services = StageFlowServices()
        let model = makeStageDetail(services)
        await model.load()
        let forward = try XCTUnwrap(model.stageActions.forward)
        services.log.removeAll()

        let webOnly = StageMove(kind: forward.kind, from: forward.from, to: forward.to, status: forward.status, needsWeb: true)
        let moved = await model.moveStage(webOnly, comment: "x")

        XCTAssertFalse(moved)
        XCTAssertTrue(services.log.isEmpty)
    }

    func test_enforcedWorkflowHidesStageButtons() async {
        let services = StageFlowServices()
        services.workflowResult = RQWorkflow(enforced: true, currentOrder: 2,
                                             steps: [RQWorkflowStep(order: 2, description: "QA", state: "current")])
        let model = makeStageDetail(services)
        await model.load()

        XCTAssertTrue(model.isWorkflowEnforced)
        XCTAssertEqual(model.stageActions, .none)
    }

    func test_decide_reloadsWorkflowAndRequest() async {
        let services = StageFlowServices()
        let model = makeStageDetail(services)
        await model.load()
        services.log.removeAll()
        let loads = services.workflowLoads

        let error = await model.decide(.approve, on: RQWorkflowStep(order: 2, description: "QA", state: "current"), comment: " ok ")

        XCTAssertNil(error)
        XCTAssertEqual(services.log, ["decide:2:approve", "fetch"])
        XCTAssertEqual(services.workflowLoads, loads + 1)
        XCTAssertFalse(model.isDeciding)
    }

    func test_decide_staleStepRefreshesAndExplains() async {
        let services = StageFlowServices()
        services.decideError = RequestsAPIError.rejected(status: 409, code: "not_current_step", message: "x")
        let model = makeStageDetail(services)
        await model.load()
        let loads = services.workflowLoads

        let error = await model.decide(.reject, on: RQWorkflowStep(order: 2, description: "QA", state: "current"), comment: "")

        XCTAssertEqual(error, "This step is no longer the current step. The workflow has been refreshed.")
        XCTAssertEqual(services.workflowLoads, loads + 1)
    }

    func test_decide_notApproverDoesNotRefresh() async {
        let services = StageFlowServices()
        services.decideError = RequestsAPIError.requestsUnavailable(statusCode: 403)
        let model = makeStageDetail(services)
        await model.load()
        let loads = services.workflowLoads

        let error = await model.decide(.approve, on: RQWorkflowStep(order: 2, description: "QA", state: "current"), comment: "")

        XCTAssertEqual(error, "You are not an approver for this step.")
        XCTAssertEqual(services.workflowLoads, loads)
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

    private func templateJSON() -> RQRequestTemplate {
        let json = #"""
        {"id":"t-1","name":"Standard","status":true,"workflow":[
          {"order":1,"description":"Development","statusCode":"DEV","qaDeploy":false},
          {"order":2,"description":"QA","statusCode":"","qaDeploy":true}]}
        """#
        return try! JSONDecoder().decode(RQRequestTemplate.self, from: Data(json.utf8))
    }

    private func makeFullNewRequest(systemsAsked: @escaping (String) -> Void = { _ in }) -> NewChangeRequestViewModel {
        let template = templateJSON()
        return NewChangeRequestViewModel(
            changeRequestService: FixtureChangeRequestService(),
            projectService: FixtureProjectService(),
            referenceDataService: FixtureReferenceDataService(),
            sources: NewRequestFormSources(
                templates: { [template] },
                applications: { [ChangeRequestPlatform(id: "sap", description: "S/4HANA", isSAP: true),
                                  ChangeRequestPlatform(id: "gh", description: "GitHub", usesGit: true)] },
                systems: { systemsAsked($0); return [] }
            ),
            currentUserId: "u-1"
        )
    }

    private func fillRequired(_ model: NewChangeRequestViewModel) {
        model.requestName = "Add index"
        model.description = "Nightly report times out."
        model.selectedProjectId = "28"
        model.selectedRequestTypeId = "1"
        model.selectedSeverityId = "3"
    }

    func test_newRequest_templateLaysOutStagesWithOwners() async throws {
        let model = makeFullNewRequest()
        await model.loadOptions()
        fillRequired(model)

        model.selectedTemplateId = "t-1"
        XCTAssertEqual(model.stages.map(\.description), ["Development", "QA"])
        XCTAssertEqual(model.stages[1].statusCode, "QA", "a blank status code falls back to the description")
        model.setOwner("u-2", for: 1)

        let payload = try XCTUnwrap(model.makePayload())
        XCTAssertEqual(payload.projectId, 28)
        XCTAssertEqual(payload.template, "t-1")
        XCTAssertEqual(payload.stage.map(\.current), [true, false], "the first stage is current")
        XCTAssertEqual(payload.stage.map(\.owner), ["u-2", nil])

        model.selectedTemplateId = nil
        XCTAssertTrue(model.stages.isEmpty)
        XCTAssertTrue(try XCTUnwrap(model.makePayload()).stage.isEmpty)
    }

    func test_newRequest_platformsAddSAPSystemAndGitFields() async throws {
        var asked: [String] = []
        let model = makeFullNewRequest { asked.append($0) }
        await model.loadOptions()
        fillRequired(model)

        model.togglePlatform(model.applications[0])
        XCTAssertTrue(model.hasSAPPlatform)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(asked, ["sap"], "an SAP platform loads its systems")
        model.selectedSystemId = "sys-1"
        model.qaBranch.source = "feature/x"

        var payload = try XCTUnwrap(model.makePayload())
        XCTAssertEqual(payload.platform.map(\.id), ["sap"])
        XCTAssertEqual(payload.sapSourceSystemId, "sys-1")
        XCTAssertEqual(payload.deploymentBranches[0].source, "", "branches are only sent for a Git platform")

        model.togglePlatform(model.applications[0])
        model.togglePlatform(model.applications[1])
        payload = try XCTUnwrap(model.makePayload())
        XCTAssertNil(payload.sapSourceSystemId)
        XCTAssertEqual(payload.deploymentBranches[0].source, "feature/x")
    }

    func test_newRequest_templateRequiredWhenApprovalsForEveryRequest() async throws {
        let template = templateJSON()
        let model = NewChangeRequestViewModel(
            changeRequestService: FixtureChangeRequestService(), projectService: FixtureProjectService(),
            referenceDataService: FixtureReferenceDataService(),
            sources: NewRequestFormSources(templates: { [template] },
                                           workflowSettings: { RQWorkflowSettings(enforceWorkflow: true) }),
            currentUserId: "u-1")
        await model.loadOptions()
        fillRequired(model)

        XCTAssertTrue(model.templateRequired)
        XCTAssertFalse(model.isValid, "the backend would refuse it: template_required")
        model.selectedTemplateId = "t-1"
        XCTAssertTrue(model.isValid)
    }

    func test_newRequest_templateOptionalWhenTheSettingIsOffOrUnreadable() async {
        for settings in [{ RQWorkflowSettings(enforceWorkflow: false) }, { throw URLError(.notConnectedToInternet) }]
            as [() async throws -> RQWorkflowSettings] {
            let model = NewChangeRequestViewModel(
                changeRequestService: FixtureChangeRequestService(), projectService: FixtureProjectService(),
                referenceDataService: FixtureReferenceDataService(),
                sources: NewRequestFormSources(workflowSettings: settings), currentUserId: "u-1")
            await model.loadOptions()
            fillRequired(model)
            XCTAssertFalse(model.templateRequired)
            XCTAssertTrue(model.isValid)
        }
    }

    func test_newRequest_teamNarrowsStageOwners() async throws {
        let teamJSON = #"{"id":"tm-1","name":"Core","membersDetails":[{"id":"u-9","name":"Nine"}]}"#
        let team = try JSONDecoder().decode(RQAdminTeam.self, from: Data(teamJSON.utf8))
        let model = NewChangeRequestViewModel(
            changeRequestService: FixtureChangeRequestService(), projectService: FixtureProjectService(),
            referenceDataService: FixtureReferenceDataService(),
            sources: NewRequestFormSources(teams: { [team] }), currentUserId: "u-1")
        await model.loadOptions()

        XCTAssertGreaterThan(model.ownerChoices.count, 1)
        model.selectedTeamId = "tm-1"
        XCTAssertEqual(model.ownerChoices.map(\.name), ["Nine"])
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

    func test_teamMembers_roleFilter() async throws {
        struct Members: TeamServicing {
            func listTeams(forceRefresh: Bool) async throws -> [RQTeam] { [] }
            func members(teamId: String, search: String) async throws -> [RQAdminUser] {
                let json = #"{"users":[{"id":"a","name":"Ann","role":"QA Lead"},{"id":"b","name":"Bob","role":"Developer"},{"id":"c","name":"Cy","role":"Developer"}]}"#
                return try JSONDecoder().decode(RQListEnvelope<RQAdminUser>.self, from: Data(json.utf8)).items
            }
        }
        let model = TeamMembersViewModel(team: RQTeam(id: "t", name: "T", members: []), service: Members())
        await model.load()
        XCTAssertEqual(model.roles, ["Developer", "QA Lead"])
        model.role = "Developer"
        XCTAssertEqual(model.filteredMembers.map(\.name), ["Bob", "Cy"])
        model.role = nil
        XCTAssertEqual(model.filteredMembers.count, 3)
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
