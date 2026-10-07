import Combine
import XCTest
@testable import CAI

// MARK: - Thinking ("Thought for Ns") Tests
//
// Covers the live thinking flow end to end at the ChatManager level:
//   - turns with no reasoning never get steps or a duration
//   - steps are upserted by stepId; only one is active at a time
//   - thinking ends at the FIRST answer token: steps finish, duration freezes
//   - the frozen duration counts thinking only (not answer streaming time)
//   - the duration is measured from the send — the same clock as the live
//     "Thinking… Ns" placeholder — not from the first visible step (the router
//     withholds reasoning shorter than 2s, and Claude's first summary lags)
//   - a late step after the answer started can't reopen thinking
//   - answer-less turns still close their steps at stream end
//   - a fetch can't wipe a reply that is still streaming (the "Thinking…"
//     placeholder vanishing bug)
// Plus the pure helpers ([MessageStep].finishAll, MessageStep.thinkingDuration).

@MainActor
final class ChatManagerThinkingTests: XCTestCase {

    // MARK: Helpers

    private func step(_ id: String, _ title: String, _ state: StepState = .active) -> ChatEvent {
        .status(StepEvent(stepId: id, title: title, detail: "\(title) — detail", state: state))
    }

    private let start = ChatEvent.streamStart(chatId: "chat", sessionId: "session")

    private func chunk(_ text: String) -> ChatEvent {
        .chunk(content: text, chunkId: 1, totalLength: text.count)
    }

    private func end(_ full: String) -> ChatEvent {
        .streamEnd(totalChunks: 1, fullContent: full, stopped: false)
    }

    /// Runs one send, recording every published state of the assistant reply.
    private func send(
        _ events: [ChatEvent],
        delaysNanos: [UInt64] = []
    ) async -> (final: ChatMessage?, timeline: [ChatMessage]) {
        let service = MockChatService()
        service.mockEvents = events
        service.mockEventDelaysNanos = delaysNanos
        let manager = ChatManager(service: service)

        var timeline: [ChatMessage] = []
        let cancellable = manager.$currentConversation.sink { conversation in
            if let last = conversation?.messages.last, last.role == .assistant {
                timeline.append(last)
            }
        }
        await manager.sendMessage("A farmer has 3 fields…")
        // sendMessage starts the stream in a background task and returns; wait for it to finish.
        let deadline = Date().addingTimeInterval(10)
        while manager.isStreaming, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        cancellable.cancel()

        let final = manager.currentConversation?.messages.last(where: { $0.role == .assistant })
        return (final, timeline)
    }

    // MARK: No reasoning

    func test_noSteps_turnHasNoThinkingCard() async {
        let (final, _) = await send([start, chunk("Hello!"), end("Hello!")])

        XCTAssertEqual(final?.content, "Hello!")
        XCTAssertNil(final?.steps, "a turn with no reasoning must not render a thinking card")
        XCTAssertNil(final?.thinkingDurationSeconds)
    }

    // MARK: Steps

    func test_steps_areUpsertedByStepId_notDuplicated() async {
        let (final, _) = await send([
            start,
            step("s1", "Setting up the equations"),
            step("s1", "Setting up the equations for A, B and C"),
            chunk("Answer"),
            end("Answer"),
        ])

        XCTAssertEqual(final?.steps?.count, 1, "a repeated stepId updates the row in place")
        XCTAssertEqual(final?.steps?.first?.title, "Setting up the equations for A, B and C")
    }

    func test_newActiveStep_deactivatesThePreviousOne() async {
        let (_, timeline) = await send([
            start,
            step("s1", "First"),
            step("s2", "Second"),
            chunk("Answer"),
            end("Answer"),
        ])

        let whileThinking = timeline.last(where: { ($0.steps?.count ?? 0) == 2 && $0.content.isEmpty })
        XCTAssertEqual(whileThinking?.steps?.filter(\.isActive).map(\.stepId), ["s2"],
                       "only the newest step reads as in progress")
    }

    // MARK: Thinking ends at the first answer token

    func test_firstAnswerChunk_finishesStepsAndFreezesDuration() async {
        let (_, timeline) = await send([start, step("s1", "Reasoning"), chunk("The"), chunk(" answer"), end("The answer")])

        guard let firstWithText = timeline.first(where: { !$0.content.isEmpty }) else {
            return XCTFail("expected the answer to stream")
        }
        XCTAssertNotNil(firstWithText.thinkingDurationSeconds,
                        "the card must lock to 'Thought for Ns' as soon as the answer starts")
        XCTAssertTrue(firstWithText.steps?.allSatisfy { !$0.isActive } ?? false,
                      "no step keeps a spinner once the answer has started")
    }

