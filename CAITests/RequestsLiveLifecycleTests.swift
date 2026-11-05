import XCTest
@testable import CAI

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
