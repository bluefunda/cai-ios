import XCTest
@testable import CAI

// MARK: - Stuck Chat Title Retry Tests
// Guards the fix for chats permanently stuck on cai-mcp-go's DefaultChatTitle
// ("New Chat") after the one-shot, fire-and-forget title-generation call
// fails once (network blip, LLM timeout, expired token) -- nothing else ever
// retries it server-side, so loadChats() must self-heal on the client.

@MainActor
final class ChatManagerTitleTests: XCTestCase {
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

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func waitForCondition(timeout: TimeInterval = 3, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func test_loadChats_retriesStuckTitle_andLeavesNormalTitlesAlone() async {
        let chatListJSON = """
        {
          "chats": [
            {"chatId": "stuck-1", "chatTitle": "New Chat", "firstPrompt": "hello world"},
            {"chatId": "fine-1", "chatTitle": "A real title", "firstPrompt": "something else"}
          ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/chats/stuck-1/title") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"title":"Generated Title"}"#.utf8))
            }
            if url.hasSuffix("/chats") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, chatListJSON)
            }
            throw URLError(.badURL)
        }

        let chatManager = ChatManager(service: MockChatService())
        chatManager.apiService = BFFAPIService(
            baseURL: "https://example.com",
            tokenProvider: { "test-token" },
            session: makeMockSession()
        )

        await chatManager.loadChats()
        await waitForCondition {
            chatManager.conversations.first(where: { $0.id == "stuck-1" })?.title == "Generated Title"
        }

        XCTAssertEqual(chatManager.conversations.first(where: { $0.id == "stuck-1" })?.title, "Generated Title")
        XCTAssertEqual(chatManager.conversations.first(where: { $0.id == "fine-1" })?.title, "A real title")
    }

    func test_loadChats_doesNotRetryWhenFirstMessageIsMissing() async {
        let chatListJSON = """
        {"chats": [{"chatId": "stuck-no-prompt", "chatTitle": "New Chat"}]}
        """.data(using: .utf8)!

        var titleCallMade = false
        MockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/title") {
                titleCallMade = true
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, chatListJSON)
        }

        let chatManager = ChatManager(service: MockChatService())
        chatManager.apiService = BFFAPIService(
            baseURL: "https://example.com",
            tokenProvider: { "test-token" },
            session: makeMockSession()
        )

        await chatManager.loadChats()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(titleCallMade, "should not attempt to regenerate a title with no prompt to work from")
        XCTAssertEqual(chatManager.conversations.first(where: { $0.id == "stuck-no-prompt" })?.title, "New Chat")
    }
}
