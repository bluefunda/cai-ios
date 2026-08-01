import XCTest
@testable import CAI

// MARK: - Persona Selection Tests (bluefunda/cai-ios#177)
// Guards the persona field on outgoing chat requests: default value,
// persistence across ChatManager instances, and taking effect on the very
// next message without requiring a restart.

@MainActor
final class ChatManagerPersonaTests: XCTestCase {
    private func waitForStreamingToFinish(_ chatManager: ChatManager, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while chatManager.isStreaming && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(chatManager.isStreaming, "Timed out waiting for streaming to finish")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cai_persona")
        super.tearDown()
    }

    func test_defaultPersona_isGeneral() {
        UserDefaults.standard.removeObject(forKey: "cai_persona")
        let chatManager = ChatManager(service: MockChatService())
        XCTAssertEqual(chatManager.persona, .general)
    }

    func test_selectedPersona_persistsAcrossInstances() {
        let first = ChatManager(service: MockChatService())
        first.persona = .abap

        let second = ChatManager(service: MockChatService())
        XCTAssertEqual(second.persona, .abap)
    }

    func test_sendMessage_includesSelectedPersonaInRequest() async throws {
        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        chatManager.persona = .fi
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("How does dunning work?")
        try await waitForStreamingToFinish(chatManager)

        XCTAssertEqual(mockService.lastRequest?.persona, Persona.fi.rawValue)
    }

    func test_switchingPersona_appliesToNextMessage_withoutRestart() async throws {
        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        chatManager.persona = .basis
        await chatManager.sendMessage("First question")
        try await waitForStreamingToFinish(chatManager)
        XCTAssertEqual(mockService.lastRequest?.persona, Persona.basis.rawValue)

        chatManager.persona = .leader
        await chatManager.sendMessage("Second question")
        try await waitForStreamingToFinish(chatManager)
        XCTAssertEqual(mockService.lastRequest?.persona, Persona.leader.rawValue)
    }
}
