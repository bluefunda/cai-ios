import XCTest
@testable import CAI

// MARK: - BlueRequests Wire Model Tests
// Ported from trm-ios (TRMTests/APIModelsTests.swift).

final class RequestsAPIModelsTests: XCTestCase {
    /// Shape confirmed against a live response and trm's own frontend source (no OpenAPI
    /// spec exists) — a truncated real sample looked like:
    /// {"combinedResponse":[{"changeRequest":{"id":32,"archive":false,"description":
    /// "Cloud files in BlueFunda AI is not working","importId":"","projectId":28,
    /// "releaseId":"","requestId":"","requestType":"7454...
    func testDecodeChangeRequestListResponse() throws {
        let json = Data("""
        {
            "combinedResponse": [
                {
                    "changeRequest": {
                        "id": 32,
                        "archive": false,
                        "description": "Cloud files in BlueFunda AI is not working",
                        "shortDescription": "Cloud files not working",
                        "status": "inprogress",
                        "importId": "",
                        "projectId": 28,
                        "releaseId": "",
                        "requestId": "",
                        "requestType": "7454",
                        "requestedBy": "u-100",
                        "ticketUrl": "https://jira.example.com/browse/CR-1042"
                    },
                    "requestId": "CR-1042",
                    "severityData": {"id": 2, "type": "High"},
                    "requestTypeData": {"id": 7454, "type": "Database"},
                    "userTimeline": [
                        {
                            "user": {"name": "Alex Smith"},
                            "timeline": {"fieldName": "Status changed", "createdAt": "2026-01-15T10:30:00Z"}
                        }
                    ]
                }
            ],
            "userProfile": {
                "u-100": {"name": "Jane Doe"}
            }
        }
        """.utf8)

        let response = try RequestsAPIClient.makeDecoder().decode(ChangeRequestListResponse.self, from: json)
        XCTAssertEqual(response.combinedResponse.count, 1)

        let cr = response.combinedResponse[0]
        XCTAssertEqual(cr.id, "32")
        XCTAssertEqual(cr.requestNumber, "CR-1042")
        XCTAssertEqual(cr.title, "Cloud files not working")
        XCTAssertEqual(cr.status, .inProgress)
        XCTAssertEqual(cr.severity, "High")
        XCTAssertEqual(cr.requestTypeLabel, "Database")
        XCTAssertEqual(cr.requestedByUserId, "u-100")
        XCTAssertEqual(cr.ticketUrl, "https://jira.example.com/browse/CR-1042")
        XCTAssertEqual(cr.timeline.count, 1)
        XCTAssertEqual(cr.timeline[0].userName, "Alex Smith")
        XCTAssertEqual(response.userProfile?["u-100"]?.name, "Jane Doe")
    }

    /// trm-backend-go CombinedResponse: `stage` is the current stage (with its owner's
    /// profile), `stageData` every stage.
    func testDecodeStagesFromEnvelope() throws {
        let json = Data("""
        {"combinedResponse": [{
            "changeRequest": {"id": 7, "shortDescription": "Fix", "status": "inprogress"},
            "stage": [{"stage": {"order": 2, "description": "QA", "statusCode": "QAS", "current": true,
                                 "completed": false, "owner": "u-9", "qaDeploy": true}, "user": {"name": "Ann"}}],
            "stageData": [
                {"order": 3, "description": "Production", "statusCode": "PRD", "owner": null},
                {"order": 1, "description": "Development", "statusCode": "DEV", "completed": true},
                {"order": 2, "description": "QA", "statusCode": "QAS", "current": true}
            ]
        }]}
        """.utf8)

        let cr = try RequestsAPIClient.makeDecoder().decode(ChangeRequestListResponse.self, from: json).combinedResponse[0]

        XCTAssertEqual(cr.currentStage?.order, 2)
        XCTAssertEqual(cr.currentStage?.ownerId, "u-9")
        XCTAssertEqual(cr.currentStage?.qaDeploy, true)
        XCTAssertEqual(cr.stages.map(\.order), [1, 2, 3], "sorted by order")
        XCTAssertNil(cr.stages[2].ownerId, "a null owner is unassigned")
        XCTAssertEqual(cr.stage, 2)
        XCTAssertEqual(cr.totalStages, 3)
        XCTAssertEqual(cr.stageStatus, "QA")
        XCTAssertFalse(cr.isAtFirstStage)
    }

