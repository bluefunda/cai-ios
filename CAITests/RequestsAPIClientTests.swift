import XCTest
@testable import CAI

// MARK: - Requests API Client Tests
// Guards P11 of docs/BLUEREQUESTS_INTEGRATION.md: a 401/403 from trm-gw is a
// non-fatal "BlueRequests unavailable", never a sign-out of chat — plus the
// header contract trm-gw / trm-backend-go rely on.

@MainActor
final class RequestsAPIClientTests: XCTestCase {
    private class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        static var lastRequest: URLRequest?

        /// Only intercepts BlueRequests traffic, so registering globally (needed for
        /// the RequestsServices test, which uses URLSession.shared) can't swallow
        /// anything else.
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.absoluteString.hasPrefix(AppConfig.requestsBaseURL) ?? false
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            MockURLProtocol.lastRequest = request
            guard let handler = MockURLProtocol.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeClient() -> RequestsAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return RequestsAPIClient(
            baseURL: AppConfig.requestsBaseURL,
            tokenProvider: { "test-token" },
            session: URLSession(configuration: config)
        )
    }

    private func respond(status: Int, body: String = "") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.lastRequest = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func test_sendsBearerAndAccessTokenHeaders_andNoRealmHeader() async throws {
        respond(status: 200, body: #"{"releases":[]}"#)

        let _: ReleaseListResponse = try await makeClient().get("/rest/trm/v1/release")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Access-Token"), "test-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Realm"))
        XCTAssertEqual(request.url?.absoluteString, "https://api.bluefunda.com/requests/rest/trm/v1/release")
    }

    func test_401And403_mapToRequestsUnavailable() async {
        for status in [401, 403] {
            respond(status: status, body: #"{"error":"forbidden"}"#)
            do {
                let _: ReleaseListResponse = try await makeClient().get("/rest/trm/v1/release")
                XCTFail("Expected a throw for HTTP \(status)")
            } catch RequestsAPIError.requestsUnavailable(let code) {
                XCTAssertEqual(code, status)
            } catch {
                XCTFail("Expected requestsUnavailable for HTTP \(status), got \(error)")
            }
        }
    }

    func test_blankBody_decodesAsEmptyList() async throws {
        respond(status: 200, body: "  ")
        let response: ReleaseListResponse = try await makeClient().get("/rest/trm/v1/release")
        XCTAssertTrue(response.releases.isEmpty)
    }

    // MARK: Messages wire contract (trm/src/apiCalls/messagesApis.js)

    /// URLProtocol sees a POST's body as a stream, not `httpBody`.
    private func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Path under the configured base URL (prod's `/requests`, or none for the local stack).
    private func path(_ route: String) -> String {
        (URL(string: AppConfig.requestsBaseURL)?.path ?? "") + route
    }

    private func makeMessagesService(userId: String = "me") -> MessagesService {
        let user = User(id: userId, email: "me@example.com", name: "Me", roles: [], organizations: ["trm"])
        return MessagesService(client: makeClient(), currentUserProvider: { user })
    }

    func test_createConversation_postsDiscussionWithCreatorOnceAndLinkedRequest() async throws {
        respond(status: 200, body: #"{"conversationId": 17}"#)

        let id = try await makeMessagesService().createConversation(
            topic: "Rollout of #42", recipientIds: ["u-1", "me", "u-1", "u-2"]
        )

        XCTAssertEqual(id, "17")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, path("/discussions"))
        let body = try bodyJSON(request)
        XCTAssertEqual(body["userIDs"] as? [String], ["u-1", "u-2", "me"], "each user once, creator last")
        XCTAssertEqual(body["creatorId"] as? String, "me")
        XCTAssertEqual(body["topic"] as? String, "Rollout of #42")
        XCTAssertEqual(body["changeRequestId"] as? Int, 42)
    }

    func test_sendMessage_sendsAttachmentsAsTheWebDoes() async throws {
        respond(status: 200, body: #"{"success":true}"#)
        try await makeMessagesService().send(
            "", attachments: [RQAttachment(id: "f-1", fileName: "spec.pdf")], conversationId: "c-9")
        let body = try bodyJSON(try XCTUnwrap(MockURLProtocol.lastRequest))
        let attachments = try XCTUnwrap(body["attachments"] as? [[String: Any]])
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments[0]["id"] as? String, "f-1")
        XCTAssertEqual(attachments[0]["fileName"] as? String, "spec.pdf")
    }

    func test_messages_latestPageLeavesTheCursorToTheServer() async throws {
        let service = makeMessagesService()
        respond(status: 200, body: #"{"discussionDetail":{"Messages":[]}}"#)
        _ = try await service.messages(conversationId: "c-9", before: nil, batchSize: 30)
        var query = URLComponents(url: try XCTUnwrap(MockURLProtocol.lastRequest?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "batchSize" }?.value, "30")
        XCTAssertNil(query.first { $0.name == "lastMessageTimestamp" }, "a whole-second device time hid just-sent messages")

        respond(status: 200, body: #"{"discussionDetail":{"Messages":[]}}"#)
        _ = try await service.messages(conversationId: "c-9", before: "2026-11-03T10:55:43.954Z", batchSize: 30)
        query = URLComponents(url: try XCTUnwrap(MockURLProtocol.lastRequest?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "lastMessageTimestamp" }?.value, "2026-11-03T10:55:43.954Z", "sent back exactly")
    }

    func test_sendMessage_timestampHasMilliseconds() async throws {
        respond(status: 200, body: #"{"success":true}"#)
        try await makeMessagesService().send("Hi", conversationId: "c-9")
        let createdAt = try XCTUnwrap(try bodyJSON(try XCTUnwrap(MockURLProtocol.lastRequest))["createdAt"] as? String)
        XCTAssertNotNil(createdAt.range(of: #"T\d{2}:\d{2}:\d{2}\.\d{3}Z$"#, options: .regularExpression),
                        "ordered and paged by this time, like the web's toISOString(): \(createdAt)")
    }

    func test_messageHistory_readsAttachments() throws {
        let json = #"{"conversationId":"c","discussionDetail":{"Messages":[{"id":3,"senderId":"me","message":"see file","createdAt":"2026-11-03T09:53:00Z","attachments":[{"id":"f-1","fileName":"att.txt"}]},{"id":4,"senderId":"me","message":"none","createdAt":"2026-11-03T09:54:00Z","attachments":null}]}}"#
        let history = try RequestsAPIClient.makeDecoder().decode(RQConversationHistory.self, from: Data(json.utf8))
        XCTAssertEqual(history.messages[0].attachments, [RQAttachment(id: "f-1", fileName: "att.txt")])
        XCTAssertTrue(history.messages[1].attachments.isEmpty)
        let comment = try JSONDecoder().decode(RQAttachment.self, from: Data(#"{"id":"f-2","name":"log.txt"}"#.utf8))
        XCTAssertEqual(comment.fileName, "log.txt", "comment attachments still read `name`")
    }

    func test_createConversation_withoutLinkOmitsChangeRequestId() async throws {
        respond(status: 200, body: #"{"conversationId": "c-1"}"#)
        _ = try await makeMessagesService().createConversation(topic: "Hello", recipientIds: ["u-1"])
        let body = try bodyJSON(try XCTUnwrap(MockURLProtocol.lastRequest))
        XCTAssertNil(body["changeRequestId"])
    }

    func test_sendMessage_postsToConversationAsCurrentUser() async throws {
        respond(status: 200, body: "{}")

        try await makeMessagesService().send("Hi team", conversationId: "c-9")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, path("/discussions/c-9/messages"))
        let body = try bodyJSON(request)
        XCTAssertEqual(body["senderId"] as? String, "me")
        XCTAssertEqual(body["message"] as? String, "Hi team")
        XCTAssertEqual(body["conversationId"] as? String, "c-9")
    }

    func test_listConversations_isScopedToCurrentUser() async throws {
        respond(status: 200, body: #"{"conversations": []}"#)
        let conversations = try await makeMessagesService(userId: "u-7").listConversations()
        XCTAssertTrue(conversations.isEmpty)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, path("/users/u-7/conversations"))
    }

    func test_deleteChangeRequest_putsNumericIdAndActor() async throws {
        respond(status: 200, body: "{}")
        let service = ChangeRequestService(client: makeClient(), projectService: FixtureProjectService())

        try await service.delete(id: "32", updatedBy: "me")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, path("/rest/trm/v1/change-request-delete"))
        let body = try bodyJSON(request)
        XCTAssertEqual(body["id"] as? Int, 32)
        XCTAssertEqual(body["updatedBy"] as? String, "me")
    }

    // MARK: Stage flow and workflow

    private func sampleMove() -> StageMove {
        StageMove(kind: .next,
                  from: RQStage(order: 2, description: "QA", statusCode: "QAS", current: true),
                  to: RQStage(order: 3, description: "UAT", statusCode: "UAT", ownerId: "u-7"),
                  status: .inProgress, needsWeb: false)
    }

    // MARK: Workflow enforcement

    func test_workflowSettings_readAndSetAsTheWebDoes() async throws {
        let admin = AdminService(client: makeClient())
        respond(status: 200, body: #"{"enforceWorkflow":false}"#)
        let current = try await admin.workflowSettings()
        XCTAssertFalse(current.enforceWorkflow)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, path("/settings/workflow"))

        respond(status: 200, body: #"{"enforceWorkflow":true}"#)
        let saved = try await admin.setWorkflowEnforcement(true)
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(try bodyJSON(request) as NSDictionary, ["enforceWorkflow": true] as NSDictionary)
        XCTAssertTrue(saved.enforceWorkflow)
    }

    func test_workflowSettings_nonAdminRefusalSurfacesTheMessage() async {
        respond(status: 400, body: #"{"error":{"code":"forbidden","message":"Changing workflow settings requires the admin or super-admin role"}}"#)
        do {
            _ = try await AdminService(client: makeClient()).setWorkflowEnforcement(true)
            XCTFail("Expected a throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("admin or super-admin"), error.localizedDescription)
        }
    }

    // MARK: Releases

    func test_scheduleAndReschedule_sendTheWebsBodies() async throws {
        let service = ReleaseService(client: makeClient())
        respond(status: 200, body: #"{"changeRequestId":5,"status":"planned"}"#)
        try await service.schedule(ReleaseSchedulePayload(changeRequestId: 5, description: "Index", plannedOn: "2026-11-06T18:30:00.000Z", createdBy: "u-1"))
        var request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, path("/rest/trm/v1/release"))
        var body = try bodyJSON(request)
        XCTAssertEqual(body["changeRequestId"] as? Int, 5)
        XCTAssertEqual(body["plannedOn"] as? String, "2026-11-06T18:30:00.000Z")
        XCTAssertEqual(body["createdBy"] as? String, "u-1")
        XCTAssertNil(body["updatedBy"])

        respond(status: 200, body: #"{"changeRequestId":5}"#)
        try await service.reschedule(ReleaseSchedulePayload(changeRequestId: 5, description: "Index", plannedOn: "2026-11-13T18:30:00.000Z", updatedBy: "u-1"))
        request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        body = try bodyJSON(request)
        XCTAssertEqual(body["updatedBy"] as? String, "u-1")
        XCTAssertNil(body["createdBy"])
    }

    func test_schedule_errorBodyThrows() async {
        respond(status: 200, body: #"[{"status":"error","message":"Error inserting release: duplicate key"}]"#)
        do {
            try await ReleaseService(client: makeClient()).schedule(
                ReleaseSchedulePayload(changeRequestId: 5, description: "x", plannedOn: "2026-11-06T18:30:00.000Z", createdBy: "u-1"))
            XCTFail("Expected a throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("duplicate key"))
        }
    }

    // MARK: Teams

    func test_teamMembers_queriesUsersOfTheTeam() async throws {
        respond(status: 200, body: #"{"users":[{"id":"u-1","name":"Nirmal T","email":"n@example.com","role":"Developer","status":true}]}"#)
        let members = try await TeamService(client: makeClient()).members(teamId: "t-1", search: "nir")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, path("/rest/trm/v1/user"))
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
            .queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["team"], "t-1")
        XCTAssertEqual(query["name"], "nir")
        XCTAssertEqual(query["assign"], "true")
        XCTAssertEqual(members.first?.email, "n@example.com")
        XCTAssertEqual(members.first?.role, "Developer")
    }

    // MARK: Comments

    private func commentService() -> CommentService {
        let me = User(id: "u-1", email: "me@example.com", name: "Me", roles: [])
        return CommentService(client: makeClient(), currentUserProvider: { me })
    }

    func test_postComment_sendsMentionsAsTheWebDoes() async throws {
        respond(status: 200, body: #"{"id":1}"#)
        _ = try await commentService().postComment("<p>hi</p>", attachments: [], mentions: ["u-2"], forChangeRequestId: "32")
        let body = try bodyJSON(try XCTUnwrap(MockURLProtocol.lastRequest))
        let mentions = try XCTUnwrap(body["mentions"] as? [[String: Any]])
        XCTAssertEqual(mentions.count, 1)
        XCTAssertEqual(mentions[0]["userId"] as? String, "u-2")
        XCTAssertEqual(mentions[0]["read"] as? Bool, false)
        XCTAssertEqual(body["changeRequestId"] as? Int, 32)
    }

    func test_markSeen_putsTheUsersSeenRoute() async throws {
        respond(status: 200, body: #"{"success":true}"#)
        try await commentService().markSeen(changeRequestId: "32", userId: "u-1")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, path("/change-requests/32/comments/u-1/seen"))
    }

    // MARK: Files

    func test_deleteFile_sendsPathOfProjectRequestAndName() async throws {
        respond(status: 200, body: #"{"message":"deleted"}"#)
        try await CRFileService(client: makeClient()).delete(projectId: "1", changeRequestId: "32", fileName: "spec v2.pdf")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, path("/rest/trm/v1/deleteFile"))
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "path" }?.value, "1/32/spec v2.pdf")
    }

    // MARK: Update

    func test_update_sendsIdAsNumber() throws {
        let payload = ChangeRequestUpdatePayload(id: "1005", createdBy: "u-1", updatedBy: "u-1", status: "planned")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(body["id"] as? Int, 1005, "trm-backend-go decodes id into an int; a string fails the update")
        XCTAssertEqual(body["status"] as? String, "planned")
        XCTAssertNil(body["shortDescription"], "unchanged fields stay out")
    }

    /// A failed write answers 200 with an error body; it used to be reported as saved.
    func test_update_errorBodyThrows() async {
        respond(status: 200, body: #"[{"time":"2026-11-03T09:06:47Z","status":"error","message":"decode failed for change request id 0x1"}]"#)
        let service = ChangeRequestService(client: makeClient(), projectService: FixtureProjectService())
        do {
            try await service.update(ChangeRequestUpdatePayload(id: "32", createdBy: "u-1", updatedBy: "u-1", archive: true))
            XCTFail("Expected a throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("decode failed"))
        }
    }

    func test_update_successBodyDoesNotThrow() async throws {
        respond(status: 200, body: #"{"ID":32,"Archive":true,"Description":""}"#)
        let service = ChangeRequestService(client: makeClient(), projectService: FixtureProjectService())
        try await service.update(ChangeRequestUpdatePayload(id: "32", createdBy: "u-1", updatedBy: "u-1", archive: true))
    }

    // MARK: Create

    private func samplePayload() -> NewChangeRequestPayload {
        NewChangeRequestPayload(
            shortDescription: "Add index", description: "Nightly report", projectId: 1,
            requestType: "rt-1", severity: "sv-1", requestedBy: "u-1", createdBy: "u-1", ticketUrl: "")
    }

    func test_create_sendsProjectIdAsNumberAndNullTemplate() throws {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(samplePayload())) as? [String: Any])
        XCTAssertEqual(body["projectId"] as? Int, 1, "trm-backend-go decodes projectId into an int")
        XCTAssertTrue(body["template"] is NSNull)
        XCTAssertEqual((body["stage"] as? [Any])?.count, 0)
        XCTAssertEqual((body["deploymentBranches"] as? [[String: Any]])?.map { $0["system"] as? String }, ["qa", "prd"])
        XCTAssertNil(body["sapSourceSystemId"], "only sent for an SAP platform")
        XCTAssertEqual(body["updatedBy"] as? String, "u-1")
        XCTAssertEqual(body["qualityCheck"] as? String, "pending", "the backend's sync path would insert an invalid \"\"")
    }

    func test_create_stagesAndPlatformsEncodeAsTheWebSendsThem() throws {
        var payload = samplePayload()
        payload.template = "t-1"
        payload.platform = [ChangeRequestPlatform(id: "a-1", description: "S/4HANA", isSAP: true)]
        payload.stage = [
            .init(order: 1, description: "Dev", statusCode: "DEV", qaDeploy: false, owner: "u-2", current: true, updatedBy: "u-1"),
            .init(order: 2, description: "QA", statusCode: "QAS", qaDeploy: true, owner: nil, current: false, updatedBy: "u-1")
        ]
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        let stages = try XCTUnwrap(body["stage"] as? [[String: Any]])
        XCTAssertEqual(stages[0]["owner"] as? String, "u-2")
        XCTAssertEqual(stages[0]["current"] as? Bool, true)
        XCTAssertNil(stages[1]["owner"], "an unassigned owner is left out: the backend reads a nullable UUID")
        XCTAssertEqual(stages[1]["qaDeploy"] as? Bool, true)
        let platform = try XCTUnwrap((body["platform"] as? [[String: Any]])?.first)
        XCTAssertEqual(platform["sap"] as? Bool, true)
        XCTAssertEqual(platform["git"] as? Bool, false)
        XCTAssertEqual(platform["description"] as? String, "S/4HANA")
    }

    /// The create endpoint reports failure as a 200 error list.
    func test_create_errorListInBodyThrowsItsMessage() async {
        respond(status: 200, body: #"[{"status":"error","message":"requestId CR-9 is already present in the database"}]"#)
        let service = ChangeRequestService(client: makeClient(), projectService: FixtureProjectService())
        do {
            _ = try await service.create(samplePayload())
            XCTFail("Expected a throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("already present"))
        }
    }

    func test_moveStage_putsTargetStage() async throws {
        respond(status: 200, body: #"{"status":"success","message":"Stage updated successfully"}"#)
        let service = ChangeRequestWorkflowService(client: makeClient())

        try await service.moveStage(StageUpdatePayload(move: sampleMove(), changeRequestId: 32, updatedBy: "me", totalStages: 4))

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, path("/rest/trm/v1/stage"))
        let body = try bodyJSON(request)
        XCTAssertEqual(body["order"] as? Int, 3)
        XCTAssertEqual(body["owner"] as? String, "u-7", "the target keeps its own owner")
        XCTAssertEqual(body["changeRequestId"] as? Int, 32)
        XCTAssertEqual(body["updatedBy"] as? String, "me")
        XCTAssertEqual(body["description"] as? String, "UAT")
        XCTAssertEqual(body["statusCode"] as? String, "UAT")
        XCTAssertEqual(body["current"] as? Bool, false)
    }

    func test_moveStage_unassignedOwnerIsSentAsNull() async throws {
        respond(status: 200, body: #"{"status":"success"}"#)
        let move = StageMove(kind: .start, from: RQStage(order: 1, description: "Dev"),
                             to: RQStage(order: 2, description: "QA"), status: .inProgress, needsWeb: false)
        try await ChangeRequestWorkflowService(client: makeClient())
            .moveStage(StageUpdatePayload(move: move, changeRequestId: 1, updatedBy: "me", totalStages: 2))
        let body = try bodyJSON(try XCTUnwrap(MockURLProtocol.lastRequest))
        XCTAssertTrue(body["owner"] is NSNull)
        XCTAssertEqual(body["current"] as? Bool, true, "moving onto the last stage")
    }

    /// The stage endpoint reports failure in a 200 body.
    func test_moveStage_errorStatusInBodyThrows() async {
        respond(status: 200, body: #"{"status":"error","message":"Update stage failed for changeRequestId 32"}"#)
        do {
            try await ChangeRequestWorkflowService(client: makeClient())
                .moveStage(StageUpdatePayload(move: sampleMove(), changeRequestId: 32, updatedBy: "me", totalStages: 4))
            XCTFail("Expected a throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Update stage failed"))
        }
    }

    func test_moveStage_enforcedWorkflowSurfacesCode() async {
        respond(status: 409, body: #"{"error":{"code":"workflow_enforced","message":"Workflow enforcement is on: step 3 needs its earlier steps approved first"}}"#)
        do {
            try await ChangeRequestWorkflowService(client: makeClient())
                .moveStage(StageUpdatePayload(move: sampleMove(), changeRequestId: 32, updatedBy: "me", totalStages: 4))
            XCTFail("Expected a throw")
        } catch RequestsAPIError.rejected(let status, let code, let message) {
            XCTAssertEqual(status, 409)
            XCTAssertEqual(code, "workflow_enforced")
            XCTAssertTrue(message.hasPrefix("Workflow enforcement is on"))
        } catch {
            XCTFail("Expected rejected, got \(error)")
        }
    }

    func test_workflow_getsViewForRequest() async throws {
        respond(status: 200, body: #"{"enforced":true,"currentOrder":2,"steps":[{"order":2,"description":"QA","type":"approval","state":"current","decisions":[]}]}"#)
        let workflow = try await ChangeRequestWorkflowService(client: makeClient()).workflow(changeRequestId: "32")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, path("/change-requests/32/workflow"))
        XCTAssertTrue(workflow.enforced)
        XCTAssertEqual(workflow.steps.first?.canDecide, true)
    }

    func test_decide_postsDecisionAndComment() async throws {
        respond(status: 201, body: #"{"id":"d-1","decision":"reject"}"#)
        try await ChangeRequestWorkflowService(client: makeClient())
            .decide(changeRequestId: "32", order: 2, WorkflowDecisionPayload(decision: .reject, comment: "Missing tests"))
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, path("/change-requests/32/steps/2/decisions"))
        let body = try bodyJSON(request)
        XCTAssertEqual(body["decision"] as? String, "reject")
        XCTAssertEqual(body["comment"] as? String, "Missing tests")
        XCTAssertEqual(body.count, 2, "the actor comes from the token")
    }

    func test_decide_notCurrentStepMapsToWebMessage() async {
        respond(status: 409, body: #"{"error":{"code":"not_current_step","message":"step 2 is not current"}}"#)
        do {
            try await ChangeRequestWorkflowService(client: makeClient())
                .decide(changeRequestId: "32", order: 2, WorkflowDecisionPayload(decision: .approve, comment: ""))
            XCTFail("Expected a throw")
        } catch {
            XCTAssertTrue(WorkflowDecisionError.needsRefresh(error))
            XCTAssertEqual(WorkflowDecisionError.message(for: error),
                           "This step is no longer the current step. The workflow has been refreshed.")
        }
    }

    func test_createConversation_serverErrorThrows() async {
        respond(status: 500, body: #"{"error":"boom"}"#)
        do {
            _ = try await makeMessagesService().createConversation(topic: "x", recipientIds: ["u-1"])
            XCTFail("Expected a throw")
        } catch RequestsAPIError.serverError(let code, _) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Expected serverError, got \(error)")
        }
    }

    #if DEBUG
    /// End to end through RequestsServices with a signed-in AuthManager: a trm-gw
    /// 401 must leave the chat session intact.
    func test_requests401_doesNotEndChatSession() async {
        let authManager = AuthManager()
        authManager.seedForScreenshots(
            user: User(id: "u-1", email: "a@example.com", name: "A", roles: [], organizations: ["trm"]),
            accessToken: "live-token"
        )
        URLProtocol.registerClass(MockURLProtocol.self)
        respond(status: 401)
        let services = RequestsServices(authManager: authManager, useFixtures: false)

        do {
            _ = try await services.changeRequestService.listChangeRequests(filter: ChangeRequestFilter())
            XCTFail("Expected requestsUnavailable")
        } catch RequestsAPIError.requestsUnavailable(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Expected requestsUnavailable, got \(error)")
        }

        XCTAssertTrue(authManager.isAuthenticated)
        XCTAssertNotNil(authManager.currentUser)
        XCTAssertEqual(authManager.accessToken, "live-token")
        XCTAssertNil(authManager.error)
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Access-Token"), "live-token")
    }
    #endif
}

// MARK: - Unread Poller Gating

@MainActor
final class UnreadCountPollerTests: XCTestCase {
    func test_pollsOnlyWhenRequestsAvailableAndAppActive() {
        let poller = UnreadCountPoller(service: FixtureNotificationsService(), interval: 3600)

        poller.update(isRequestsAvailable: false, isAppActive: true)
        XCTAssertFalse(poller.isPolling)
        poller.update(isRequestsAvailable: true, isAppActive: false)
        XCTAssertFalse(poller.isPolling)
        poller.update(isRequestsAvailable: true, isAppActive: true)
        XCTAssertTrue(poller.isPolling)
        poller.update(isRequestsAvailable: true, isAppActive: false)
        XCTAssertFalse(poller.isPolling)
    }

    func test_losingEntitlementClearsCounts_backgroundingKeepsThem() async throws {
        let poller = UnreadCountPoller(service: FixtureNotificationsService(), interval: 3600)
        poller.update(isRequestsAvailable: true, isAppActive: true)
        for _ in 0..<50 where poller.counts == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(poller.counts?.totalUnreadMessages, 2)

        poller.update(isRequestsAvailable: true, isAppActive: false)
        XCTAssertNotNil(poller.counts)

        poller.update(isRequestsAvailable: false, isAppActive: false)
        XCTAssertNil(poller.counts)
    }
}
