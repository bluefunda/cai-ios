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
        static let defaultBFFURL = "https://api.bluefunda.com/ai"
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
                    "prompt": request.prompt
                ]
                if let mcpName = request.mcpServerName { payload["mcp_server_name"] = mcpName }
                if let mcpURL  = request.mcpServerURL  { payload["mcp_server_url"]  = mcpURL  }

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
                        continuation.finish(throwing: ChatServiceError.serverError("Session expired. Please sign in again."))
                        return
                    }
                    guard httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: ChatServiceError.serverError("HTTP \(httpResponse.statusCode)"))
                        return
                    }

                    var buffer = ""
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        buffer.append(Character(UnicodeScalar(byte)))
                        while let range = buffer.range(of: "\n\n") {
                            let eventText = String(buffer[..<range.lowerBound])
                            buffer = String(buffer[range.upperBound...])
                            if let event = BFFChatService.parseSSEEvent(eventText) {
                                continuation.yield(event)
                                if event.isTerminal { continuation.finish(); return }
                            }
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

    // MARK: - SSE Parsing

    private static func parseSSEEvent(_ eventText: String) -> ChatEvent? {
        var eventData: String?

        let lines = eventText.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data:") {
                let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if eventData == nil {
                    eventData = data
                } else {
                    eventData! += "\n" + data
                }
            }
        }

        guard let data = eventData,
              !data.isEmpty,
              let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        let type = json["type"] as? String ?? ""

        switch type {
        case "stream_start":
            let chatId = json["chat_id"] as? String ?? json["chatId"] as? String ?? ""
            let sessionId = json["session_id"] as? String ?? json["sessionId"] as? String ?? ""
            return .streamStart(chatId: chatId, sessionId: sessionId)

        case "stream_chunk":
            let content = json["content"] as? String ?? ""
            let chunkId = json["chunk_id"] as? Int ?? json["chunkId"] as? Int ?? 0
            let totalLength = json["total_content_length"] as? Int ?? json["totalContentLength"] as? Int ?? 0
            return .chunk(content: content, chunkId: chunkId, totalLength: totalLength)

        case "stream_end":
            let totalChunks = json["total_chunks"] as? Int ?? json["totalChunks"] as? Int ?? 0
            let fullContent = json["full_content"] as? String ?? json["fullContent"] as? String ?? ""
            let stopped = json["stopped"] as? Bool ?? false
            return .streamEnd(totalChunks: totalChunks, fullContent: fullContent, stopped: stopped)

        case "stream_heartbeat":
            let sessionId = json["session_id"] as? String ?? json["sessionId"] as? String ?? ""
            let chunks = json["chunks"] as? Int ?? 0
            let contentLength = json["content_length"] as? Int ?? json["contentLength"] as? Int ?? 0
            return .heartbeat(sessionId: sessionId, chunks: chunks, contentLength: contentLength)

        case "stream_error", "error":
            let message = json["message"] as? String ?? json["error"] as? String ?? "Unknown error"
            let details = json["details"] as? String
            return .error(message: message, details: details)

        default:
            // Try to parse as chunk if content exists
            if let content = json["content"] as? String, !content.isEmpty {
                return .chunk(content: content, chunkId: 0, totalLength: 0)
            }
            return nil
        }
    }
}
