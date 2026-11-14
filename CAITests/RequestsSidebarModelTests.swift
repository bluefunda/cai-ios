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

    // MARK: Prefill from an answer (requestChatLinks.test.js)

    private let answer = "## Plan\n\nUse **bulk** updates and `BAPI_X`:\n\n1. Read [the note](https://x)\n- Fix _it_\n\n```abap\nWRITE x.\n```\n\n---"

    func test_prefill_plainTextDropsMarks() {
        XCTAssertEqual(NewRequestPrefill.plainText(answer), "Plan\nUse bulk updates and BAPI_X:\n- Read the note\n- Fix it\nWRITE x.")
    }

    func test_prefill_keepsTheAnswersSections() {
        XCTAssertEqual(NewRequestPrefill.requestDescription(answer),
                       "Plan:\nUse bulk updates and BAPI_X:\n\n- Read the note\n- Fix it\n\nWRITE x.")
        XCTAssertEqual(NewRequestPrefill.requestDescription("Intro line.\n\n## Problem\nIt fails.\n\n## Fix\n- Retry\n- Log"),
                       "Intro line.\n\nProblem:\nIt fails.\n\nFix:\n- Retry\n- Log")
    }

    func test_prefill_namedAfterTheFirstNonGenericHeading() {
        let markdown = "## Summary\nShort.\n\n## Make replies warmer\nDetails."
        let prefill = NewRequestPrefill(chatTitle: "Bulk update", answerMarkdown: markdown, conversationId: "c1")
        XCTAssertEqual(prefill.title, "Make replies warmer")
        XCTAssertEqual(prefill.description, NewRequestPrefill.requestDescription(markdown))
        XCTAssertEqual(prefill.conversationId, "c1")
    }

    func test_prefill_fallsBackToTheChatTitleThenTheFirstLine() {
        XCTAssertEqual(NewRequestPrefill(chatTitle: " Bulk update ", answerMarkdown: "Use bulk updates.", conversationId: nil).title,
                       "Bulk update")
        XCTAssertEqual(NewRequestPrefill(chatTitle: "Bulk update", answerMarkdown: answer, conversationId: nil).title, "Plan")
        XCTAssertEqual(NewRequestPrefill(chatTitle: "New Chat", answerMarkdown: "First line here\nMore.", conversationId: nil).title,
                       "First line here", "an untitled chat uses the answer's first line")
        XCTAssertEqual(NewRequestPrefill(chatTitle: "", answerMarkdown: String(repeating: "x", count: 200), conversationId: nil).title.count,
                       120)
    }

    func test_prefill_shortensALongAnswerAtALineBreak() {
        let long = (0..<200).map { "Line \($0) \(String(repeating: "x", count: 30))" }.joined(separator: "\n")
        let linked = NewRequestPrefill(chatTitle: "T", answerMarkdown: long, conversationId: "c1").description
        XCTAssertLessThan(linked.count, NewRequestPrefill.descriptionLimit + 80)
        XCTAssertNotNil(linked.range(of: #"Line \d+ x+\n\n\(Shortened\. The full answer is in the linked chat\.\)$"#,
                                     options: .regularExpression))
        let unlinked = NewRequestPrefill(chatTitle: "T", answerMarkdown: long, conversationId: nil).description
        XCTAssertTrue(unlinked.hasSuffix("\n\n(Shortened.)"))
        XCTAssertEqual(NewRequestPrefill(chatTitle: "T", answerMarkdown: "Short.", conversationId: nil).description, "Short.")
    }

    func test_prefill_neverEndsOnAnEmptyHeading() {
        let body = (0..<110).map { "Line \($0) \(String(repeating: "x", count: 30))" }.joined(separator: "\n")
        let markdown = "## Problem\n\(body)\n\n## Expected outcome\n\(String(repeating: "y", count: 60))\n"
            + String(repeating: "z", count: NewRequestPrefill.descriptionLimit)
        let description = NewRequestPrefill(chatTitle: "T", answerMarkdown: markdown, conversationId: "c1").description
        XCTAssertFalse(description.contains("Expected outcome:\n\n(Shortened"))
        XCTAssertTrue(description.hasSuffix("\n\n(Shortened. The full answer is in the linked chat.)"))
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
