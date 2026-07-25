import XCTest
@testable import CAI

// MARK: - ChatManager File Persistence Tests

@MainActor
final class ChatManagerFileTests: XCTestCase {
    private class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
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

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    var mockService: MockChatService!
    var fileStore: LocalFileStore!
    var tempRoot: URL!
    var chatManager: ChatManager!

    override func setUp() async throws {
        mockService = MockChatService()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fileStore = LocalFileStore(rootDirectory: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func waitForStreamingToFinish(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while chatManager.isStreaming && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(chatManager.isStreaming, "Timed out waiting for streaming to finish")
    }

    /// Gives the fire-and-forget Task inside persistOutputFiles a moment to complete.
    private func waitForCondition(timeout: TimeInterval = 3, _ condition: @escaping () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func test_streamEnd_withMarkdownImage_persistsOutputFile() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!
            return (response, Data([0xFF, 0xD8]))
        }
        chatManager = ChatManager(service: mockService, fileStore: fileStore, urlSession: makeMockSession())

        let imageURL = "https://storage.example.com/chart.png"
        mockService.mockEvents = [
            .streamEnd(totalChunks: 1, fullContent: "Here's your chart: ![chart](\(imageURL))", stopped: false)
        ]

        chatManager.newConversation()
        let conversationId = chatManager.currentConversation!.id
        await chatManager.sendMessage("Make a chart")
        try await waitForStreamingToFinish()

        await waitForCondition {
            await self.chatManager.attachments(for: conversationId).count == 1
        }

        let files = await chatManager.attachments(for: conversationId)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.source, .llmOutput)
        XCTAssertEqual(files.first?.remoteURL, imageURL)
    }

    func test_streamEnd_withoutFileLinks_persistsNothing() async throws {
        chatManager = ChatManager(service: mockService, fileStore: fileStore, urlSession: makeMockSession())
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Just a plain answer.", stopped: false)]

        chatManager.newConversation()
        let conversationId = chatManager.currentConversation!.id
        await chatManager.sendMessage("Hello")
        try await waitForStreamingToFinish()

        // Give any (nonexistent) background task a moment, then assert nothing appeared.
        try await Task.sleep(nanoseconds: 200_000_000)
        let files = await chatManager.attachments(for: conversationId)
        XCTAssertTrue(files.isEmpty)
    }

    func test_saveLocalAttachment_andList() async throws {
        chatManager = ChatManager(service: mockService, fileStore: fileStore, urlSession: makeMockSession())
        let conversationId = chatManager.conversationIdForAttachment()

        let metadata = await chatManager.saveLocalAttachment(
            data: Data("hello".utf8), filename: "note.txt", mimeType: "text/plain", conversationId: conversationId
        )
        XCTAssertNotNil(metadata)

        let files = await chatManager.attachments(for: conversationId)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.source, .userUpload)
    }

    func test_deleteAttachment_removesIt() async throws {
        chatManager = ChatManager(service: mockService, fileStore: fileStore, urlSession: makeMockSession())
        let conversationId = chatManager.conversationIdForAttachment()
        let metadata = await chatManager.saveLocalAttachment(
            data: Data("hello".utf8), filename: "note.txt", mimeType: "text/plain", conversationId: conversationId
        )!

        await chatManager.deleteAttachment(metadata)

        let files = await chatManager.attachments(for: conversationId)
        XCTAssertTrue(files.isEmpty)
    }

    func test_conversationIdForAttachment_createsDraftWhenNoneActive() async throws {
        chatManager = ChatManager(service: mockService, fileStore: fileStore, urlSession: makeMockSession())
        XCTAssertNil(chatManager.currentConversation)

        let id = chatManager.conversationIdForAttachment()

        XCTAssertNotNil(chatManager.currentConversation)
        XCTAssertEqual(chatManager.currentConversation?.id, id)
    }

    func test_deleteConversation_deletesItsFiles() async throws {
        chatManager = ChatManager(service: mockService, fileStore: fileStore, urlSession: makeMockSession())
        mockService.mockEvents = [.streamEnd(totalChunks: 1, fullContent: "Hi!", stopped: false)]
        chatManager.newConversation()
        await chatManager.sendMessage("Hello")
        try await waitForStreamingToFinish()

        let conversation = chatManager.conversations[0]
        _ = await chatManager.saveLocalAttachment(
            data: Data("x".utf8), filename: "a.txt", mimeType: "text/plain", conversationId: conversation.id
        )
        var files = await chatManager.attachments(for: conversation.id)
        XCTAssertEqual(files.count, 1)

        chatManager.deleteConversation(conversation)

        await waitForCondition {
            await self.chatManager.attachments(for: conversation.id).isEmpty
        }
        files = await chatManager.attachments(for: conversation.id)
        XCTAssertTrue(files.isEmpty)
    }
}
