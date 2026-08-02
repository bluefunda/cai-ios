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
        UserDefaults.standard.removeObject(forKey: "cai_persona_enabled")
        UserDefaults.standard.removeObject(forKey: BFFeatureFlags.Keys.personaWire)
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
        UserDefaults.standard.set(true, forKey: BFFeatureFlags.Keys.personaWire) // simulates backend being ready
        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        chatManager.persona = .fi
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("How does dunning work?")
        try await waitForStreamingToFinish(chatManager)

        XCTAssertEqual(mockService.lastRequest?.persona, Persona.fi.rawValue)
    }

    func test_switchingPersona_appliesToNextMessage_withoutRestart() async throws {
        UserDefaults.standard.set(true, forKey: BFFeatureFlags.Keys.personaWire) // simulates backend being ready
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

    // MARK: - Wire kill-switch (BFFeatureFlags.personaWireEnabled)
    // Off by default (2026-08-02): no backend support yet (cai-bff#110-112,
    // cai-llm-router#242-244, cai-mcp-go#180-182 unimplemented), and every
    // message failed with it on in the first live end-to-end test. Local UI
    // (toggle, chip, override, history metadata) stays fully functional.

    func test_personaWireDisabledByDefault_omitsPersonaFromRequest() async throws {
        UserDefaults.standard.removeObject(forKey: BFFeatureFlags.Keys.personaWire)
        XCTAssertFalse(BFFeatureFlags.personaWireEnabled)

        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        chatManager.persona = .fi
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("How does dunning work?")
        try await waitForStreamingToFinish(chatManager)

        XCTAssertNil(mockService.lastRequest?.persona, "wire must stay off until explicitly re-enabled")
    }

    func test_personaWireDisabled_localMetadataStillRecorded() async throws {
        UserDefaults.standard.removeObject(forKey: BFFeatureFlags.Keys.personaWire)

        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        chatManager.persona = .abap
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("Question")
        try await waitForStreamingToFinish(chatManager)

        XCTAssertNil(mockService.lastRequest?.persona, "still gated off the wire")
        let messages = chatManager.currentConversation?.messages ?? []
        XCTAssertEqual(
            messages.first(where: { $0.role == .user })?.persona, Persona.abap.rawValue,
            "local history/UI metadata keeps working even while the wire is gated off"
        )
    }

    // MARK: - Enable/disable toggle (bluefunda/cai-ios#203)

    func test_personaEnabled_defaultsToTrue() {
        UserDefaults.standard.removeObject(forKey: "cai_persona_enabled")
        let chatManager = ChatManager(service: MockChatService())
        XCTAssertTrue(chatManager.personaEnabled, "must default on so #177's existing behavior is unchanged")
    }

    func test_personaEnabled_persistsAcrossInstances() {
        let first = ChatManager(service: MockChatService())
        first.personaEnabled = false

        let second = ChatManager(service: MockChatService())
        XCTAssertFalse(second.personaEnabled)
    }

    func test_disabled_sendsNoPersonaField_evenWithADefaultAndOverrideSet() async throws {
        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        chatManager.persona = .fi
        chatManager.personaEnabled = false
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("Question", personaOverride: .abap)
        try await waitForStreamingToFinish(chatManager)

        XCTAssertNil(mockService.lastRequest?.persona, "disabled must omit persona entirely, not send a placeholder")
    }

    // MARK: - Per-message override (bluefunda/cai-ios#205/#206)

    func test_personaOverride_appliesOnlyToThatMessage() async throws {
        UserDefaults.standard.set(true, forKey: BFFeatureFlags.Keys.personaWire) // simulates backend being ready
        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        chatManager.persona = .basis
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("Overridden question", personaOverride: .leader)
        try await waitForStreamingToFinish(chatManager)
        XCTAssertEqual(mockService.lastRequest?.persona, Persona.leader.rawValue)

        await chatManager.sendMessage("Next question")
        try await waitForStreamingToFinish(chatManager)
        XCTAssertEqual(
            mockService.lastRequest?.persona, Persona.basis.rawValue,
            "an override must not carry over — the next message falls back to the global default"
        )
    }

    // MARK: - Per-message metadata (bluefunda/cai-ios#207)

    func test_sentMessage_andItsAnswer_bothCarryTheSamePersona() async throws {
        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("Question", personaOverride: .fiCA)
        try await waitForStreamingToFinish(chatManager)

        let messages = chatManager.currentConversation?.messages ?? []
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first(where: { $0.role == .user })?.persona, Persona.fiCA.rawValue)
        XCTAssertEqual(messages.first(where: { $0.role == .assistant })?.persona, Persona.fiCA.rawValue)
    }

    // MARK: - FI vs FI-CA distinct personas

    func test_fiAndFiCA_areDistinctPersonas() {
        XCTAssertNotEqual(Persona.fi, Persona.fiCA)
        XCTAssertEqual(Persona.fiCA.rawValue, "fi-ca")
    }
}