    func test_whileThinking_noDurationYet() async {
        let (_, timeline) = await send([start, step("s1", "Reasoning"), chunk("Answer"), end("Answer")])

        let thinking = timeline.first(where: { !($0.steps ?? []).isEmpty && $0.content.isEmpty })
        XCTAssertNotNil(thinking, "expected a published state while still thinking")
        XCTAssertNil(thinking?.thinkingDurationSeconds, "no 'Thought for Ns' while thinking is live")
        XCTAssertNotNil(thinking?.thinkingStartedAt, "the live timer needs the shared start time")
    }

    func test_duration_countsThinkingOnly_notAnswerStreaming() async {
        // Thinking is instant; the answer then streams for ~1.4s. Duration must stay 1s.
        let (final, _) = await send(
            [start, step("s1", "Reasoning"), chunk("Part one"), chunk(" part two"), end("Part one part two")],
            delaysNanos: [0, 0, 0, 1_400_000_000, 0]
        )

        XCTAssertEqual(final?.thinkingDurationSeconds, 1,
                       "answer streaming time must not be added to 'Thought for Ns'")
    }

    func test_duration_isMeasuredFromSend_notFirstVisibleStep() async {
        // The first step arrives late (withheld/lagging reasoning): ~1.6s after the send.
        let (final, _) = await send(
            [start, step("s1", "Reasoning"), chunk("Answer"), end("Answer")],
            delaysNanos: [0, 1_600_000_000, 0, 0]
        )

        XCTAssertEqual(final?.thinkingDurationSeconds, 2,
                       "duration must include the wait before the first visible step")
    }

    func test_thinkingClock_startsAtTheSend_sharedWithPlaceholder() async {
        let (_, timeline) = await send(
            [start, step("s1", "Reasoning"), chunk("Answer"), end("Answer")],
            delaysNanos: [0, 300_000_000, 0, 0]
        )

        guard let thinking = timeline.first(where: { !($0.steps ?? []).isEmpty }) else {
            return XCTFail("expected a published thinking state")
        }
        XCTAssertEqual(thinking.thinkingStartedAt, thinking.timestamp,
                       "the steps card must count from the send, like the 'Thinking… Ns' placeholder, so the count never jumps back")
    }

    func test_duration_isAtLeastOneSecond() async {
        let (final, _) = await send([start, step("s1", "Quick"), chunk("A"), end("A")])
        XCTAssertEqual(final?.thinkingDurationSeconds, 1)
    }

    // MARK: Late steps

    func test_lateStepAfterAnswerStarted_cannotReopenThinking() async {
        let (final, timeline) = await send([
            start,
            step("s1", "Reasoning"),
            chunk("Answer"),
            step("s2", "Late reasoning", .active),
            end("Answer"),
        ])

        let afterLateStep = timeline.first(where: { ($0.steps?.contains { $0.stepId == "s2" }) ?? false })
        XCTAssertNotNil(afterLateStep)
        XCTAssertTrue(afterLateStep?.steps?.allSatisfy { !$0.isActive } ?? false,
                      "a step arriving after the answer started must not show as in progress")
        XCTAssertNotNil(afterLateStep?.thinkingDurationSeconds, "the card stays locked")
        XCTAssertTrue(final?.steps?.allSatisfy { !$0.isActive } ?? false)
    }

    // MARK: Answer-less turn

    func test_stepsWithoutAnswerText_areClosedAtStreamEnd() async {
        let (final, _) = await send([start, step("s1", "Reasoning"), end("")])

        XCTAssertEqual(final?.steps?.count, 1)
        XCTAssertTrue(final?.steps?.allSatisfy { !$0.isActive } ?? false,
                      "steps must be finished even when no answer text ever arrived")
        XCTAssertNotNil(final?.thinkingDurationSeconds)
    }

    // MARK: Pure helpers

    func test_finishAll_marksEveryStepInactive() {
        var steps = [
            MessageStep(stepId: "a", title: "A", detail: "", isActive: true),
            MessageStep(stepId: "b", title: "B", detail: "", isActive: false),
        ]
        steps.finishAll()
        XCTAssertTrue(steps.allSatisfy { !$0.isActive })
    }

