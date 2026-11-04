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
        let json = #"{"id":"t-1","name":"Standard","status":true,"workflow":[{"order":1,"description":"Development","statusCode":"DEV","qaDeploy":false},{"order":2,"description":"QA","statusCode":"","qaDeploy":true}]}"#
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

// MARK: - Messages Flow
// New conversation (pick people → create → first message, retry-safe), the thread's
// paging merge and reply, and the list's ordering and search.

private struct StubError: LocalizedError {
    var errorDescription: String? { "stub failure" }
}

/// Records every call; each step can be made to fail.
private actor RecordingMessagesService: MessagesServicing {
    var conversations: [RQConversation] = []
    var pages: [[RQMessage]] = []
    var failCreate = false
    var failSendTimes = 0

    private(set) var created: [(topic: String, recipients: [String])] = []
    private(set) var sent: [(text: String, conversationId: String)] = []
    private(set) var seen: [String] = []

    func configure(conversations: [RQConversation] = [], pages: [[RQMessage]] = [],
                   failCreate: Bool = false, failSendTimes: Int = 0) {
        self.conversations = conversations
        self.pages = pages
        self.failCreate = failCreate
        self.failSendTimes = failSendTimes
    }

    func listConversations() async throws -> [RQConversation] { conversations }

    func messages(conversationId: String, before: String?, batchSize: Int) async throws -> [RQMessage] {
        pages.isEmpty ? [] : pages.removeFirst()
    }

    private(set) var sentAttachments: [[RQAttachment]] = []

    func send(_ text: String, attachments: [RQAttachment], conversationId: String) async throws {
        if failSendTimes > 0 {
            failSendTimes -= 1
            throw StubError()
        }
        sent.append((text, conversationId))
        sentAttachments.append(attachments)
    }

    func markSeen(conversationId: String) async throws { seen.append(conversationId) }

    func createConversation(topic: String, recipientIds: [String]) async throws -> String {
        if failCreate { throw StubError() }
        created.append((topic, recipientIds))
        return "conv-\(created.count)"
    }
}

