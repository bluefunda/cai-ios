import Foundation

// MARK: - Chat Service Protocol
// This abstraction allows swapping between NATS and BFF implementations
// After A/B testing cai-llm-router, implement BFFChatService

protocol ChatServiceProtocol {
    /// Connect to the chat service
    func connect(credentials: ServiceCredentials) async throws

    /// Disconnect from the chat service
    func disconnect() async

    /// Send a chat message and receive streaming response
    func sendMessage(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error>

    /// Stop the current streaming response
    func stopStreaming(chatId: String) async throws

    /// Get chat history/context for a conversation
    func getChatContext(chatId: String) async throws -> [ChatMessage]

    /// Generate a title for a chat based on the prompt
    func generateTitle(chatId: String, prompt: String) async throws -> String

    /// Connection status
    var isConnected: Bool { get }
    var connectionStatus: ConnectionStatus { get }
}

// MARK: - Service Credentials
struct ServiceCredentials {
    let userId: String
    let realm: String
    let accessToken: String

    // NATS-specific (used by NATSChatService)
    let natsURL: String?
    let natsCredentials: String?

    // BFF-specific (used by BFFChatService - future)
    let bffBaseURL: String?

    init(
        userId: String,
        realm: String,
        accessToken: String,
        natsURL: String? = nil,
        natsCredentials: String? = nil,
        bffBaseURL: String? = nil
    ) {
        self.userId = userId
        self.realm = realm
        self.accessToken = accessToken
        self.natsURL = natsURL
        self.natsCredentials = natsCredentials
        self.bffBaseURL = bffBaseURL
    }
}

// MARK: - Connection Status
enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(String)

    var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Chat Request
struct ChatRequest {
    let chatId: String
    let prompt: String
    let model: String
    let isNewChat: Bool
    let mcpServerName: String?
    let mcpServerURL: String?
    let messages: [ChatMessage]?
    /// Reasoning effort: "auto", "quick", or "deep".
    let thinkingMode: String
    /// True when the user explicitly picked a model; the backend then uses
    /// `model` and ignores `thinkingMode`.
    let modelExplicit: Bool
    /// Storage URL of an uploaded file attachment; passed as `fileUrl` to the backend.
    let fileUrl: String?
    /// Explicit agent name for routing (e.g. "abaper"). When set, cai-llm-router routes
    /// to the named agent rather than the default MCP agent.
    let agentName: String?
    /// The user's selected SAP persona (bluefunda/cai-ios#177), e.g. "abap" or
    /// "fi". Additive context for response tuning — independent of `agentName`,
    /// which is reserved for actual backend agent routing.
    let persona: String

    init(
        chatId: String,
        prompt: String,
        model: String,
        isNewChat: Bool = true,
        mcpServerName: String? = nil,
        mcpServerURL: String? = nil,
        messages: [ChatMessage]? = nil,
        thinkingMode: String = "auto",
        modelExplicit: Bool = false,
        fileUrl: String? = nil,
        agentName: String? = nil,
        persona: String = Persona.general.rawValue
    ) {
        self.chatId = chatId
        self.prompt = prompt
        self.model = model
        self.isNewChat = isNewChat
        self.mcpServerName = mcpServerName
        self.mcpServerURL = mcpServerURL
        self.messages = messages
        self.thinkingMode = thinkingMode
        self.modelExplicit = modelExplicit
        self.fileUrl = fileUrl
        self.agentName = agentName
        self.persona = persona
    }

    /// Convert to JSON payload for NATS/BFF
    func toJSON(userId: String, realm: String) -> [String: Any] {
        var json: [String: Any] = [
            "type": "Human",
            "model": model,
            "prompt": prompt,
            "isNewChat": isNewChat,
            "thinkingMode": thinkingMode,
            "modelExplicit": modelExplicit,
            "persona": persona
        ]

        if let mcpName = mcpServerName { json["mcp_server_name"] = mcpName }
        if let mcpURL  = mcpServerURL  { json["mcp_server_url"]  = mcpURL  }
        if let agent   = agentName     { json["agentName"]        = agent   }

        return json
    }
}

// MARK: - Chat Event (Streaming Response)
enum ChatEvent {
    case streamStart(chatId: String, sessionId: String)
    case chunk(content: String, chunkId: Int, totalLength: Int)
    case streamEnd(totalChunks: Int, fullContent: String, stopped: Bool)
    case heartbeat(sessionId: String, chunks: Int, contentLength: Int)
    case error(message: String, details: String?)
    case rateLimited(period: String, resetLabel: String)

    var isTerminal: Bool {
        switch self {
        case .streamEnd, .error, .rateLimited:
            return true
        default:
            return false
        }
    }
}

// MARK: - Chat Message
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    /// Durable reference to a user-attached file, relayed by cai-bff from history
    /// (also set locally the moment an attachment upload succeeds).
    var fileUrl: String? = nil
    /// Structured reference(s) for LLM-generated files, relayed by cai-bff from history.
    var fileMetadata: [MessageFileMetadata]? = nil

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        fileUrl: String? = nil,
        fileMetadata: [MessageFileMetadata]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.fileUrl = fileUrl
        self.fileMetadata = fileMetadata
    }

}

/// App-level mirror of `FileMetadataDTO` — the structured reference for an
/// LLM-generated file attached to a chat message.
struct MessageFileMetadata: Codable, Equatable, Hashable {
    let originalURL: String?
    let s3Path: String?
    let downloadURL: String?
    let fileName: String?
    let fileSize: Int64?
    let source: String?
}

extension MessageFileMetadata {
    init(from dto: FileMetadataDTO) {
        self.originalURL = dto.originalURL
        self.s3Path = dto.s3Path
        self.downloadURL = dto.downloadURL
        self.fileName = dto.fileName
        self.fileSize = dto.fileSize
        self.source = dto.source
    }
}

extension ChatMessage {
    init?(from persisted: PersistedMessage) {
        guard let role = MessageRole(rawValue: persisted.roleRaw) else { return nil }
        self.id = persisted.id
        self.role = role
        self.content = persisted.content
        self.timestamp = persisted.timestamp
    }
}

enum MessageRole: String, Codable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"

    var displayName: String {
        switch self {
        case .user: return "You"
        case .assistant: return "AI"
        case .system: return "System"
        }
    }
}

// MARK: - Chat Service Errors
enum ChatServiceError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case timeout
    case invalidResponse
    case serverError(String)
    /// The server rejected the request auth (HTTP 401). Callers should trigger
    /// re-authentication rather than showing a generic error.
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to chat service"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .timeout:
            return "Request timed out"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return "Server error: \(message)"
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        }
    }
}
