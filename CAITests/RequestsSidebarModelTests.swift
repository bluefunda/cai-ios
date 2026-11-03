import XCTest
@testable import CAI

// MARK: - Requests Sidebar Model Tests
// Recently viewed (capped, de-duplicated, persisted, cleared per user) and the quick
// filter presets the Requests sidebar applies to the list.

@MainActor
final class RequestsSidebarModelTests: XCTestCase {
    private nonisolated static let suiteName = "RequestsSidebarModelTests"
    private var defaults: UserDefaults { UserDefaults(suiteName: Self.suiteName)! }

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    private func recent(_ id: Int) -> RecentRequest {
        RecentRequest(id: "\(id)", number: "CR-\(id)", title: "Request \(id)")
    }

    // MARK: Recently viewed

    func test_recents_newestFirst_deduplicated_capped() {
        let store = RecentRequestsStore(defaults: defaults)
        for id in 1...10 { store.record(recent(id)) }
        store.record(recent(5))

        XCTAssertEqual(store.items.count, RecentRequestsStore.limit)
        XCTAssertEqual(store.items.first?.id, "5")
        XCTAssertEqual(store.items.filter { $0.id == "5" }.count, 1)
        XCTAssertFalse(store.items.contains { $0.id == "1" }, "Oldest entries fall off")
    }

    func test_recents_persistAndClear() {
        let store = RecentRequestsStore(defaults: defaults)
        store.record(recent(1))
        store.record(recent(2))

        XCTAssertEqual(RecentRequestsStore(defaults: defaults).items.map(\.id), ["2", "1"])

        store.removeAll()
        XCTAssertTrue(RecentRequestsStore(defaults: defaults).items.isEmpty)
    }

    // MARK: Quick filters

    func test_quickFilters_presets() {
        XCTAssertEqual(RequestsQuickFilter.allCases.first, .all)
        XCTAssertEqual(RequestsQuickFilter.allCases.count, 2 + ChangeRequestStatus.allCases.count)

        XCTAssertTrue(RequestsQuickFilter.mine.advancedFilters.ownerIsMe)
        XCTAssertTrue(RequestsQuickFilter.mine.advancedFilters.assigneeIsMe)
        XCTAssertFalse(RequestsQuickFilter.all.advancedFilters.ownerIsMe)
        XCTAssertEqual(RequestsQuickFilter.status(.blocked).statusFilter, .blocked)
        XCTAssertNil(RequestsQuickFilter.mine.statusFilter)
    }

    func test_quickFilters_roundTripThroughListModel() {
        let model = ChangeRequestListViewModel(service: FixtureChangeRequestService(), currentUserId: "u-1")
        XCTAssertEqual(model.activeQuickFilter, .mine, "The list's default is Mine, as in trm-ios")

        for filter in RequestsQuickFilter.allCases {
            model.apply(filter)
            XCTAssertEqual(model.activeQuickFilter, filter)
        }
    }

    func test_quickFilters_noPresetForCustomFilters() {
        var custom = ChangeRequestAdvancedFilters()
        custom.severity = "30000000-0000-4000-8000-000000000003"
        XCTAssertNil(RequestsQuickFilter.matching(advanced: custom, status: nil))

        var someoneElse = ChangeRequestAdvancedFilters(ownerIsMe: false, assigneeIsMe: false)
        someoneElse.ownerId = "u-2"
        XCTAssertNil(RequestsQuickFilter.matching(advanced: someoneElse, status: nil))

        var ownerOnly = ChangeRequestAdvancedFilters()
        ownerOnly.assigneeIsMe = false
        XCTAssertNil(RequestsQuickFilter.matching(advanced: ownerOnly, status: nil))
    }
}

// MARK: - Ask AI About Requests (P8)

@MainActor
final class RequestChatBridgeTests: XCTestCase {
    private func request(timelineCount: Int = 12) -> ChangeRequest {
        let base = Date(timeIntervalSince1970: 1_793_000_000)
        var cr = ChangeRequest(
            id: "1001", requestNumber: "CR-1001", title: "Orders reporting index",
            description: "Add an index on orders (customer_id, created_at).", status: .inProgress,
            severity: "High", requestTypeLabel: "Enhancement", requestedByUserId: "u-1", createdByName: "Nirmal T",
            projectId: "1", projectName: "Local Sandbox",
            platforms: [ChangeRequestPlatform(id: "a", description: "S/4HANA Dev", isSAP: true)],
            timeline: (0..<timelineCount).map { i in
                ChangeRequestTimelineEntry(userName: "User \(i)", fieldName: "order", fromStatus: "stage-A",
                                           toStatus: "stage-S\(i)", createdAt: base.addingTimeInterval(Double(i) * 60))
            },
            createdAt: base, stage: nil, totalStages: nil, stageStatus: nil)
        let stages = (1...4).map { RQStage(order: $0, description: ["Development", "QA", "UAT", "Completed"][$0 - 1], current: $0 == 2) }
        cr.stages = stages
        cr.currentStage = stages[1]
        return cr
    }

