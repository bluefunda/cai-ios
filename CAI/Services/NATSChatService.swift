import Foundation

// MARK: - NATS Chat Service Implementation
// This implementation uses NATS WebSocket for real-time chat
// Can be swapped with BFFChatService after A/B testing

final class NATSChatService: ChatServiceProtocol {
    private(set) var isConnected: Bool = false
    private(set) var connectionStatus: ConnectionStatus = .disconnected

    private var natsClient: NATSWebSocketClient?
    private var credentials: ServiceCredentials?
    private var subdomain: String = "ai2"  // Use ai2 for cai-llm-router testing

    // MARK: - Configuration
    struct Config {
        static let defaultNATSURL = "wss://connect.ngs.global"
        static let requestTimeout: TimeInterval = 120
        static let reconnectDelay: TimeInterval = 2
        static let maxReconnectAttempts = 5
    }

    init(subdomain: String = "ai2") {
        self.subdomain = subdomain
    }

    // MARK: - ChatServiceProtocol Implementation

    func connect(credentials: ServiceCredentials) async throws {
        self.credentials = credentials
        connectionStatus = .connecting

        let natsURL = credentials.natsURL ?? Config.defaultNATSURL

        do {
            natsClient = NATSWebSocketClient(
                url: natsURL,
                credentials: credentials.natsCredentials
            )

            try await natsClient?.connect()

            isConnected = true
            connectionStatus = .connected
        } catch {
            isConnected = false
            connectionStatus = .error(error.localizedDescription)
            throw ChatServiceError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() async {
        await natsClient?.disconnect()
        isConnected = false
        connectionStatus = .disconnected
    }

    func sendMessage(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        guard let credentials = credentials, let client = natsClient else {
            return AsyncThrowingStream { $0.finish(throwing: ChatServiceError.notConnected) }
        }

        let subject = "\(subdomain).\(credentials.realm).\(credentials.userId).chat.\(request.chatId)"
        let replySubject = "\(subject).response"
        let payload = request.toJSON(userId: credentials.userId, realm: credentials.realm)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let responseStream = try await client.subscribe(subject: replySubject)

                    try await client.publish(
                        subject: subject,
                        payload: payload,
                        replyTo: replySubject
                    )

                    for try await message in responseStream {
                        if let event = NATSChatService.parseNATSMessage(message) {
                            continuation.yield(event)
                            if event.isTerminal { break }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func stopStreaming(chatId: String) async throws {
        guard let credentials = credentials, let client = natsClient else {
            throw ChatServiceError.notConnected
        }

        let stopSubject = buildStopSubject(
            realm: credentials.realm,
            userId: credentials.userId,
            chatId: chatId
        )

        try await client.publish(
            subject: stopSubject,
            payload: ["reason": "user_requested"],
            replyTo: nil
        )
    }

    func generateTitle(chatId: String, prompt: String) async throws -> String {
        // NATS doesn't have a title endpoint - fallback to truncated prompt
        return String(prompt.prefix(50)) + (prompt.count > 50 ? "..." : "")
    }

    func getChatContext(chatId: String) async throws -> [ChatMessage] {
        guard let credentials = credentials, let client = natsClient else {
            throw ChatServiceError.notConnected
        }

        let querySubject = buildContextQuerySubject(
            realm: credentials.realm,
            userId: credentials.userId,
            chatId: chatId
        )

        let response = try await client.request(
            subject: querySubject,
            payload: ["chat_id": chatId],
            timeout: 30
        )

        return parseContextResponse(response)
    }

    // MARK: - Subject Builders

    private func buildChatSubject(realm: String, userId: String, chatId: String) -> String {
        "\(subdomain).\(realm).\(userId).chat.\(chatId)"
    }

    private func buildStopSubject(realm: String, userId: String, chatId: String) -> String {
        "\(subdomain).\(realm).\(userId).chat.\(chatId).stop"
    }

    private func buildContextQuerySubject(realm: String, userId: String, chatId: String) -> String {
        "\(subdomain).\(realm).\(userId).query.getChatContext.\(chatId)"
    }

    // MARK: - Message Parsing

    private static func parseNATSMessage(_ data: Data) -> ChatEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let type = json["type"] as? String else {
            // Could be JetStream ack - ignore
            if json["stream"] != nil {
                return nil
            }
            return nil
        }

        switch type {
        case "stream_start":
            let chatId = json["chat_id"] as? String ?? ""
            let sessionId = json["session_id"] as? String ?? ""
            return .streamStart(chatId: chatId, sessionId: sessionId)

        case "stream_chunk":
            let content = json["content"] as? String ?? ""
            let chunkId = json["chunk_id"] as? Int ?? 0
            let totalLength = json["total_content_length"] as? Int ?? 0
            return .chunk(content: content, chunkId: chunkId, totalLength: totalLength)

        case "stream_end":
            let totalChunks = json["total_chunks"] as? Int ?? 0
            let fullContent = json["full_content"] as? String ?? ""
            let stopped = json["stopped"] as? Bool ?? false
            return .streamEnd(totalChunks: totalChunks, fullContent: fullContent, stopped: stopped)

        case "stream_heartbeat":
            let sessionId = json["session_id"] as? String ?? ""
            let chunks = json["chunks"] as? Int ?? 0
            let contentLength = json["content_length"] as? Int ?? 0
            return .heartbeat(sessionId: sessionId, chunks: chunks, contentLength: contentLength)

        case "stream_error", "error":
            let message = json["message"] as? String ?? json["error"] as? String ?? "Unknown error"
            let details = json["details"] as? String
            return .error(message: message, details: details)

        default:
            return nil
        }
    }

    private func parseContextResponse(_ data: Data) -> [ChatMessage] {
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

// MARK: - NATS WebSocket Client
// Handles low-level NATS protocol over WebSocket

final class NATSWebSocketClient: @unchecked Sendable {
    private var webSocket: URLSessionWebSocketTask?
    private let url: String
    private let credentials: String?
    private var subscriptions: [String: AsyncStream<Data>.Continuation] = [:]
    private var pendingRequests: [String: CheckedContinuation<Data, Error>] = [:]
    private var isRunning = false

    init(url: String, credentials: String?) {
        self.url = url
        self.credentials = credentials
    }

    func connect() async throws {
        guard let wsURL = URL(string: url) else {
            throw ChatServiceError.connectionFailed("Invalid URL")
        }

        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: wsURL)
        webSocket?.resume()

        // Send CONNECT command
        try await sendConnect()

        // Start receiving messages
        isRunning = true
        Task {
            await receiveLoop()
        }
    }

    func disconnect() async {
        isRunning = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
    }

    func subscribe(subject: String) async throws -> AsyncStream<Data> {
        let sid = UUID().uuidString

        return AsyncStream { continuation in
            subscriptions[sid] = continuation

            Task {
                do {
                    try await send("SUB \(subject) \(sid)\r\n")
                } catch {
                    continuation.finish()
                }
            }

            continuation.onTermination = { [weak self] _ in
                self?.subscriptions.removeValue(forKey: sid)
                Task {
                    try? await self?.send("UNSUB \(sid)\r\n")
                }
            }
        }
    }

    func publish(subject: String, payload: [String: Any], replyTo: String?) async throws {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let payloadStr = String(data: jsonData, encoding: .utf8) ?? "{}"

        var cmd: String
        if let reply = replyTo {
            cmd = "PUB \(subject) \(reply) \(jsonData.count)\r\n\(payloadStr)\r\n"
        } else {
            cmd = "PUB \(subject) \(jsonData.count)\r\n\(payloadStr)\r\n"
        }

        try await send(cmd)
    }

    func request(subject: String, payload: [String: Any], timeout: TimeInterval) async throws -> Data {
        let inbox = "_INBOX.\(UUID().uuidString)"

        // Subscribe to inbox
        let stream = try await subscribe(subject: inbox)

        // Publish with reply
        try await publish(subject: subject, payload: payload, replyTo: inbox)

        // Wait for response with timeout
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                for await data in stream {
                    return data
                }
                throw ChatServiceError.invalidResponse
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ChatServiceError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Private

    private func sendConnect() async throws {
        var connectOpts: [String: Any] = [
            "verbose": false,
            "pedantic": false,
            "protocol": 1,
            "echo": true
        ]

        if let creds = credentials {
            // Parse NKey credentials if provided
            connectOpts["nkey"] = parseNKey(from: creds)
        }

        let jsonData = try JSONSerialization.data(withJSONObject: connectOpts)
        let jsonStr = String(data: jsonData, encoding: .utf8) ?? "{}"
        try await send("CONNECT \(jsonStr)\r\n")
    }

    private func send(_ message: String) async throws {
        guard let webSocket = webSocket else {
            throw ChatServiceError.notConnected
        }

        try await webSocket.send(.string(message))
    }

    private func receiveLoop() async {
        while isRunning, let webSocket = webSocket {
            do {
                let message = try await webSocket.receive()
                switch message {
                case .string(let text):
                    processMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        processMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if isRunning {
                    // Connection error - could trigger reconnect here
                    break
                }
            }
        }
    }

    private func processMessage(_ text: String) {
        let lines = text.components(separatedBy: "\r\n")

        for line in lines {
            if line.hasPrefix("MSG ") {
                // Parse MSG: MSG <subject> <sid> [reply-to] <#bytes>
                let parts = line.components(separatedBy: " ")
                if parts.count >= 4 {
                    let sid = parts[2]
                    // Find payload (next line or inline)
                    if let payloadIndex = lines.firstIndex(where: { $0 == line }),
                       payloadIndex + 1 < lines.count {
                        let payload = lines[payloadIndex + 1]
                        if let data = payload.data(using: .utf8),
                           let continuation = subscriptions[sid] {
                            continuation.yield(data)
                        }
                    }
                }
            } else if line.hasPrefix("PING") {
                Task {
                    try? await send("PONG\r\n")
                }
            } else if line.hasPrefix("+OK") {
                // Success acknowledgment
            } else if line.hasPrefix("-ERR") {
                // Error from server
                print("NATS Error: \(line)")
            }
        }
    }

    private func parseNKey(from credentials: String) -> String? {
        // Parse NKey from credentials file format
        // This is a simplified version - full implementation would parse .creds file
        let lines = credentials.components(separatedBy: "\n")
        for line in lines {
            if line.contains("-----BEGIN USER NKEY SEED-----") {
                if let nextIndex = lines.firstIndex(of: line).map({ $0 + 1 }),
                   nextIndex < lines.count {
                    return lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }
}
