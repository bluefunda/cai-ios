import Foundation

// MARK: - BFF Chat Service Implementation
// Uses HTTP/SSE endpoints from cai-bff for chat functionality

final class BFFChatService: ChatServiceProtocol {
    private(set) var isConnected: Bool = false
    private(set) var connectionStatus: ConnectionStatus = .disconnected

    private var credentials: ServiceCredentials?
    private var currentTask: Task<Void, Never>?

    // MARK: - Configuration
    struct Config {
        static let defaultBFFURL = AppConfig.bffBaseURL
        static let chatsPath = "/chats"  // POST /chats/{chat_id} for streaming
        static let requestTimeout: TimeInterval = 120
    }

    // MARK: - ChatServiceProtocol Implementation

    func connect(credentials: ServiceCredentials) async throws {
        self.credentials = credentials
        isConnected = true
        connectionStatus = .connected
    }

    func disconnect() async {
        currentTask?.cancel()
        currentTask = nil
        isConnected = false
        connectionStatus = .disconnected
    }

    func sendMessage(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        // Capture only Sendable values before crossing into the Task.
        // BFFChatService itself is non-Sendable, so self must not be captured.
        guard let credentials = credentials else {
            return AsyncThrowingStream { $0.finish(throwing: ChatServiceError.notConnected) }
        }
        let baseURL = credentials.bffBaseURL ?? Config.defaultBFFURL
        let chatsPath = Config.chatsPath
        let timeout = Config.requestTimeout

        return AsyncThrowingStream { continuation in
            let task = Task {
                guard let url = URL(string: "\(baseURL)\(chatsPath)/\(request.chatId)") else {
                    continuation.finish(throwing: ChatServiceError.connectionFailed("Invalid URL"))
                    return
                }

                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                urlRequest.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
                urlRequest.timeoutInterval = timeout

                var payload: [String: Any] = [
                    "type": "Human",
                    "model": request.model,
                    "prompt": request.prompt,
                    "thinkingMode": request.thinkingMode,
                    "modelExplicit": request.modelExplicit
                ]
                if let mcpName = request.mcpServerName { payload["mcp_server_name"] = mcpName }
                if let mcpURL  = request.mcpServerURL  { payload["mcp_server_url"]  = mcpURL  }
                if let fileUrl = request.fileUrl        { payload["fileUrl"]         = fileUrl  }
                if let agent   = request.agentName      { payload["agentName"]       = agent    }

                do {
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                do {
                    let session = URLSession(configuration: .default)
                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ChatServiceError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode == 401 {
                        continuation.finish(throwing: ChatServiceError.unauthorized)
                        return
                    }
                    guard httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: ChatServiceError.serverError("HTTP \(httpResponse.statusCode)"))
                        return
                    }

                    // Decode per-byte via SSEEventFramer (not per-byte UnicodeScalar,
                    // which is Latin-1 and corrupts any multi-byte character — em
                    // dash, arrows, accents, emoji…). The framer only treats a
                    // "\n\n" as a real event boundary once the bytes before it
                    // actually parse, so a blank line inside a chunk's own content
                    // can't be mistaken for the end of the stream.
                    var framer = SSEEventFramer()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        for event in framer.feed(byte: byte) {
                            continuation.yield(event)
                            if event.isTerminal { continuation.finish(); return }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self.currentTask = task
        }
    }

    func stopStreaming(chatId: String) async throws {
        currentTask?.cancel()

        guard let credentials = credentials else {
            throw ChatServiceError.notConnected
        }

        let baseURL = credentials.bffBaseURL ?? Config.defaultBFFURL
        // Endpoint: POST /chats/{chat_id}/stop
        guard let url = URL(string: "\(baseURL)\(Config.chatsPath)/\(chatId)/stop") else {
            throw ChatServiceError.connectionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = "{}".data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Ignore stop errors - the stream might have already ended
            return
        }
    }

    func generateTitle(chatId: String, prompt: String) async throws -> String {
        guard let credentials = credentials else {
            throw ChatServiceError.notConnected
        }

        let baseURL = credentials.bffBaseURL ?? Config.defaultBFFURL
        // Endpoint: POST /chats/{chat_id}/title
        guard let url = URL(string: "\(baseURL)\(Config.chatsPath)/\(chatId)/title") else {
            throw ChatServiceError.connectionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        // Backend expects "message" key (confirmed in hurl tests and Postman collection)
        let payload: [String: Any] = ["message": prompt]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        let rawBody = String(data: data, encoding: .utf8) ?? ""
        print("[CAI] Title API response: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0), body: \(rawBody)")

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Fallback
            return String(prompt.prefix(60)) + (prompt.count > 60 ? "..." : "")
        }

        // Try JSON response with various key names
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let title = json["generatedTitle"] as? String, !title.isEmpty {
                return title
            }
            if let title = json["title"] as? String, !title.isEmpty {
                return title
            }
            if let title = json["chatTitle"] as? String, !title.isEmpty {
                return title
            }
        }

        // Fallback
        return String(prompt.prefix(60)) + (prompt.count > 60 ? "..." : "")
    }

    func getChatContext(chatId: String) async throws -> [ChatMessage] {
        guard let credentials = credentials else {
            throw ChatServiceError.notConnected
        }

        let baseURL = credentials.bffBaseURL ?? Config.defaultBFFURL
        // Endpoint: GET /chats/{chat_id}/context
        guard let url = URL(string: "\(baseURL)\(Config.chatsPath)/\(chatId)/context") else {
            throw ChatServiceError.connectionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let context = json["chatContext"] as? [[String: Any]] else {
            return []
        }

        return context.compactMap { msg -> ChatMessage? in
            guard let role = msg["role"] as? String,
                  let content = msg["content"] as? String else {
                return nil
            }

            return ChatMessage(
                role: MessageRole(rawValue: role) ?? .user,
                content: content
            )
        }
    }

}
