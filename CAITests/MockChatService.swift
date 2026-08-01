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
    /// The most recent request passed to sendMessage, for assertions on the
    /// outgoing wire format (e.g. mcpServers population).
    var lastRequest: ChatRequest?

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
        lastRequest = request
        let events = mockEvents
        let error = mockError

        return AsyncThrowingStream { continuation in
            let innerTask = Task {
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                for event in events {
                    continuation.yield(event)
                }
                // With no events the test wants to simulate an open stream that
                // stays alive until stopStreaming / cancellation arrives.
                if events.isEmpty {
                    do {
                        try await Task.sleep(nanoseconds: 30_000_000_000) // 30 s
                    } catch {
                        // Cancelled by stopStreaming or task cancellation — expected.
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in innerTask.cancel() }
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
