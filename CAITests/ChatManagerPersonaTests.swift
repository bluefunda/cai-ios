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
        UserDefaults.standard.set(true, forKey: BFFeatureFlags.Keys.personaWire) // explicit override, same as the default
        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        chatManager.persona = .fi
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("How does dunning work?")
        try await waitForStreamingToFinish(chatManager)

        XCTAssertEqual(mockService.lastRequest?.persona, Persona.fi.rawValue)
    }

    func test_switchingPersona_appliesToNextMessage_withoutRestart() async throws {
        UserDefaults.standard.set(true, forKey: BFFeatureFlags.Keys.personaWire) // explicit override, same as the default
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

    // Guards bluefunda/cai-bff#110: cai-bff's persona allowlist has no
    // "general" entry (it recognizes "none"/empty for "no persona lens").
    // Sending the literal string "general" would get normalized away
    // server-side too, but the client should never rely on that — it must
    // omit persona entirely for .general, exactly like the feature-disabled
    // case, even with the wire switch on.
    func test_generalPersona_omittedFromRequest_evenWithWireEnabled() async throws {
        UserDefaults.standard.set(true, forKey: BFFeatureFlags.Keys.personaWire)
        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        chatManager.persona = .general
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("Hi")
        try await waitForStreamingToFinish(chatManager)

        XCTAssertNil(mockService.lastRequest?.persona, "general has no wire representation — must not send the literal string \"general\"")
    }

    // MARK: - Wire kill-switch (BFFeatureFlags.personaWireEnabled)
    // On by default (2026-08-03): backend support shipped and confirmed
    // working end-to-end in a live device test (cai-bff#110-112,
    // cai-llm-router#242-244, cai-mcp-go#180-182). The UserDefaults override
    // remains as an emergency kill-switch if a regression turns up.

    func test_personaWireEnabledByDefault_includesPersonaInRequest() async throws {
        UserDefaults.standard.removeObject(forKey: BFFeatureFlags.Keys.personaWire)
        XCTAssertTrue(BFFeatureFlags.personaWireEnabled)

        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        chatManager.persona = .fi
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("How does dunning work?")
        try await waitForStreamingToFinish(chatManager)

        XCTAssertEqual(mockService.lastRequest?.persona, Persona.fi.rawValue, "wire is on by default")
    }

    func test_personaWireKillSwitched_omitsPersonaFromRequestButKeepsLocalMetadata() async throws {
        UserDefaults.standard.set(false, forKey: BFFeatureFlags.Keys.personaWire)

        let mockService = MockChatService()
        let chatManager = ChatManager(service: mockService)
        chatManager.persona = .abap
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Answer", stopped: false)]

        await chatManager.sendMessage("Question")
        try await waitForStreamingToFinish(chatManager)

        XCTAssertNil(mockService.lastRequest?.persona, "kill-switch must still be able to gate the wire off")
        let messages = chatManager.currentConversation?.messages ?? []
        XCTAssertEqual(
            messages.first(where: { $0.role == .user })?.persona, Persona.abap.rawValue,
            "local history/UI metadata keeps working even while the wire is killed"
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
        UserDefaults.standard.set(true, forKey: BFFeatureFlags.Keys.personaWire) // explicit override, same as the default
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
