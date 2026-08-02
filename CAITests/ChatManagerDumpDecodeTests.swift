import XCTest
@testable import CAI

// MARK: - ST22 Dump Decode Wiring Tests (bluefunda/cai-ios#182)
// Guards that requestPromptOverride reaches the outgoing ChatRequest while
// the conversation's own stored user message keeps the original pasted text.

@MainActor
final class ChatManagerDumpDecodeTests: XCTestCase {
    private func waitForStreamingToFinish(_ chatManager: ChatManager, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while chatManager.isStreaming && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(chatManager.isStreaming, "Timed out waiting for streaming to finish")
    }

    func test_requestPromptOverride_sentToBackend_originalTextShownInConversation() async throws {
        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        let rawDump = "Category ABAP programming error"
        let override = ST22PromptBuilder.buildPrompt(rawDump: rawDump)

        await chatManager.sendMessage(rawDump, requestPromptOverride: override)
        try await waitForStreamingToFinish(chatManager)

        XCTAssertEqual(mockService.lastRequest?.prompt, override)
        XCTAssertEqual(chatManager.currentConversation?.messages.first?.content, rawDump)
    }

    func test_noOverride_usesTextAsIsForRequest() async throws {
        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("Plain question")
        try await waitForStreamingToFinish(chatManager)

        XCTAssertEqual(mockService.lastRequest?.prompt, "Plain question")
    }
}
