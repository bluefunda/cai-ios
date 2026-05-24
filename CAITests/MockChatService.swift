import Foundation
@testable import CAI

// MARK: - Mock Chat Service for Unit Tests

final class MockChatService: ChatServiceProtocol {
    var isConnected: Bool = false
    var connectionStatus: ConnectionStatus = .disconnected

    var connectCalled = false
    var disconnectCalled = false
    var sendMessageCalled = false
    var stopStreamingCalled = false

    var mockEvents: [ChatEvent] = []
    var mockError: Error?
    var mockContext: [ChatMessage] = []
    var mockTitle = "Mock Title"

    func connect(credentials: ServiceCredentials) async throws {
        connectCalled = true
        isConnected = true
        connectionStatus = .connected
    }

    func disconnect() async {
        disconnectCalled = true
        isConnected = false
        connectionStatus = .disconnected
    }

    func sendMessage(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        sendMessageCalled = true
        let events = mockEvents
        let error = mockError

        return AsyncThrowingStream { continuation in
            Task {
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    func stopStreaming(chatId: String) async throws {
        stopStreamingCalled = true
    }

    func getChatContext(chatId: String) async throws -> [ChatMessage] {
        mockContext
    }

    func generateTitle(chatId: String, prompt: String) async throws -> String {
        mockTitle
    }
}