    func test_thinkingDuration_roundsAndHasAOneSecondFloor() {
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(MessageStep.thinkingDuration(since: t0, until: t0.addingTimeInterval(0.2)), 1)
        XCTAssertEqual(MessageStep.thinkingDuration(since: t0, until: t0.addingTimeInterval(2.4)), 2)
        XCTAssertEqual(MessageStep.thinkingDuration(since: t0, until: t0.addingTimeInterval(2.6)), 3)
    }

    // MARK: A fetch must not wipe a streaming reply

    private final class CountingURLProtocol: URLProtocol {
        static var messagesRequests = 0
        static var body = Data(#"{"chatHistory":[{"id":"u1","role":"Human","content":"Hi"}]}"#.utf8)

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if request.url?.path.hasSuffix("/messages") == true { Self.messagesRequests += 1 }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func managerWithStreamingTurn() -> (ChatManager, assistantId: String) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountingURLProtocol.self]
        CountingURLProtocol.messagesRequests = 0

        let manager = ChatManager(service: MockChatService())
        manager.apiService = BFFAPIService(
            baseURL: "https://example.com",
            tokenProvider: { "token" },
            session: URLSession(configuration: config)
        )
        let user = ChatMessage(id: "u1", role: .user, content: "Hi")
        let reply = ChatMessage(id: "a1", role: .assistant, content: "")
        let conversation = Conversation(id: "c1", title: "New Chat", messages: [user, reply], model: "auto", createdAt: Date())
        manager.conversations = [conversation]
        manager.currentConversation = conversation
        manager.isStreaming = true
        manager.streamingMessageId = reply.id
        return (manager, reply.id)
    }

    func test_loadMessages_doesNotFetchOrWipeWhileReplyIsStreaming() async {
        let (manager, assistantId) = managerWithStreamingTurn()

        await manager.loadMessages(for: "c1")

        XCTAssertEqual(CountingURLProtocol.messagesRequests, 0, "no fetch while a reply is streaming in")
        XCTAssertTrue(manager.currentConversation?.messages.contains { $0.id == assistantId } ?? false,
                      "the in-flight reply (and its 'Thinking…' placeholder) must survive")
    }

    func test_loadMessages_fetchesNormallyOnceStreamingEnded() async {
        let (manager, _) = managerWithStreamingTurn()
        manager.isStreaming = false
        manager.streamingMessageId = nil

        await manager.loadMessages(for: "c1")

        XCTAssertEqual(CountingURLProtocol.messagesRequests, 1, "history loads as usual when nothing is streaming")
    }

    // MARK: Inline steps (mid-answer, claude.ai-style)

    private func inlineStep(_ id: String, _ title: String, at offset: Int, _ state: StepState = .done) -> ChatEvent {
        .status(StepEvent(stepId: id, title: title, detail: "", state: state, contentOffset: offset, mood: "happy"))
    }

    func test_inlineStep_staysLiveAfterTheAnswerStarted_andKeepsItsPosition() async {
        let (final, timeline) = await send([
            start,
            step("s1", "Planning"),
            chunk("I'll fetch the page. "),
            inlineStep("t1", "Reading fao.org", at: 21, .active),
            inlineStep("t1", "Read fao.org", at: 21),
            chunk("Here are the points."),
            end("I'll fetch the page. Here are the points."),
        ])

        let whileReading = timeline.first(where: { $0.steps?.contains { $0.stepId == "t1" && $0.isActive } ?? false })
        XCTAssertNotNil(whileReading, "an inline step must show as running even though thinking is locked")
        let inline = final?.steps?.first(where: { $0.stepId == "t1" })
        XCTAssertEqual(inline?.contentOffset, 21)
        XCTAssertEqual(inline?.mood, "happy")
        XCTAssertEqual(final?.steps?.cardSteps.map(\.stepId), ["s1"], "the card only holds pre-answer steps")
        XCTAssertEqual(final?.steps?.inlineSteps.map(\.stepId), ["t1"])
    }

    func test_stepsDecodeContentOffsetAndMoodFromHistory() throws {
        let json = #"[{"stepId":"s1","title":"Planning"},{"stepId":"t1","title":"Read fao.org","mood":"happy","contentOffset":44}]"#
        let steps = try JSONDecoder().decode([MessageStep].self, from: Data(json.utf8))
        XCTAssertNil(steps[0].contentOffset)
        XCTAssertEqual(steps[1].contentOffset, 44)
        XCTAssertEqual(steps[1].mood, "happy")
        XCTAssertFalse(steps[1].isActive)
    }