    func test_context_takesTheLatestTenActivitiesNewestFirst() {
        let context = RequestChatContext(request())
        XCTAssertEqual(context.number, "CR-1001")
        XCTAssertEqual(context.platforms, ["S/4HANA Dev"])
        XCTAssertEqual(context.stage, 2)
        XCTAssertEqual(context.totalStages, 4)
        XCTAssertEqual(context.stageName, "QA")
        XCTAssertEqual(context.timeline.count, RequestChatContext.timelineLimit)
        XCTAssertTrue(context.timeline[0].hasPrefix("User 11 moved the request to S11"), context.timeline[0])
        XCTAssertTrue(context.timeline[9].hasPrefix("User 2 "))
    }

    func test_prompt_carriesTheRequestAndTheQuestion() {
        let prompt = RequestPromptBuilder.buildPrompt(question: "What's left to do?", request: RequestChatContext(request()))
        for part in ["CR-1001", "Title: Orders reporting index", "Status: In progress", "Stage: 2 of 4 (QA)",
                     "Platforms: S/4HANA Dev", "Description:\nAdd an index", "Recent activity (newest first):\n- User 11",
                     "Question: What's left to do?"] {
            XCTAssertTrue(prompt.contains(part), "missing \(part)\n\(prompt)")
        }
        XCTAssertTrue(RequestPromptBuilder.buildPrompt(question: "  ", request: RequestChatContext(request()))
            .contains("Question: Summarise this change request"))
    }

    func test_links_firstMessageCarriesTheContextOnceAndLinksTheChat() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let links = RequestChatLinks(defaults: defaults)
        links.setUser("u-1")
        links.attach(RequestChatContext(request()), to: "chat-1")
        XCTAssertEqual(links.pendingContext(for: "chat-1")?.number, "CR-1001")

        let prompt = links.consumePrompt(for: "chat-1", question: "Why is it blocked?")
        XCTAssertTrue(prompt?.contains("Question: Why is it blocked?") ?? false)
        XCTAssertNil(links.pendingContext(for: "chat-1"), "only the first message carries it")
        XCTAssertNil(links.consumePrompt(for: "chat-1", question: "And now?"), "later messages are sent as typed")
        XCTAssertEqual(links.link(forConversation: "chat-1")?.number, "CR-1001")
        XCTAssertEqual(links.conversations(forRequest: "1001").map(\.conversationId), ["chat-1"])
        XCTAssertNil(links.consumePrompt(for: "chat-2", question: "x"), "a chat without a request is untouched")
    }

    func test_links_arePerUserAndSurviveRelaunch() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let links = RequestChatLinks(defaults: defaults)
        links.setUser("u-1")
        links.link(conversationId: "chat-1", requestId: "1001", number: "CR-1001", title: "Index")
        links.setUser("u-2")
        XCTAssertNil(links.link(forConversation: "chat-1"), "another account doesn't see them")

        let relaunched = RequestChatLinks(defaults: defaults)
        relaunched.setUser("u-1")
        XCTAssertEqual(relaunched.link(forConversation: "chat-1")?.requestId, "1001")
        relaunched.unlink(conversationId: "chat-1")
        XCTAssertTrue(relaunched.conversations(forRequest: "1001").isEmpty)
    }

    func test_prefill_titleFromTheChatAndAnswerAsPlainText() {
        let markdown = "## Root cause\nThe **index** is missing.\n\n- Add `idx_orders`\n- Re-run the report"
        let prefill = NewRequestPrefill(chatTitle: "Slow orders report", answerMarkdown: markdown, conversationId: "chat-1")
        XCTAssertEqual(prefill.title, "Slow orders report")
        XCTAssertEqual(prefill.description, "Root cause\nThe index is missing.\n- Add idx_orders\n- Re-run the report")

        let untitled = NewRequestPrefill(chatTitle: "New Chat", answerMarkdown: markdown, conversationId: nil)
        XCTAssertEqual(untitled.title, "Root cause", "an untitled chat uses the answer's first line")
    }

    func test_newRequestPrefillKeepsWhatWasTyped() async {
        let model = NewChangeRequestViewModel(
            changeRequestService: FixtureChangeRequestService(), projectService: FixtureProjectService(),
            referenceDataService: FixtureReferenceDataService(), currentUserId: "u-1")
        model.requestName = "Typed already"
        let prefill = NewRequestPrefill(chatTitle: "From chat", answerMarkdown: "Body", conversationId: nil)
        _ = model.applying(prefill)
        XCTAssertEqual(model.requestName, "Typed already")
        XCTAssertEqual(model.description, "Body")
    }

    func test_sidebarRowChangesWhenTheChatIsLinked() {
        let conversation = Conversation(id: "chat-1", title: "Slow report", messages: [], model: "m", createdAt: Date())
        XCTAssertNotEqual(SidebarRowItem(conversation), SidebarRowItem(conversation, requestNumber: "CR-1001"),
                          "the row redraws to show the number")
    }

    func test_bridgeActionsCompareEqualSoMessagesDontRedraw() {
        let a = RequestBridgeActions(askAI: { _ in }, openConversation: { _ in }, createRequest: { _ in }, chatTitle: { _ in nil })
        let b = RequestBridgeActions(askAI: { _ in }, openConversation: { _ in }, createRequest: { _ in }, chatTitle: { _ in "x" })
        XCTAssertEqual(a, b)
    }
}