private func adminUser(_ id: String, _ name: String) throws -> RQAdminUser {
    try JSONDecoder().decode(RQAdminUser.self, from: Data(#"{"id":"\#(id)","name":"\#(name)","email":"\#(id)@example.com"}"#.utf8))
}

private func message(_ id: Int, _ at: String, sender: String = "u-1") -> RQMessage {
    RQMessage(id: id, senderId: sender, text: "m\(id)", createdAtRaw: at, sender: nil)
}

@MainActor
final class NewConversationViewModelTests: XCTestCase {
    private func makeModel(_ service: RecordingMessagesService,
                           users: [RQAdminUser] = [],
                           searchError: Error? = nil) -> NewConversationViewModel {
        NewConversationViewModel(
            messagesService: service,
            searchUsers: { _ in
                if let searchError { throw searchError }
                return users
            },
            currentUserId: "me"
        )
    }

    func test_search_hidesCurrentUserAndPeopleAlreadyAdded() async throws {
        let users = [try adminUser("me", "Me"), try adminUser("u-1", "Ann"), try adminUser("u-2", "Bob")]
        let model = makeModel(RecordingMessagesService(), users: users)

        await model.search()
        XCTAssertEqual(model.matches.map(\.id), ["u-1", "u-2"])

        model.add(users[1])
        XCTAssertEqual(model.recipients.map(\.id), ["u-1"])
        XCTAssertEqual(model.matches.map(\.id), ["u-2"])

        await model.search()
        XCTAssertEqual(model.matches.map(\.id), ["u-2"], "an added person isn't offered again")
    }

    /// As the web's drawer: everyone loads once, and typing matches name or email here
    /// (the server's name+active filter found no one in production).
    func test_search_loadsEveryoneOnceAndMatchesNameOrEmail() async throws {
        let users = [try adminUser("u-1", "Phani Kumar"), try adminUser("u-2", "Bob"), try adminUser("pha", "Zed")]
        var loads: [String] = []
        let model = NewConversationViewModel(
            messagesService: RecordingMessagesService(),
            searchUsers: { query in loads.append(query); return users },
            currentUserId: "me")

        model.searchText = "pha"
        await model.search()
        XCTAssertEqual(model.matches.map(\.name), ["Phani Kumar", "Zed"], "name, or email (pha@example.com)")
        model.searchText = "BOB"
        await model.search()
        XCTAssertEqual(model.matches.map(\.id), ["u-2"], "case doesn't matter")
        XCTAssertEqual(loads, [""], "one unfiltered load, as the web's getSystemUserApp()")
    }

    func test_search_hidesDeactivatedUsers() async throws {
        func user(_ json: String) throws -> RQAdminUser {
            try JSONDecoder().decode(RQAdminUser.self, from: Data(json.utf8))
        }
        let users = [
            try user(#"{"id":"a","name":"Active Ann","status":true}"#),
            try user(#"{"id":"b","name":"Gone Bob","status":false}"#),
            try user(#"{"id":"c","name":"Text Cy","status":"in-active"}"#),
            try user(#"{"id":"d","name":"Unknown Dee"}"#)
        ]
        let model = NewConversationViewModel(messagesService: RecordingMessagesService(),
                                             searchUsers: { _ in users }, currentUserId: "me")
        await model.search()
        XCTAssertEqual(model.matches.map(\.id), ["a", "d"], "deactivated hidden; no status counts as active")
    }

    func test_addTwice_keepsOneRecipient_andRemoveWorks() throws {
        let ann = try adminUser("u-1", "Ann")
        let model = makeModel(RecordingMessagesService())
        model.add(ann)
        model.add(ann)
        XCTAssertEqual(model.recipients.count, 1)
        model.remove(ann)
        XCTAssertTrue(model.recipients.isEmpty)
    }

    func test_searchFailure_setsError_andNextSuccessClearsIt() async throws {
        let failing = makeModel(RecordingMessagesService(), searchError: StubError())
        await failing.search()
        XCTAssertEqual(failing.error, "stub failure")
        XCTAssertTrue(failing.matches.isEmpty)
    }

    func test_canSend_needsRecipientAndNonBlankMessage() throws {
        let model = makeModel(RecordingMessagesService())
        XCTAssertFalse(model.canSend)
        model.add(try adminUser("u-1", "Ann"))
        XCTAssertFalse(model.canSend)
        model.message = "   \n "
        XCTAssertFalse(model.canSend, "whitespace isn't a message")
        model.message = "Hello"
        XCTAssertTrue(model.canSend)
    }

    func test_send_createsConversationThenPostsFirstMessage() async throws {
        let service = RecordingMessagesService()
        let model = makeModel(service)
        model.add(try adminUser("u-1", "Ann"))
        model.topic = "  Rollout #42 "
        model.message = "  Hello team  "

        let id = await model.send()

        XCTAssertEqual(id, "conv-1")
        let created = await service.created
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.topic, "Rollout #42")
        XCTAssertEqual(created.first?.recipients, ["u-1"])
        let sent = await service.sent
        XCTAssertEqual(sent.map(\.text), ["Hello team"])
        XCTAssertEqual(sent.map(\.conversationId), ["conv-1"])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isSending)
    }

    func test_emptyTopic_fallsBackToStartOfMessage() async throws {
        let service = RecordingMessagesService()
        let model = makeModel(service)
        model.add(try adminUser("u-1", "Ann"))
        model.message = String(repeating: "a", count: 120)

        _ = await model.send()

        let topic = await service.created.first?.topic
        XCTAssertEqual(topic?.count, 80)
    }

    func test_firstMessageFails_retryResendsWithoutCreatingAnotherConversation() async throws {
        let service = RecordingMessagesService()
        await service.configure(failSendTimes: 1)
        let model = makeModel(service)
        let ann = try adminUser("u-1", "Ann")
        model.add(ann)
        model.message = "Hello"

        let first = await model.send()
        XCTAssertNil(first)
        XCTAssertEqual(model.createdConversationId, "conv-1")
        XCTAssertNotNil(model.error)

        model.remove(ann)
        XCTAssertEqual(model.recipients.count, 1, "recipients are fixed once the conversation exists")

        let retry = await model.send()
        XCTAssertEqual(retry, "conv-1")
        let created = await service.created.count
        XCTAssertEqual(created, 1, "the retry must not create a duplicate conversation")
        let sent = await service.sent.map(\.conversationId)
        XCTAssertEqual(sent, ["conv-1"])
        XCTAssertNil(model.error)
    }

    func test_createFails_reportsErrorAndSendsNothing() async throws {
        let service = RecordingMessagesService()
        await service.configure(failCreate: true)
        let model = makeModel(service)
        model.add(try adminUser("u-1", "Ann"))
        model.message = "Hello"

        let id = await model.send()

        XCTAssertNil(id)
        XCTAssertNil(model.createdConversationId)
        XCTAssertEqual(model.error, "stub failure")
        let sent = await service.sent
        XCTAssertTrue(sent.isEmpty)
    }
}

@MainActor
final class ConversationViewModelTests: XCTestCase {
    private let conversation = RQConversation(
        id: "c-1", topic: "", isGroup: false, lastMessage: nil,
        participants: [RQParticipant(id: "u-1", name: "Ann", profileImage: nil)], unreadCount: 1
    )

    func test_load_ordersOldestFirst_dedupesOverlappingPages_andMarksSeen() async {
        let service = RecordingMessagesService()
        // Pages overlap at their boundary (the backend's page is inclusive).
        await service.configure(pages: [
            [message(3, "2026-11-03T10:03:00Z"), message(2, "2026-11-03T10:02:00Z")],
            [message(2, "2026-11-03T10:02:00Z"), message(1, "2026-11-03T10:01:00Z")]
        ])
        let model = ConversationViewModel(conversation: conversation, service: service, currentUserId: "me")

        await model.load()
        XCTAssertEqual(model.messages.map(\.id), [2, 3])
        let seen = await service.seen
        XCTAssertEqual(seen, ["c-1"])

        await model.refreshLatest()
        XCTAssertEqual(model.messages.map(\.id), [1, 2, 3], "merged by id, no duplicate of 2")
    }

    func test_send_clearsDraftOnSuccess_keepsItOnFailure() async {
        let service = RecordingMessagesService()
        await service.configure(failSendTimes: 1)
        let model = ConversationViewModel(conversation: conversation, service: service, currentUserId: "me")

        model.draft = "Reply"
        await model.send()
        XCTAssertEqual(model.draft, "Reply", "a failed send keeps the text so it isn't lost")
        XCTAssertNotNil(model.error)

        await model.send()
        XCTAssertEqual(model.draft, "")
        let sent = await service.sent.map(\.text)
        XCTAssertEqual(sent, ["Reply"])
    }

    func test_attachmentGoesWithTheNextMessage() async throws {
        let service = RecordingMessagesService()
        let model = ConversationViewModel(conversation: conversation, service: service, currentUserId: "me",
                                          attachmentService: FixtureAttachmentService())
        XCTAssertFalse(model.canSend)

        await model.attach(fileURL: URL(fileURLWithPath: "/tmp/spec.pdf"))
        XCTAssertEqual(model.pendingAttachments.map(\.fileName), ["spec.pdf"])
        XCTAssertTrue(model.canSend, "a file alone can be sent, as on the web")

        await model.send()
        let sent = await service.sentAttachments
        XCTAssertEqual(sent.first?.map(\.fileName), ["spec.pdf"])
        XCTAssertTrue(model.pendingAttachments.isEmpty)

        await model.attach(fileURL: URL(fileURLWithPath: "/tmp/a.txt"))
        model.removePending(model.pendingAttachments[0])
        XCTAssertFalse(model.canSend)
    }

    func test_withoutAnAttachmentService_attachingIsOff() {
        let model = ConversationViewModel(conversation: conversation, service: RecordingMessagesService(), currentUserId: "me")
        XCTAssertFalse(model.canAttach)
    }

    func test_blankDraft_isNotSent() async {
        let service = RecordingMessagesService()
        let model = ConversationViewModel(conversation: conversation, service: service, currentUserId: "me")
        model.draft = "   "
        XCTAssertFalse(model.canSend)
        await model.send()
        let sent = await service.sent
        XCTAssertTrue(sent.isEmpty)
    }

    func test_isMine_comparesSender() {
        let model = ConversationViewModel(conversation: conversation, service: RecordingMessagesService(), currentUserId: "me")
        XCTAssertTrue(model.isMine(message(1, "2026-11-03T10:00:00Z", sender: "me")))
        XCTAssertFalse(model.isMine(message(2, "2026-11-03T10:00:00Z", sender: "u-1")))
    }
}

@MainActor
final class MessagesListViewModelTests: XCTestCase {
    func test_load_sortsNewestFirst_andSearchMatchesTopicOrPeople() async {
        let service = RecordingMessagesService()
        let older = RQConversation(id: "a", topic: "Release plan", isGroup: false,
                                   lastMessage: message(1, "2026-11-01T10:00:00Z"),
                                   participants: [RQParticipant(id: "u-1", name: "Ann", profileImage: nil)], unreadCount: 0)
        let newer = RQConversation(id: "b", topic: "", isGroup: false,
                                   lastMessage: message(2, "2026-11-03T10:00:00Z"),
                                   participants: [RQParticipant(id: "u-2", name: "Bob", profileImage: nil)], unreadCount: 2)
        await service.configure(conversations: [older, newer])
        let model = MessagesListViewModel(service: service, currentUserId: "me")

        await model.load()
        XCTAssertEqual(model.conversations.map(\.id), ["b", "a"])
        XCTAssertTrue(model.hasLoaded)

        model.searchText = "release"
        XCTAssertEqual(model.filteredConversations.map(\.id), ["a"])
        model.searchText = "bob"
        XCTAssertEqual(model.filteredConversations.map(\.id), ["b"])
    }
}

// MARK: - Live lifecycle against the local trm stack
// Opt-in: skipped unless a gateway stand-in answers on 127.0.0.1:8099 (local-stack's trm-gw
// checks JWT signatures, so the run uses ~/bluefunda/local-stack/gwproxy.py, which applies
// krakend.json's routes, collection wrapping and claim headers without that check, and an
// unsigned token for the seeded user). Start it with `python3 gwproxy.py 8099`.
// Drives the real services through the same view models the screens use: create with a
// template and stage owners, edit, comment, the stage flow, board drop, archive, delete.

@MainActor
final class RequestsLiveLifecycleTests: XCTestCase {
    private static let base = "http://127.0.0.1:8099"
    nonisolated private static let me = "4ae24f18-5011-4b6c-9977-2aa762930356"
    private static let other = "00000000-0000-4000-8000-000000000001"

    nonisolated private static var token: String {
        func part(_ object: [String: Any]) -> String {
            (try! JSONSerialization.data(withJSONObject: object)).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return part(["alg": "RS256", "typ": "JWT"]) + "."
            + part(["iss": "https://auth.bluefunda.com/realms/trm", "sub": me, "exp": 4_102_444_800,
                    "preferred_username": "me", "name": "Nirmal T", "realm": "trm"]) + ".c2lnbmF0dXJl"
    }

    private var client: RequestsAPIClient!
    private var projects: ProjectService!
    private var changeRequests: ChangeRequestService!
    private var createdIds: [String] = []

    override func setUp() async throws {
        var probe = URLRequest(url: URL(string: Self.base + "/__proxy_ok")!)
        probe.timeoutInterval = 1
        guard let (_, response) = try? await URLSession.shared.data(for: probe),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw XCTSkip("The local trm stack proxy isn't running on \(Self.base)")
        }
        client = RequestsAPIClient(baseURL: Self.base) { Self.token }
        projects = ProjectService(client: client)
        changeRequests = ChangeRequestService(client: client, projectService: projects)
    }

    override func tearDown() async throws {
        for id in createdIds {
            try? await changeRequests.delete(id: id, updatedBy: Self.me)
        }
    }

    private func newRequestModel() -> NewChangeRequestViewModel {
        NewChangeRequestViewModel(
            changeRequestService: changeRequests, projectService: projects,
            referenceDataService: ReferenceDataService(client: client),
            sources: NewRequestFormSources(admin: AdminService(client: client)),
            currentUserId: Self.me)
    }

    private func detailModel(_ id: String) -> ChangeRequestDetailViewModel {
        let user = User(id: Self.me, email: "me@example.com", name: "Nirmal T", roles: [])
        return ChangeRequestDetailViewModel(
            changeRequestId: id, changeRequestService: changeRequests,
            workflowService: ChangeRequestWorkflowService(client: client),
            commentService: CommentService(client: client, currentUserProvider: { user }),
            attachmentService: FixtureAttachmentService(), crFileService: FixtureCRFileService(),
            currentUserId: Self.me)
    }

    /// The form filled as someone would: required fields, a request number, the seeded
    /// 4-stage template with owners on the first two stages.
    /// A 4-stage template without approvals, so the stage buttons move the request (the
    /// seeded one may require approvals, depending on the local settings).
    private func freeTemplate() async throws -> String {
        let name = "Free 4-stage \(UUID().uuidString.prefix(6))"
        let stages = ["Development", "QA", "UAT", "Completed"].map {
            RQTemplateStage(description: $0, department: "Eng", role: "Developer")
        }
        try await AdminService(client: client).createTemplate(
            RQTemplatePayload(name: name, requireApproval: false, stages: stages, createdBy: Self.me))
        return name
    }

    private func fillForm(_ form: NewChangeRequestViewModel, title: String, number: String,
                          template: String = "Standard 4-stage") throws {
        form.requestName = title
        form.description = "Created by the live lifecycle test."
        form.selectedProjectId = try XCTUnwrap(form.projects.first { $0.name == "Local Sandbox" }?.id)
        form.selectedRequestTypeId = try XCTUnwrap(form.requestTypes.first { $0.type == "Enhancement" }?.id)
        form.selectedSeverityId = try XCTUnwrap(form.severities.first { $0.type == "Medium" }?.id)
        form.ticketUrl = "https://example.com/T-1"
        form.requestNumber = number
        form.selectedTemplateId = try XCTUnwrap(form.activeTemplates.first { $0.name == template }?.id)
        form.setOwner(Self.me, for: 1)
        form.setOwner(Self.other, for: 2)
    }

    func test_scheduleAndMoveARelease() async throws {
        // A completed request without a template or platform: ready to schedule in the app.
        let settings = try await AdminService(client: client).workflowSettings()
        try XCTSkipIf(settings.enforceWorkflow, "approvals are on for every request; a request needs a template")
        let suffix = String(UUID().uuidString.prefix(8))
        let form = newRequestModel()
        await form.loadOptions()
        form.requestName = "Release \(suffix)"
        form.description = "Scheduled by the live test."
        form.selectedProjectId = try XCTUnwrap(form.projects.first { $0.name == "Local Sandbox" }?.id)
        form.selectedRequestTypeId = try XCTUnwrap(form.requestTypes.first?.id)
        form.selectedSeverityId = try XCTUnwrap(form.severities.first?.id)
        let maybeCreated = await form.submit()
        let created = try XCTUnwrap(maybeCreated, form.error ?? "")
        createdIds.append(created.id)
        defer { Task { await Self.removeRelease(created.id) } }
        let detail = detailModel(created.id)
        await detail.setStatus(.completed)
        XCTAssertNil(detail.error)

        let releases = ReleasesListViewModel(service: ReleaseService(client: client),
                                             changeRequestService: changeRequests, currentUserId: Self.me)
        await releases.load()
        XCTAssertNil(releases.error)
        let ready = try XCTUnwrap(releases.readyToSchedule.first { $0.id == created.id }, "completed and not released")

        let day = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let scheduleError = await releases.schedule(ready, on: day)
        XCTAssertNil(scheduleError)
        XCTAssertFalse(releases.readyToSchedule.contains { $0.id == created.id }, "no longer waiting")
        var release = try XCTUnwrap(releases.sections.flatMap(\.releases).first { $0.changeRequestId == created.id })
        XCTAssertEqual(release.status, .planned)
        XCTAssertEqual(release.plannedOn.map { Calendar.current.startOfDay(for: $0) }, Calendar.current.startOfDay(for: day))

        let later = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let moveError = await releases.reschedule(release, to: later)
        XCTAssertNil(moveError)
        release = try XCTUnwrap(releases.sections.flatMap(\.releases).first { $0.changeRequestId == created.id })
        XCTAssertEqual(release.plannedOn.map { Calendar.current.startOfDay(for: $0) }, Calendar.current.startOfDay(for: later))
    }

    /// The gateway has no release delete; cleanup goes to the backend directly.
    private nonisolated static func removeRelease(_ changeRequestId: String) async {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:5001/release?changeRequestId=\(changeRequestId)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    func test_messageWithAttachment() async throws {
        let user = User(id: Self.me, email: "me@example.com", name: "Nirmal T", roles: [])
        let messages = MessagesService(client: client, currentUserProvider: { user })
        let files = AttachmentService(client: client, currentUserProvider: { user })
        let conversationId = try await messages.createConversation(
            topic: "Attachments \(UUID().uuidString.prefix(6))", recipientIds: [Self.other])

        let suffix = UUID().uuidString.prefix(8)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(suffix).txt")
        try Data("release notes \(suffix)".utf8).write(to: fileURL)

        let conversation = RQConversation(id: conversationId, topic: "", isGroup: false, lastMessage: nil,
                                          participants: [], unreadCount: 0)
        let model = ConversationViewModel(conversation: conversation, service: messages, currentUserId: Self.me,
                                          attachmentService: files)
        await model.attach(fileURL: fileURL)
        XCTAssertNil(model.error)
        model.draft = "Notes attached"
        await model.send()
        XCTAssertNil(model.error)

        let sent = try XCTUnwrap(model.messages.first { $0.text == "Notes attached" }, "read back after sending")
        let attachment = try XCTUnwrap(sent.attachments.first)
        XCTAssertEqual(attachment.fileName, "notes-\(suffix).txt")
        let file = try await model.download(attachment)
        XCTAssertEqual(String(data: file.data, encoding: .utf8), "release notes \(suffix)")
    }

    func test_techTemplateWithGateSurvivesSaveAndEdit() async throws {
        let admin = AdminService(client: client)
        let name = "Tech \(UUID().uuidString.prefix(6))"
        var gate = RQTemplateStage(description: "Merged to main", department: "Eng", role: "Developer")
        gate.type = .githubGate
        gate.gate.minApprovals = 2
        let stages = [RQTemplateStage(description: "Build", department: "Eng", role: "Developer"), gate]
        try await admin.createTemplate(RQTemplatePayload(name: name, kind: .tech, stages: stages, createdBy: Self.me))

        let all = try await admin.templates()
        let saved = try XCTUnwrap(all.first { $0.name == name })
        XCTAssertEqual(saved.kind, .tech)
        XCTAssertEqual(saved.workflow.map(\.type), [.approval, .githubGate])
        XCTAssertEqual(saved.workflow.last?.gate.minApprovals, 2)

        // Edited as the form does: loaded, one field changed, saved with what was read.
        var edited = saved.workflow
        edited[0].description = "Build and test"
        try await admin.updateTemplate(id: saved.id, RQTemplatePayload(name: name, kind: saved.kind, stages: edited, createdBy: Self.me))
        let reloaded = try await admin.template(id: saved.id)
        XCTAssertEqual(reloaded?.kind, .tech, "an edit no longer turns a tech template standard")
        XCTAssertEqual(reloaded?.workflow.last?.type, .githubGate, "and keeps its gate step")
        XCTAssertEqual(reloaded?.workflow.first?.description, "Build and test")
    }

    func test_releaseSettingsSaveAndReadBack() async throws {
        let releases = ReleasesListViewModel(service: ReleaseService(client: client),
                                             changeRequestService: changeRequests, currentUserId: Self.me)
        let loadError = await releases.loadSettings()
        XCTAssertNil(loadError, "seed-requests.sql seeds the cycle row")
        let original = try XCTUnwrap(releases.releaseCycle)

        var cycle = original
        cycle.frequency = .biweekly
        cycle.day = .wednesday
        cycle.systemRetry = true
        cycle.attempts = 2
        cycle.time = ReleaseTime(hour: 17, minute: 45)
        let saveError = await releases.saveReleaseCycle(cycle)
        XCTAssertNil(saveError)

        let fetched = try await ReleaseService(client: client).releaseCycle()
        let reread = try XCTUnwrap(fetched)
        XCTAssertEqual(reread.frequency, .biweekly)
        XCTAssertEqual(reread.day, .wednesday)
        XCTAssertEqual(reread.attempts, 2, "the retry count is saved")
        XCTAssertEqual(reread.time, ReleaseTime(hour: 17, minute: 45))

        let day = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let addError = await releases.addCustomRelease(on: day, at: ReleaseTime(hour: 20, minute: 0))
        XCTAssertNil(addError)
        XCTAssertTrue(releases.customReleases.contains {
            $0.date.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
        }, "listed after adding")

        _ = await releases.saveReleaseCycle(original)
    }

    /// "Load earlier messages": the page size and cursor now reach the backend (trm-gw
    /// forwards them; trm-backend accepts the BFF's string batchSize).
    func test_loadEarlierMessages() async throws {
        let user = User(id: Self.me, email: "me@example.com", name: "Nirmal T", roles: [])
        let messages = MessagesService(client: client, currentUserProvider: { user })
        let conversationId = try await messages.createConversation(
            topic: "Paging \(UUID().uuidString.prefix(6))", recipientIds: [Self.other])
        let total = ConversationViewModel.batchSize + 5
        for index in 1...total {
            try await messages.send("p\(index)", conversationId: conversationId)
        }

        let conversation = RQConversation(id: conversationId, topic: "", isGroup: false, lastMessage: nil,
                                          participants: [], unreadCount: 0)
        let model = ConversationViewModel(conversation: conversation, service: messages, currentUserId: Self.me)
        await model.load()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.messages.count, ConversationViewModel.batchSize, "the latest page only")
        XCTAssertTrue(model.hasEarlier)
        XCTAssertEqual(model.messages.last?.text, "p\(total)")

        await model.loadEarlier()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.messages.map(\.text), (1...total).map { "p\($0)" }, "every message once, oldest first")
        XCTAssertFalse(model.hasEarlier, "nothing older left")
    }

    /// Per-template approvals: with the organization switch off, a request from a template
    /// with "Require approvals" can't skip ahead with the stage buttons; one without can.
    func test_templateApprovalsAreEnforcedPerTemplate() async throws {
        let admin = AdminService(client: client)
        let settings = try await admin.workflowSettings()
        try XCTSkipIf(settings.enforceWorkflow, "approvals are on for every request; turn the switch off to test per template")
        let suffix = String(UUID().uuidString.prefix(6))
        let stages = ["Build", "Review", "Done"].map { RQTemplateStage(description: $0, department: "Eng", role: "Developer") }
        try await admin.createTemplate(RQTemplatePayload(name: "Approved \(suffix)", requireApproval: true,
                                                         stages: stages, createdBy: Self.me))
        try await admin.createTemplate(RQTemplatePayload(name: "Free \(suffix)", requireApproval: false,
                                                         stages: stages, createdBy: Self.me))
        let all = try await admin.templates()
        let approved = try XCTUnwrap(all.first { $0.name == "Approved \(suffix)" })
        XCTAssertTrue(approved.requireApproval)
        let free = try XCTUnwrap(all.first { $0.name == "Free \(suffix)" })
        XCTAssertFalse(free.requireApproval)

        func startRequest(from templateName: String) async throws -> Bool {
            let form = newRequestModel()
            await form.loadOptions()
            form.requestName = "\(templateName) request"
            form.description = "Per-template approvals."
            form.selectedProjectId = try XCTUnwrap(form.projects.first { $0.name == "Local Sandbox" }?.id)
            form.selectedRequestTypeId = try XCTUnwrap(form.requestTypes.first?.id)
            form.selectedSeverityId = try XCTUnwrap(form.severities.first?.id)
            form.selectedTemplateId = try XCTUnwrap(form.activeTemplates.first { $0.name == templateName }?.id)
            let maybeCreated = await form.submit()
            let created = try XCTUnwrap(maybeCreated, form.error ?? "")
            createdIds.append(created.id)
            XCTAssertEqual(created.stages.count, 3)
            let detail = detailModel(created.id)
            await detail.load()
            // The buttons as the app would show them without approvals: the backend decides.
            let start = try XCTUnwrap(detail.changeRequest?.stageActions(workflowEnforced: false).forward)
            return await detail.moveStage(start, comment: "")
        }

        let freeMoved = try await startRequest(from: "Free \(suffix)")
        XCTAssertTrue(freeMoved, "a template without approvals moves freely")
        let approvedMoved = try await startRequest(from: "Approved \(suffix)")
        XCTAssertFalse(approvedMoved, "the backend refuses moving past an unapproved step")
    }

    func test_teamMembersTable() async throws {
        let teams = TeamService(client: client)
        let all = try await teams.listTeams(forceRefresh: true)
        let team = try XCTUnwrap(all.first { $0.name == "Core Platform" }, "seed-requests.sql seeds Core Platform")
        let model = TeamMembersViewModel(team: team, service: teams)
        await model.load()
        XCTAssertNil(model.error)
        // The team's members as the team list has them (people can be added or removed
        // while trying the app), with the user records' details.
        XCTAssertEqual(Set(model.members.map(\.id)), Set(team.members.map(\.id)))
        try XCTSkipUnless(team.members.contains { $0.id == Self.other }, "Test User One was removed from Core Platform")
        XCTAssertEqual(model.members.first { $0.id == Self.other }?.role, "QA Lead")
        XCTAssertEqual(model.members.first { $0.id == Self.other }?.email, "test.one@example.com")
        model.role = "QA Lead"
        XCTAssertEqual(model.filteredMembers.map(\.id), [Self.other])

        let search = TeamMembersViewModel(team: team, service: teams)
        search.searchText = "Test"
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(search.members.map(\.id), [Self.other], "search goes to the server")
    }

    func test_createUpdateMoveArchiveDelete() async throws {
        let suffix = String(UUID().uuidString.prefix(8))
        let title = "iOS lifecycle \(suffix)"
        let number = "IOS-\(suffix)"

        let settings = try await AdminService(client: client).workflowSettings()
        try XCTSkipIf(settings.enforceWorkflow, "approvals are on for every request; the stage buttons are refused")

        // Create
        let template = try await freeTemplate()
        let form = newRequestModel()
        await form.loadOptions()
        XCTAssertNil(form.error)
        XCTAssertEqual(form.selectedOwnerId, Self.me)
        try fillForm(form, title: title, number: number, template: template)
        XCTAssertEqual(form.stages.map(\.description), ["Development", "QA", "UAT", "Completed"])
        let maybeCreated = await form.submit()
        XCTAssertNil(form.error)
        let created = try XCTUnwrap(maybeCreated)
        createdIds.append(created.id)

        XCTAssertEqual(created.title, title)
        XCTAssertEqual(created.status, .planned)
        XCTAssertEqual(created.severity, "Medium")
        XCTAssertEqual(created.requestTypeLabel, "Enhancement")
        XCTAssertEqual(created.projectName, "Local Sandbox")
        XCTAssertEqual(created.ticketUrl, "https://example.com/T-1")
        XCTAssertEqual(created.stages.count, 4)
        XCTAssertEqual(created.currentStage?.order, 1)
        XCTAssertEqual(created.currentStageOwnerName, "Nirmal T")
        XCTAssertEqual(created.stages.first { $0.order == 2 }?.ownerId, Self.other)
        XCTAssertNil(created.stages.first { $0.order == 3 }?.ownerId, "an unassigned stage stays unassigned")

        // The same request number again is refused, with the backend's message.
        let duplicate = newRequestModel()
        await duplicate.loadOptions()
        try fillForm(duplicate, title: title + " again", number: number, template: template)
        let refused = await duplicate.submit()
        XCTAssertNil(refused)
        XCTAssertTrue(duplicate.error?.contains("already present") ?? false, duplicate.error ?? "no error")

        // Update, as Edit request saves it
        let detail = detailModel(created.id)
        await detail.load()
        XCTAssertEqual(detail.changeRequest?.title, title)
        let reference = ReferenceDataService(client: client)
        let severities = try await reference.severities(forceRefresh: false)
        let high = try XCTUnwrap(severities.first { $0.type == "High" }?.id)
        await detail.applyEdit(shortDescription: title + " (edited)", description: "Edited description.",
                               requestType: nil, severity: high, requestedBy: Self.other, ticketUrl: "https://example.com/T-2")
        XCTAssertNil(detail.error)
        XCTAssertEqual(detail.changeRequest?.title, title + " (edited)")
        XCTAssertEqual(detail.changeRequest?.description, "Edited description.")
        XCTAssertEqual(detail.changeRequest?.severity, "High")
        XCTAssertEqual(detail.changeRequest?.requestedByUserId, Self.other)
        XCTAssertEqual(detail.changeRequest?.ticketUrl, "https://example.com/T-2")
        XCTAssertFalse(detail.changeRequest?.timeline.isEmpty ?? true, "edits are logged")

        // The filter sheet's priority, type and person filters, as the list sends them
        let medium = try XCTUnwrap(severities.first { $0.type == "Medium" }?.id)
        let types = try await reference.requestTypes(forceRefresh: false)
        let enhancement = try XCTUnwrap(types.first { $0.type == "Enhancement" }?.id)
        func listed(_ configure: (inout ChangeRequestAdvancedFilters) -> Void) async throws -> Bool {
            let list = ChangeRequestListViewModel(service: changeRequests, currentUserId: Self.me)
            var filters = ChangeRequestAdvancedFilters(ownerIsMe: false, assigneeIsMe: false)
            configure(&filters)
            list.advancedFilters = filters
            await list.load()
            XCTAssertNil(list.error)
            return list.changeRequests.contains { $0.id == created.id }
        }
        let byHigh = try await listed { $0.severity = high }
        let byMedium = try await listed { $0.severity = medium }
        let byType = try await listed { $0.requestTypeId = enhancement; $0.severity = high }
        let byOwner = try await listed { $0.ownerId = Self.other }
        let byOtherOwner = try await listed { $0.ownerId = "00000000-0000-4000-8000-000000000099" }
        XCTAssertTrue(byHigh, "now High")
        XCTAssertFalse(byMedium)
        XCTAssertTrue(byType)
        XCTAssertTrue(byOwner, "the edit made Test User One the owner")
        XCTAssertFalse(byOtherOwner)

        // Comment
        await detail.postComment("Lifecycle comment \(suffix)")
        XCTAssertNil(detail.error)
        await detail.load()
        XCTAssertTrue(detail.comments.contains { $0.plainTextBody.contains("Lifecycle comment \(suffix)") })

        // A comment @mentioning someone on the project, then the tab's seen call
        XCTAssertTrue(detail.mentionCandidates.contains { $0.id == Self.other })
        XCTAssertFalse(detail.mentionCandidates.contains { $0.id == Self.me }, "you can't mention yourself")
        await detail.postComment("Ping @Test User One about \(suffix)")
        XCTAssertNil(detail.error)
        await detail.load()
        let mention = try XCTUnwrap(detail.comments.first { $0.plainTextBody.contains("about \(suffix)") })
        XCTAssertTrue(mention.bodyHTML.contains(#"class="wysiwyg-mention""#), mention.bodyHTML)
        XCTAssertEqual(mention.plainTextBody, "Ping @Test User One about \(suffix)")
        await detail.markCommentsSeen()

        // Stage flow: Start, Push to next, Revert, Push to next, Mark as completed
        func move(_ expected: StageMoveKind, revert: Bool = false, comment: String = "") async throws {
            let actions = detail.stageActions
            let next = try XCTUnwrap(revert ? actions.revert : actions.forward)
            XCTAssertEqual(next.kind, expected)
            let moved = await detail.moveStage(next, comment: comment)
            XCTAssertTrue(moved, detail.error ?? "")
            XCTAssertEqual(detail.changeRequest?.currentStage?.order, next.to.order)
            XCTAssertEqual(detail.changeRequest?.status, next.status)
        }
        try await move(.start, comment: "Starting \(suffix)")
        XCTAssertEqual(detail.changeRequest?.status, .inProgress)
        XCTAssertEqual(detail.changeRequest?.currentStageOwnerName, "Test User One", "the target stage keeps its owner")
        try await move(.next)
        try await move(.revert, revert: true)
        XCTAssertEqual(detail.changeRequest?.currentStage?.order, 2)
        try await move(.next)
        try await move(.complete)
        XCTAssertEqual(detail.changeRequest?.status, .completed)
        XCTAssertEqual(detail.stageActions, .none, "the last stage offers no stage buttons")
        XCTAssertTrue(detail.changeRequest?.timeline.contains { $0.actionVerb == "moved the request to" } ?? false)
        await detail.load()
        XCTAssertTrue(detail.comments.contains { $0.plainTextBody.contains("Starting \(suffix)") },
                      "the move's comment was posted")

        // Board drop back to Planned: the status, then the first stage
        let board = ChangeRequestListViewModel(
            service: changeRequests, workflowService: ChangeRequestWorkflowService(client: client),
            currentUserId: Self.me)
        board.advancedFilters = ChangeRequestAdvancedFilters(ownerIsMe: false, assigneeIsMe: false)
        board.searchText = created.id
        await board.load()
        XCTAssertTrue(board.changeRequests.contains { $0.id == created.id })
        await board.move(created.id, to: .planned)
        XCTAssertNil(board.error)
        await detail.load()
        XCTAssertEqual(detail.changeRequest?.status, .planned)
        XCTAssertEqual(detail.changeRequest?.currentStage?.order, 1)

        // Archive, then restore
        await detail.setArchived(true)
        XCTAssertNil(detail.error)
        XCTAssertEqual(detail.changeRequest?.isArchived, true)
        board.archiveTab = .archived
        await board.load()
        XCTAssertTrue(board.changeRequests.contains { $0.id == created.id }, "listed under Archive")
        await detail.setArchived(false)
        XCTAssertEqual(detail.changeRequest?.isArchived, false)

        // Delete
        let deleted = await detail.delete()
        XCTAssertTrue(deleted, detail.error ?? "")
        createdIds.removeAll { $0 == created.id }
        do {
            _ = try await changeRequests.changeRequest(id: created.id)
            XCTFail("A deleted request shouldn't load")
        } catch {}
        board.archiveTab = .active
        await board.load()
        XCTAssertFalse(board.changeRequests.contains { $0.id == created.id })
    }
}