    func test_toolTitlesSplitIntoLabelAndValue() {
        let search = MessageStep(stepId: "a", title: #"Searched the web for "MacBook Air M5""#, detail: "", isActive: false)
        XCTAssertEqual(search.toolLabelAndValue?.label, "Searched the web")
        XCTAssertEqual(search.toolLabelAndValue?.value, "MacBook Air M5")
        let read = MessageStep(stepId: "b", title: "Read fao.org", detail: "", isActive: false)
        XCTAssertEqual(read.toolLabelAndValue?.label, "Read")
        XCTAssertEqual(read.toolLabelAndValue?.value, "fao.org")
        let thought = MessageStep(stepId: "c", title: "Read the clue about Ben again", detail: "", isActive: false)
        XCTAssertNil(thought.toolLabelAndValue, "a reasoning sentence is not a tool step")
    }

    // MARK: A stopped reply survives a reload that beats its server-side save

    func test_loadMessages_keepsStoppedReplyWhenServerIsOneReplyBehind() async {
        let (manager, _) = managerWithStreamingTurn()
        manager.isStreaming = false
        manager.streamingMessageId = nil
        var conversation = manager.conversations[0]
        // the stopped partial reply
        conversation.messages[1] = ChatMessage(id: conversation.messages[1].id, role: .assistant, content: "Half an ans")
        manager.conversations = [conversation]
        manager.currentConversation = conversation

        await manager.loadMessages(for: "c1")   // server history: just the prompt

        let messages = manager.conversations.first?.messages ?? []
        XCTAssertEqual(messages.map(\.role), [.user, .assistant], "the stopped reply must not vanish")
        XCTAssertEqual(messages.last?.content, "Half an ans")
        XCTAssertFalse(manager.conversations.first?.messagesLoaded ?? true, "fetch again next open, once the save lands")
    }

    // MARK: Thought line shows a full sentence, never a two-word fragment

    func test_fullSentence_showsOnlyCompleteSentencesWhileThinking() {
        let forming = MessageStep(stepId: "s", title: "But this leaves",
                                  detail: "Testing Ben=5 gives a consistent arrangement.\nBut this leaves", isActive: true)
        XCTAssertEqual(forming.fullSentence, "Testing Ben=5 gives a consistent arrangement.",
                       "a sentence still being written is never shown")

        let finished = MessageStep(stepId: "s", title: "But this…",
                                   detail: "Testing Ben=5 works.\nBut this leaves the rabbit for Ela, which clue 6 forbids.", isActive: true)
        XCTAssertEqual(finished.fullSentence, "But this leaves the rabbit for Ela, which clue 6 forbids.")

        let nothingYet = MessageStep(stepId: "s", title: "Setting", detail: "Setting", isActive: true)
        XCTAssertEqual(nothingYet.fullSentence, "", "no complete sentence yet: the header shows Thinking…")

        let history = MessageStep(stepId: "s", title: "Planning the", detail: "Planning the", isActive: false)
        XCTAssertEqual(history.fullSentence, "Planning the", "a finished step always shows its text")
    }

    // MARK: Opening a chat doesn't flash the prompt twice

    func test_keepingOnScreenIds_reusesTheShownIdForTheSameMessage() {
        let manager = ChatManager(service: MockChatService())
        let shown = [ChatMessage(id: "local-1", role: .user, content: "Hi"),
                     ChatMessage(id: "local-2", role: .assistant, content: "Hello!")]
        let server = [ChatMessage(id: "srv-1", role: .user, content: "Hi"),
                      ChatMessage(id: "srv-2", role: .assistant, content: "Hello! (edited)")]

        let merged = manager.keepingOnScreenIds(server, onScreen: shown)

        XCTAssertEqual(merged[0].id, "local-1", "same position, role and text: the row must not be swapped")
        XCTAssertEqual(merged[1].id, "srv-2", "different text is a different message")
    }

    func test_loadMessages_secondConcurrentLoadOfTheSameChatIsSkipped() async {
        let (manager, _) = managerWithStreamingTurn()
        manager.isStreaming = false
        manager.streamingMessageId = nil
        manager.loadingConversationIds.insert("c1")   // a load already in flight

        await manager.loadMessages(for: "c1")

        XCTAssertEqual(CountingURLProtocol.messagesRequests, 0, "a concurrent load of the same chat must not fetch again")
    }
}