    func testRequestWithoutStagesCountsAsFirstStage() throws {
        let json = Data(#"{"combinedResponse": [{"changeRequest": {"id": 8, "shortDescription": "x"}}]}"#.utf8)
        let cr = try RequestsAPIClient.makeDecoder().decode(ChangeRequestListResponse.self, from: json).combinedResponse[0]
        XCTAssertNil(cr.currentStage)
        XCTAssertTrue(cr.stages.isEmpty)
        XCTAssertNil(cr.totalStages)
        XCTAssertTrue(cr.isAtFirstStage, "no stages: Edit/Delete stay available")
    }

    func testUnknownStatusFallsBackToOtherInsteadOfCrashing() {
        let status = ChangeRequestStatus(raw: "pending_qa")
        if case .other(let raw) = status {
            XCTAssertEqual(raw, "pending_qa")
        } else {
            XCTFail("Expected .other for an unrecognized status")
        }
    }

    func testDecodeComments() throws {
        let json = Data("""
        {
            "comments": [
                {
                    "comment": "<p>Looks good to me</p>",
                    "createdAt": "2026-01-15T10:30:00Z",
                    "user": {"name": "Jane Doe"},
                    "attachments": [{"id": 5, "name": "plan.pdf"}]
                }
            ]
        }
        """.utf8)

        struct Wrapper: Decodable { let comments: [RQComment] }
        let wrapper = try RequestsAPIClient.makeDecoder().decode(Wrapper.self, from: json)

        XCTAssertEqual(wrapper.comments.count, 1)
        let comment = wrapper.comments[0]
        XCTAssertEqual(comment.plainTextBody, "Looks good to me")
        XCTAssertEqual(comment.authorName, "Jane Doe")
        XCTAssertEqual(comment.attachments.first?.fileName, "plan.pdf")
        XCTAssertEqual(comment.attachments.first?.id, "5")
    }

    /// No live sample exists for this one (unlike ChangeRequest) — this is a best-effort
    /// shape from trm's frontend source, so the test only asserts the defensive decode
    /// doesn't crash and pulls what it can, not exact field values against real data.
    func testDecodeReleases() throws {
        let json = Data("""
        {
            "releases": [
                {
                    "changeRequestId": 32,
                    "requestId": "CR-1042",
                    "status": "inprogress",
                    "plannedOn": "2026-01-20T00:00:00Z"
                },
                {
                    "changeRequestId": 31,
                    "status": "unexpectedstatus"
                }
            ]
        }
        """.utf8)

        let response = try RequestsAPIClient.makeDecoder().decode(ReleaseListResponse.self, from: json)
        XCTAssertEqual(response.releases.count, 2)

        let first = response.releases[0]
        XCTAssertEqual(first.changeRequestId, "32")
        XCTAssertEqual(first.requestId, "CR-1042")
        XCTAssertEqual(first.status, .inProgress)
        XCTAssertNotNil(first.plannedOn)

        let second = response.releases[1]
        XCTAssertEqual(second.changeRequestId, "31")
        XCTAssertNil(second.plannedOn)
        if case .other(let raw) = second.status {
            XCTAssertEqual(raw, "unexpectedstatus")
        } else {
            XCTFail("Expected .other for an unrecognized release status")
        }
    }

    func testDecodeUnreadCounts() throws {
        let json = Data("""
        {
            "totalUnreadMessages": 3,
            "perCRUnreadCounts": [{"crNumber": "32", "count": 2}]
        }
        """.utf8)

        let counts = try JSONDecoder().decode(UnreadCounts.self, from: json)
        XCTAssertEqual(counts.totalUnreadMessages, 3)
        XCTAssertEqual(counts.count(forChangeRequestId: "32"), 2)
        XCTAssertEqual(counts.count(forChangeRequestId: "99"), 0)
    }

    func testNewConversationLinksChangeRequestFromTopic() {
        XCTAssertEqual(RQNewConversation.changeRequestId(inTopic: "Question about #42 rollout"), 42)
        XCTAssertNil(RQNewConversation.changeRequestId(inTopic: "No link here"))
    }

    func testCreatedConversationIdAcceptsNumberOrString() throws {
        let decoder = RequestsAPIClient.makeDecoder()
        XCTAssertEqual(try decoder.decode(RQCreatedConversation.self, from: Data(#"{"conversationId": 17}"#.utf8)).conversationId, "17")
        XCTAssertEqual(try decoder.decode(RQCreatedConversation.self, from: Data(#"{"conversationId": "c-9"}"#.utf8)).conversationId, "c-9")
    }

    /// The requests notification stream sends an array of snapshots; the newest wins,
    /// as in trm's changeRequestHome.js.
    func testDecodeUnreadCountsStreamEventUsesNewestSnapshot() {
        let payload = Data("""
        [
            {"totalUnreadMessages": 1, "perCRUnreadCounts": [{"crNumber": "32", "count": 1}]},
            {"totalUnreadMessages": 4, "perCRUnreadCounts": [{"crNumber": "32", "count": 3}]}
        ]
        """.utf8)

        let counts = NotificationsService.decode(payload, decoder: RequestsAPIClient.makeDecoder())
        XCTAssertEqual(counts?.totalUnreadMessages, 4)
        XCTAssertEqual(counts?.count(forChangeRequestId: "32"), 3)
        XCTAssertNil(NotificationsService.decode(Data("not json".utf8), decoder: RequestsAPIClient.makeDecoder()))
    }

    // MARK: Stage flow

    private func request(at order: Int?, of total: Int, platforms: [ChangeRequestPlatform] = [],
                         qaDeployAt: Int? = nil) -> ChangeRequest {
        let stages = (1...total).map {
            RQStage(order: $0, description: "S\($0)", statusCode: "C\($0)", current: $0 == order,
                    ownerId: "owner-\($0)", qaDeploy: $0 == qaDeployAt)
        }
        var cr = ChangeRequest(
            id: "7", requestNumber: "CR-7", title: "x", description: nil, status: .planned,
            severity: nil, requestTypeLabel: nil, requestedByUserId: nil, createdByName: nil,
            projectId: nil, projectName: nil, platforms: platforms, timeline: [], createdAt: nil,
            stage: order, totalStages: total, stageStatus: nil)
        cr.stages = stages
        cr.currentStage = order.flatMap { o in stages.first { $0.order == o } }
        return cr
    }

    func testFirstStageOffersStartOnly() {
        let actions = request(at: 1, of: 4).stageActions(workflowEnforced: false)
        XCTAssertEqual(actions.forward?.kind, .start)
        XCTAssertEqual(actions.forward?.to.order, 2)
        XCTAssertEqual(actions.forward?.status, .inProgress)
        XCTAssertNil(actions.revert)
    }

    func testMiddleStageOffersNextAndRevert() {
        let actions = request(at: 2, of: 4).stageActions(workflowEnforced: false)
        XCTAssertEqual(actions.forward?.kind, .next)
        XCTAssertEqual(actions.forward?.to.order, 3)
        XCTAssertEqual(actions.revert?.kind, .revert)
        XCTAssertEqual(actions.revert?.to.order, 1)
        XCTAssertEqual(actions.revert?.status, .planned, "back at the first stage is planned")
    }

    func testStageBeforeLastOffersComplete() {
        let actions = request(at: 3, of: 4).stageActions(workflowEnforced: false)
        XCTAssertEqual(actions.forward?.kind, .complete)
        XCTAssertEqual(actions.forward?.status, .completed)
        XCTAssertEqual(actions.forward?.to.ownerId, "owner-4")
    }

    func testLastStageNoStagesOrEnforcedOfferNothing() {
        XCTAssertEqual(request(at: 4, of: 4).stageActions(workflowEnforced: false), .none)
        XCTAssertEqual(request(at: 2, of: 4).stageActions(workflowEnforced: true), .none)
        XCTAssertEqual(request(at: nil, of: 4).stageActions(workflowEnforced: false), .none)
    }

    func testDeployToQAOnSAPOrGitIsLeftToTheWeb() {
        let sap = [ChangeRequestPlatform(description: "S4", isSAP: true)]
        let git = [ChangeRequestPlatform(description: "Web", usesGit: true)]
        XCTAssertEqual(request(at: 2, of: 4, platforms: sap, qaDeployAt: 2).stageActions(workflowEnforced: false).forward?.needsWeb, true)
        XCTAssertEqual(request(at: 2, of: 4, platforms: git, qaDeployAt: 2).stageActions(workflowEnforced: false).forward?.needsWeb, true)
        let plain = request(at: 2, of: 4, qaDeployAt: 2).stageActions(workflowEnforced: false)
        XCTAssertEqual(plain.forward?.needsWeb, false, "no SAP or Git: a plain stage move")
        XCTAssertEqual(request(at: 2, of: 4, platforms: sap, qaDeployAt: 2).stageActions(workflowEnforced: false).revert?.needsWeb, false,
                       "reverting never deploys")
    }

    func testCompletingAnSAPRequestIsLeftToTheWeb() {
        let sap = [ChangeRequestPlatform(description: "S4", isSAP: true)]
        XCTAssertEqual(request(at: 3, of: 4, platforms: sap).stageActions(workflowEnforced: false).forward?.needsWeb, true)
        XCTAssertEqual(request(at: 2, of: 4, platforms: sap).stageActions(workflowEnforced: false).forward?.needsWeb, false)
    }

    func testDecodesPlatformFlagsAndStageOwnerName() throws {
        let json = Data("""
        {"combinedResponse": [{
            "changeRequest": {"id": 9, "shortDescription": "x",
                              "platform": [{"id": "a-1", "description": "S/4 Dev", "sap": true, "git": false},
                                           {"id": "a-2", "description": "Portal", "sap": false, "git": true}]},
            "stage": [{"stage": {"order": 1, "description": "Dev", "current": true}, "user": {"name": "Ann Lee"}}]
        }]}
        """.utf8)
        let cr = try RequestsAPIClient.makeDecoder().decode(ChangeRequestListResponse.self, from: json).combinedResponse[0]
        XCTAssertEqual(cr.platforms.map(\.description), ["S/4 Dev", "Portal"])
        XCTAssertTrue(cr.usesSAP)
        XCTAssertTrue(cr.usesGit)
        XCTAssertEqual(cr.currentStageOwnerName, "Ann Lee")
    }

    func testStageMoveTimelineEntryReadsAsAMove() throws {
        let json = Data(#"{"user": {"name": "Ann"}, "timeline": {"fieldName": "order", "fromStatus": "stage-Dev", "toStatus": "stage-QA"}}"#.utf8)
        let entry = try RequestsAPIClient.makeDecoder().decode(ChangeRequestTimelineEntry.self, from: json)
        XCTAssertEqual(entry.actionVerb, "moved the request to")
        XCTAssertEqual(entry.actionDetail, "QA")
    }

    // MARK: Approval workflow

    func testDecodeWorkflowView() throws {
        let json = Data("""
        {"enforced": true, "currentOrder": 2, "steps": [
            {"order": 1, "statusCode": "DEV", "description": "Development", "type": "approval",
             "department": "", "role": "", "state": "approved",
             "decisions": [{"id": "d-1", "decision": "approve", "actor": {"sub": "u-1", "name": "Ann"},
                            "comment": "ok", "createdAt": "2026-10-01T10:00:00Z"}], "gate": null},
            {"order": 2, "statusCode": "QAS", "description": "", "type": "approval",
             "department": "Finance", "role": "approver", "state": "current", "decisions": [], "gate": null},
            {"order": 3, "statusCode": "GH", "description": "Code review", "type": "github_gate",
             "state": "pending", "decisions": [], "gate": {"status": "approved_stale", "prs": 2, "detail": ""}}
        ]}
        """.utf8)
        let workflow = try RequestsAPIClient.makeDecoder().decode(RQWorkflow.self, from: json)
        XCTAssertTrue(workflow.enforced)
        XCTAssertEqual(workflow.currentOrder, 2)
        XCTAssertEqual(workflow.steps[0].decisions.first?.actorName, "Ann")
        XCTAssertFalse(workflow.steps[0].canDecide)
        XCTAssertTrue(workflow.steps[1].canDecide)
        XCTAssertEqual(workflow.steps[1].title, "QAS", "falls back to the status code")
        XCTAssertTrue(workflow.steps[2].isGate)
        XCTAssertEqual(workflow.steps[2].gateLabel, "Approval is stale")
    }

    func testCanDecideFollowsTheServer() throws {
        let json = #"""
        {"enforced":true,"currentOrder":1,"steps":[
          {"order":1,"description":"In Progress","type":"approval","department":"Engineering","role":"developer",
           "owner":"u-me","canDecide":true,"state":"current","decisions":[]},
          {"order":2,"description":"Review","type":"approval","department":"Engineering","role":"developer",
           "canDecide":false,"state":"current","decisions":[]},
          {"order":3,"description":"Older server","type":"approval","state":"current","decisions":[]}]}
        """#
        let workflow = try JSONDecoder().decode(RQWorkflow.self, from: Data(json.utf8))
        XCTAssertTrue(workflow.steps[0].canDecide, "the stage owner may decide")
        XCTAssertEqual(workflow.steps[0].owner, "u-me")
        XCTAssertFalse(workflow.steps[1].canDecide, "the server says this user can't")
        XCTAssertTrue(workflow.steps[1].isAwaitingDecision, "still shows as waiting")
        XCTAssertTrue(workflow.steps[2].canDecide, "a server that doesn't say leaves the buttons on")
    }

    func testGateStepIsNeverDecidedByHand() {
        let gate = RQWorkflowStep(order: 3, description: "Review", state: "current", type: "github_gate")
        XCTAssertFalse(gate.canDecide)
    }

    func testDecisionErrorMessages() {
        XCTAssertEqual(WorkflowDecisionError.message(for: RequestsAPIError.requestsUnavailable(statusCode: 403)),
                       "You are not an approver for this step.")
        XCTAssertEqual(WorkflowDecisionError.message(for: RequestsAPIError.serverError(500, "x")),
                       "Could not record your decision. Please try again.")
        XCTAssertFalse(WorkflowDecisionError.needsRefresh(RequestsAPIError.rejected(status: 409, code: "workflow_enforced", message: "")))
        XCTAssertTrue(WorkflowDecisionError.needsRefresh(RequestsAPIError.rejected(status: 409, code: "step_is_gate", message: "")))
    }

    // MARK: Comment mentions

    private let ann = ProjectTeamMember(id: "u-ann", name: "Ann", profileImageURL: nil)
    private let annLee = ProjectTeamMember(id: "u-annlee", name: "Ann Lee", profileImageURL: nil)
    private let bob = ProjectTeamMember(id: "u-bob", name: "Bob <B>", profileImageURL: nil)

    func testCommentWithoutMentionsIsSentAsTyped() {
        XCTAssertEqual(CommentComposition.body(for: "plain & simple", mentioning: []), "plain & simple")
    }

    func testMentionsBecomeTheWebEditorsLinks() {
        let text = "@Ann Lee and @Bob <B>, see\nthis"
        let people = CommentComposition.mentions(in: text, from: [bob, ann, annLee])
        XCTAssertEqual(people.map(\.id), ["u-annlee", "u-bob"], "@Ann Lee doesn't also mention Ann")
        XCTAssertEqual(CommentComposition.mentions(in: "@Ann and @Ann Lee", from: [ann, annLee]).map(\.id),
                       ["u-ann", "u-annlee"])
        XCTAssertEqual(CommentComposition.body(for: "@Ann and @Ann Lee", mentioning: [ann, annLee]),
                       #"<p><a href="u-ann" class="wysiwyg-mention" data-mention data-value="Ann">@Ann</a> and "#
                       + #"<a href="u-annlee" class="wysiwyg-mention" data-mention data-value="Ann Lee">@Ann Lee</a></p>"#)
        let html = CommentComposition.body(for: text, mentioning: [annLee, bob])
        XCTAssertEqual(html, #"<p><a href="u-annlee" class="wysiwyg-mention" data-mention data-value="Ann Lee">@Ann Lee</a> and "#
            + #"<a href="u-bob" class="wysiwyg-mention" data-mention data-value="Bob &lt;B&gt;">@Bob &lt;B&gt;</a>, see<br>this</p>"#)
    }

    func testMentionedPeopleMustStillBeInTheText() {
        XCTAssertEqual(CommentComposition.mentions(in: "hi @Bob <B> @Bob <B>", from: [ann, bob]).map(\.id), ["u-bob"],
                       "listed once, and someone removed from the text isn't mentioned")
    }

    func testActiveMentionQueryAndCompletion() {
        XCTAssertEqual(CommentComposition.activeQuery(in: "hey @an"), "an")
        XCTAssertEqual(CommentComposition.activeQuery(in: "@"), "")
        XCTAssertNil(CommentComposition.activeQuery(in: "mail me@example.com"), "an @ inside a word isn't a mention")
        XCTAssertNil(CommentComposition.activeQuery(in: "no mention"))
        XCTAssertEqual(CommentComposition.complete("hey @an", with: annLee), "hey @Ann Lee ")
    }

    // MARK: Releases

    /// GET /release as the gateway returns it: the releases are nested in the first entry,
    /// and the counts entry holds none.
    func testReleaseListReadsTheNestedReleases() throws {
        let json = #"{"releases": [{"releases": [{"changeRequestId": 1002, "status": "planned", "description": "Pricing fix", "plannedOn": "2026-11-07T00:00:00.000Z", "platform": [{"id": "a", "description": "S/4HANA Dev", "sap": true, "git": false}], "requestId": ""}, {"changeRequestId": 1003, "status": "released", "description": "Index", "plannedOn": "2026-11-01T00:00:00Z", "platform": []}]}, {"plannedCount": 1, "platformCounts": {"S/4HANA Dev": 1}, "releasedCount": 0}]}"#
        let response = try RequestsAPIClient.makeDecoder().decode(ReleaseListResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.releases.map(\.changeRequestId), ["1002", "1003"], "no made-up rows for the counts entry")
        XCTAssertNotNil(response.releases[0].plannedOn, "milliseconds in the date")
        XCTAssertNil(response.releases[0].requestId, "an empty request number reads as none")
        XCTAssertTrue(response.releases[0].needsWebToSchedule)
        XCTAssertFalse(response.releases[1].needsWebToSchedule)
        XCTAssertEqual(response.releases[1].status, .released)
    }

    func testReleaseDateIsTheDaysLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 15))!
        XCTAssertEqual(ReleaseSchedulePayload.plannedOn(afternoon, calendar: calendar), "2026-11-06T18:30:00.000Z",
                       "moment().startOf('day').toISOString(), as the web's columns are keyed")
    }

    // MARK: Request templates

    func testTemplatePayloadKeepsKindStepTypeAndGateAsTheWebSendsThem() throws {
        var gate = RQTemplateStage(description: "Merged", department: "Eng", role: "Dev")
        gate.type = .githubGate
        gate.gate.minApprovals = 2
        let stages = [
            RQTemplateStage(description: "Dev", department: "Eng", role: "Dev"),
            RQTemplateStage(description: "", department: "", role: ""),  // incomplete: dropped
            gate
        ]
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            RQTemplatePayload(name: "Tech flow", kind: .tech, stages: stages, createdBy: "u-1"))) as? [String: Any])
        XCTAssertEqual(body["kind"] as? String, "tech")
        let workflow = try XCTUnwrap(body["workflow"] as? [[String: Any]])
        XCTAssertEqual(workflow.map { $0["order"] as? Int }, [1, 3], "the editor position, as the web numbers it")
        XCTAssertEqual(workflow.map { $0["type"] as? String }, ["approval", "github_gate"])
        XCTAssertNil(workflow[0]["gate"], "only a gate step carries a policy")
        let policy = try XCTUnwrap(workflow[1]["gate"] as? [String: Any])
        XCTAssertEqual(policy["minApprovals"] as? Int, 2)
        XCTAssertEqual(policy["requireMerged"] as? Bool, true)
        XCTAssertEqual(body["requireApproval"] as? Bool, false, "sent every time, so an edit can switch it off")

        let standard = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            RQTemplatePayload(name: "Std", kind: .standard, stages: [gate], createdBy: "u-1"))) as? [String: Any])
        let step = try XCTUnwrap((standard["workflow"] as? [[String: Any]])?.first)
        XCTAssertEqual(step["type"] as? String, "approval", "a standard template has no gate steps")
        XCTAssertNil(step["gate"])
    }

    func testOlderTemplatesReadAsStandardApprovalSteps() throws {
        let old = #"{"id":"t","name":"Old","status":true,"workflow":[{"order":1,"description":"Dev","department":"Eng","role":"Dev","qaDeploy":false}]}"#
        let template = try JSONDecoder().decode(RQRequestTemplate.self, from: Data(old.utf8))
        XCTAssertEqual(template.kind, .standard)
        XCTAssertEqual(template.workflow.first?.type, .approval)
        XCTAssertFalse(template.requireApproval, "older templates have no approvals")

        let tech = #"{"id":"t2","name":"Tech","kind":"tech","workflow":[{"order":1,"description":"PR","department":"Eng","role":"Dev","type":"github_gate","gate":{"minApprovals":3}}]}"#
        let gated = try JSONDecoder().decode(RQRequestTemplate.self, from: Data(tech.utf8))
        XCTAssertEqual(gated.kind, .tech)
        XCTAssertEqual(gated.workflow.first?.type, .githubGate)
        XCTAssertEqual(gated.workflow.first?.gate.minApprovals, 3)
        XCTAssertEqual(gated.workflow.first?.gate.requireChecksGreen, true, "missing fields take the web's defaults")
    }

    // MARK: Release settings

    func testReleaseCyclePayloadSendsWhatTheBackendReads() throws {
        var cycle = RQReleaseCycle.default
        cycle.frequency = .biweekly
        cycle.day = .tuesday
        cycle.systemRetry = true
        cycle.attempts = 2
        cycle.time = ReleaseTime(hour: 9, minute: 5)
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            ReleaseCyclePayload(cycle, createdBy: "u-1"))) as? [String: Any])
        XCTAssertEqual(body["attempts"] as? Int, 2, "the field the backend reads; the web's `attempt` is dropped")
        XCTAssertNil(body["attempt"])
        XCTAssertEqual(body["day"] as? String, "tuesday", "bi weekly cycles keep their weekday")
        XCTAssertNil(body["date"])
        XCTAssertEqual(body["time"] as? String, "09:05:00+00")
        XCTAssertEqual(body["frequency"] as? String, "biweekly")

        cycle.frequency = .monthly
        cycle.dayOfMonth = 15
        cycle.systemRetry = false
        body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            ReleaseCyclePayload(cycle, createdBy: "u-1"))) as? [String: Any])
        XCTAssertEqual(body["date"] as? String, "15")
        XCTAssertNil(body["day"])
        XCTAssertEqual(body["attempts"] as? Int, 0, "no retries without system retry, as the web sends")
    }

    func testReleaseCycleReadsTheGatewaysShape() throws {
        let json = #"{"releases": [{"id": 1, "frequency": "monthly", "day": "", "systemRetry": true, "manualRetry": false, "attempts": 2, "date": "15", "time": "18:30:00+00"}]}"#
        let cycle = try XCTUnwrap(try JSONDecoder().decode(RQListEnvelope<RQReleaseCycle>.self, from: Data(json.utf8)).items.first)
        XCTAssertEqual(cycle.frequency, .monthly)
        XCTAssertEqual(cycle.dayOfMonth, 15)
        XCTAssertEqual(cycle.time, ReleaseTime(hour: 18, minute: 30))
        XCTAssertEqual(cycle.attempts, 2)
        XCTAssertEqual(cycle.day, .friday, "an empty weekday falls back to the web's default")
    }

    func testCustomReleaseDateIsTheDayAt1830OnTheDevice() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        let payload = CustomReleasePayload(day: day, time: ReleaseTime(hour: 20, minute: 0), createdBy: "u-1", calendar: calendar)
        XCTAssertEqual(payload.date, "2026-11-20T13:00:00.000Z")
        XCTAssertEqual(payload.time, "20:00:00+00")
    }
}
