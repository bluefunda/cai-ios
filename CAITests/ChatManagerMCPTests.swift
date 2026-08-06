import XCTest
@testable import CAI

// MARK: - Multi-MCP Wire Format & Per-Conversation Scoping Tests
// Covers bluefunda/cai-ios#171 (send the full enabledMCPServers list instead
// of collapsing to nil) and bluefunda/cai-ios#172 (scope enabledMCPServers
// per-conversation instead of one global set).

@MainActor
final class ChatManagerMCPTests: XCTestCase {

    private func makeServer(_ id: String, name: String? = nil, url: String = "http://example/mcp") -> MCPServer {
        MCPServer(id: id, name: name ?? id, url: url, description: nil)
    }

    /// sendMessage() kicks off streaming in a detached `Task` and returns as
    /// soon as it's scheduled — it does not await the request actually
    /// reaching the service. Poll for it instead of asserting immediately.
    private func waitForCondition(timeout: TimeInterval = 3, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - ChatRequest.toJSON() wire format

    func test_toJSON_includesMcpServersWhenMultipleSet() {
        let request = ChatRequest(
            chatId: "c1",
            prompt: "hi",
            model: "auto",
            mcpServers: [
                MCPServerRef(name: "abaper-mcp", url: "http://abaper-mcp:8015/sse"),
                MCPServerRef(name: "github-mcp", url: nil)
            ]
        )
        let json = request.toJSON(userId: "u1", realm: "individual")

        guard let servers = json["mcpServers"] as? [[String: Any]] else {
            return XCTFail("expected mcpServers array in JSON payload")
        }
        XCTAssertEqual(servers.count, 2)
        XCTAssertEqual(servers[0]["name"] as? String, "abaper-mcp")
        XCTAssertEqual(servers[0]["url"] as? String, "http://abaper-mcp:8015/sse")
        XCTAssertEqual(servers[1]["name"] as? String, "github-mcp")
        XCTAssertNil(servers[1]["url"], "url key should be omitted, not sent as null, when a ref has no URL")
    }

    func test_toJSON_omitsMcpServersWhenNil() {
        let request = ChatRequest(chatId: "c1", prompt: "hi", model: "auto", mcpServers: nil)
        let json = request.toJSON(userId: "u1", realm: "individual")
        XCTAssertNil(json["mcpServers"])
    }

    func test_toJSON_omitsMcpServersWhenEmpty() {
        let request = ChatRequest(chatId: "c1", prompt: "hi", model: "auto", mcpServers: [])
        let json = request.toJSON(userId: "u1", realm: "individual")
        XCTAssertNil(json["mcpServers"])
    }

    // MARK: - ChatManager.sendMessage — wire-format flip (#171)

    func test_sendMessage_singleServer_usesLegacyFieldsNotList() async {
        let mock = MockChatService()
        let chatManager = ChatManager(service: mock)
        let server = makeServer("abaper-mcp", url: "http://abaper-mcp:8015/sse")
        chatManager.availableMCPServers = [server]
        chatManager.enabledMCPServers = [server.id]

        await chatManager.sendMessage("hello")
        await waitForCondition { mock.sendMessageCalled }

        XCTAssertEqual(mock.lastRequest?.mcpServerName, server.name)
        XCTAssertEqual(mock.lastRequest?.mcpServerURL, server.url)
        XCTAssertNil(mock.lastRequest?.mcpServers, "a single enabled server must keep using the legacy singular fields")
    }

    func test_sendMessage_multipleServers_populatesMcpServersList() async {
        let mock = MockChatService()
        let chatManager = ChatManager(service: mock)
        let serverA = makeServer("abaper-mcp", url: "http://abaper-mcp:8015/sse")
        let serverB = makeServer("github-mcp", url: "http://github-mcp:8020/mcp")
        chatManager.availableMCPServers = [serverA, serverB]
        chatManager.enabledMCPServers = [serverA.id, serverB.id]

        await chatManager.sendMessage("hello")
        await waitForCondition { mock.sendMessageCalled }

        XCTAssertNil(mock.lastRequest?.mcpServerName, "the multi-select path must not also populate the legacy singular field")
        XCTAssertNil(mock.lastRequest?.mcpServerURL)
        let names = Set((mock.lastRequest?.mcpServers ?? []).map(\.name))
        XCTAssertEqual(names, [serverA.name, serverB.name])
    }

    func test_sendMessage_noServersEnabled_sendsNoMcpFields() async {
        let mock = MockChatService()
        let chatManager = ChatManager(service: mock)
        chatManager.availableMCPServers = [makeServer("abaper-mcp")]
        chatManager.enabledMCPServers = []

        await chatManager.sendMessage("hello")
        await waitForCondition { mock.sendMessageCalled }

        XCTAssertTrue(mock.sendMessageCalled)
        XCTAssertNil(mock.lastRequest?.mcpServerName)
        XCTAssertNil(mock.lastRequest?.mcpServerURL)
        XCTAssertNil(mock.lastRequest?.mcpServers)
    }

    // MARK: - Per-conversation scoping (#172)

    func test_switchingConversations_isolatesEnabledMCPServers() {
        let chatManager = ChatManager(service: MockChatService())
        let serverA = makeServer("abaper-mcp")
        let serverB = makeServer("github-mcp")
        chatManager.availableMCPServers = [serverA, serverB]

        let conversationA = Conversation(id: "conv-a", title: "A", messages: [], model: "auto", createdAt: Date())
        let conversationB = Conversation(id: "conv-b", title: "B", messages: [], model: "auto", createdAt: Date())

        chatManager.currentConversation = conversationA
        chatManager.enabledMCPServers = [serverA.id]

        // Switching to a never-seen conversation must default to no tools,
        // not inherit conversation A's selection.
        chatManager.currentConversation = conversationB
        XCTAssertTrue(chatManager.enabledMCPServers.isEmpty)

        chatManager.enabledMCPServers = [serverB.id]

        // Switching back to A must restore exactly what A had, unaffected by B.
        chatManager.currentConversation = conversationA
        XCTAssertEqual(chatManager.enabledMCPServers, [serverA.id])

        // And B must still have its own selection intact.
        chatManager.currentConversation = conversationB
        XCTAssertEqual(chatManager.enabledMCPServers, [serverB.id])
    }

    func test_inPlaceConversationUpdate_doesNotResetEnabledMCPServers() {
        let chatManager = ChatManager(service: MockChatService())
        let server = makeServer("abaper-mcp")
        chatManager.availableMCPServers = [server]

        var conversation = Conversation(id: "conv-a", title: "A", messages: [], model: "auto", createdAt: Date())
        chatManager.currentConversation = conversation
        chatManager.enabledMCPServers = [server.id]

        // Same id, updated content (e.g. loadMessages replacing the struct
        // with a fresher copy) — must NOT be treated as a conversation switch.
        conversation.title = "A (renamed)"
        chatManager.currentConversation = conversation

        XCTAssertEqual(chatManager.enabledMCPServers, [server.id])
    }

    func test_disconnect_clearsPerConversationMCPState() async {
        let chatManager = ChatManager(service: MockChatService())
        let server = makeServer("abaper-mcp")
        chatManager.availableMCPServers = [server]

        let conversationA = Conversation(id: "conv-a", title: "A", messages: [], model: "auto", createdAt: Date())
        chatManager.currentConversation = conversationA
        chatManager.enabledMCPServers = [server.id]

        await chatManager.disconnect()

        chatManager.currentConversation = conversationA
        XCTAssertTrue(chatManager.enabledMCPServers.isEmpty, "per-conversation tool state must not survive disconnect/logout")
    }
}
