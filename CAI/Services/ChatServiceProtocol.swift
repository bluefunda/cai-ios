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

/// A single MCP server reference for the client-driven multi-select wire
/// format (bluefunda/cai-ios#171). Mirrors cai-bff's `MCPServerRef{Name, URL}`
/// (internal/nats/models/messages.go) — only `name` is required; `url` is
/// resolved server-side from the account's MCP registry when omitted/empty,
/// same as the legacy singular `mcpServerName` field already does.
struct MCPServerRef {
    let name: String
    let url: String?

    func toJSON() -> [String: Any] {
        var json: [String: Any] = ["name": name]
        if let url { json["url"] = url }
        return json
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
    /// Multiple simultaneously-enabled MCP servers (bluefunda/cai-ios#171).
    /// Additive to `mcpServerName`/`mcpServerURL` above: only populated when
    /// more than one assistant is enabled at once, since cai-llm-router's
    /// client-driven multi-MCP path activates specifically on `count > 1`
    /// (a single enabled server keeps using the legacy singular fields, which
    /// preserve persona-swap behavior like ABAPer's tuned model/prompt).
    let mcpServers: [MCPServerRef]?
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
    /// The persona active for this specific message (bluefunda/cai-ios#177,
    /// #208), e.g. "abap" or "fi-ca" — override-or-inherited, resolved once
    /// per send. Additive context for response tuning, independent of
    /// `agentName` (reserved for actual backend agent routing). `nil` when
    /// the SAP persona feature is disabled — omitted from the wire payload
    /// entirely rather than sent as a placeholder value, so the backend
    /// applies its own default assistant behavior.
    let persona: String?

    init(
        chatId: String,
        prompt: String,
        model: String,
        isNewChat: Bool = true,
        mcpServerName: String? = nil,
        mcpServerURL: String? = nil,
        mcpServers: [MCPServerRef]? = nil,
        messages: [ChatMessage]? = nil,
        thinkingMode: String = "auto",
        modelExplicit: Bool = false,
        fileUrl: String? = nil,
        agentName: String? = nil,
        persona: String? = nil
    ) {
        self.chatId = chatId
        self.prompt = prompt
        self.model = model
        self.isNewChat = isNewChat
        self.mcpServerName = mcpServerName
        self.mcpServerURL = mcpServerURL
        self.mcpServers = mcpServers
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
            "modelExplicit": modelExplicit
        ]

        if let mcpName = mcpServerName { json["mcp_server_name"] = mcpName }
        if let mcpURL  = mcpServerURL  { json["mcp_server_url"]  = mcpURL  }
        if let servers = mcpServers, !servers.isEmpty {
            json["mcpServers"] = servers.map { $0.toJSON() }
        }
        if let agent   = agentName     { json["agentName"]        = agent   }
        if let persona                 { json["persona"]          = persona }

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
    /// Real-time status of a backend tool-use step (bluefunda/cai-ios#310),
    /// e.g. "Searching the knowledge base…" — only emitted when the backend
    /// actually runs a tool for this turn, never fabricated client-side.
    case status(StepEvent)

    var isTerminal: Bool {
        switch self {
        case .streamEnd, .error, .rateLimited:
            return true
        default:
            return false
        }
    }
}

// MARK: - Step Event (live status, bluefunda/cai-ios#310)

/// One `stream_status` SSE frame from cai-llm-router (bluefunda/cai-llm-router#324).
struct StepEvent: Equatable {
    let stepId: String
    let title: String
    let detail: String
    let state: StepState
    /// Set for `stream_inline_status`: the step happened after the answer started, at this
    /// position in the answer text (UTF-16 code units) — rendered in place, claude.ai-style.
    var contentOffset: Int? = nil
    /// The AI's apparent mood for this step (thinking / curious / happy / sad), for the mascot.
    var mood: String? = nil
}

enum StepState: String, Equatable {
    case active
    case done
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
    /// Persona active when this message was sent/answered (bluefunda/cai-ios#207)
    /// — the same value for a user message and the assistant reply that answered
    /// it, so history stays consistent per turn even after the global default
    /// changes. `nil` when the feature was disabled for that send, or when
    /// loaded from history that predates this field.
    var persona: String? = nil
    /// Live tool-use status steps accumulated while this message streamed
    /// (bluefunda/cai-ios#310). `nil`/empty for turns with no backend tool
    /// activity, and for any message loaded from history/cache predating
    /// this field — `Optional` so the synthesized `Codable` conformance
    /// decodes a missing key as `nil` instead of throwing, same as
    /// `fileUrl`/`fileMetadata`/`persona` above.
    var steps: [MessageStep]? = nil
    /// Wall-clock seconds from the first step appearing to the stream ending
    /// (bluefunda/cai-ios#310 follow-up) — computed once in `ChatManager` and
    /// persisted alongside `steps`, so `ThinkingStepsView`'s "Thought for Ns"
    /// header has real data to show after a reload, instead of only being
    /// derivable while the view itself was live for the whole stream.
    var thinkingDurationSeconds: Int? = nil
    /// When the first thinking step arrived, set only while the turn is live so
    /// `ThinkingStepsView`'s running timer uses the same clock as the
    /// `thinkingDurationSeconds` `ChatManager` freezes — not the view's own
    /// onAppear time. Not sent to the server; `nil` for anything from history.
    var thinkingStartedAt: Date? = nil

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        fileUrl: String? = nil,
        fileMetadata: [MessageFileMetadata]? = nil,
        persona: String? = nil,
        steps: [MessageStep]? = nil,
        thinkingDurationSeconds: Int? = nil,
        thinkingStartedAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.fileUrl = fileUrl
        self.fileMetadata = fileMetadata
        self.persona = persona
        self.steps = steps
        self.thinkingDurationSeconds = thinkingDurationSeconds
        self.thinkingStartedAt = thinkingStartedAt
    }

}

/// One live status row shown in `ThinkingStepsView` while/after a message
/// streams (bluefunda/cai-ios#310). Mirrors `StepEvent` but persists on the
/// message itself so history/cache round-trips it like any other field.
// MARK: - Thinking phase

/// Thinking is over the moment the answer starts streaming — matching ChatGPT/claude.ai,
/// where the box locks to "Thought for Ns" and stops its spinner at the first answer token,
/// not when the whole answer finishes. Shared by every place `ChatManager` closes it.
extension Array where Element == MessageStep {
    /// Marks every step finished, so none keeps a spinner once thinking has ended.
    mutating func finishAll() {
        for index in indices { self[index].isActive = false }
    }
}

extension MessageStep {
    /// Whole seconds of thinking, at least 1 — what "Thought for Ns" shows.
    static func thinkingDuration(since startedAt: Date, until end: Date = Date()) -> Int {
        max(1, Int(end.timeIntervalSince(startedAt).rounded()))
    }
}

struct MessageStep: Codable, Equatable, Identifiable {
    var id: String { stepId }
    let stepId: String
    var title: String
    var detail: String
    var isActive: Bool
    /// nil = part of the "Thought for Ns" card above the answer; set = a step that happened
    /// mid-answer, shown in place at this UTF-16 offset of the answer text (claude.ai-style).
    var contentOffset: Int?
    var mood: String?

    init(stepId: String, title: String, detail: String, isActive: Bool, contentOffset: Int? = nil, mood: String? = nil) {
        self.stepId = stepId
        self.title = title
        self.detail = detail
        self.isActive = isActive
        self.contentOffset = contentOffset
        self.mood = mood
    }

    // Custom decoding: `isActive` is absent from the server's persisted history (cai-mcp-go
    // never stores it — a step read back from history is, by definition, no longer "in
    // progress"), so the synthesized Decodable (which would require the key) is replaced with
    // one that defaults it to false when missing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stepId = try container.decode(String.self, forKey: .stepId)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        contentOffset = try container.decodeIfPresent(Int.self, forKey: .contentOffset)
        mood = try container.decodeIfPresent(String.self, forKey: .mood)
    }
}

extension Array where Element == MessageStep {
    /// Steps for the "Thought for Ns" card above the answer.
    var cardSteps: [MessageStep] { filter { $0.contentOffset == nil } }
    /// Steps that happened mid-answer, rendered in place inside the answer.
    var inlineSteps: [MessageStep] { filter { $0.contentOffset != nil } }

    /// Upserts a live step event by stepId. Only one step reads as in progress at a time
    /// (claude.ai). Once thinking is locked (answer started), card steps can't reopen —
    /// but inline steps stay live: they are shown in place in the answer.
    mutating func apply(_ event: StepEvent, thinkingLocked: Bool) {
        if let index = firstIndex(where: { $0.stepId == event.stepId }) {
            self[index].title = event.title
            self[index].detail = event.detail
            self[index].isActive = event.state == .active
            self[index].contentOffset = self[index].contentOffset ?? event.contentOffset
            self[index].mood = event.mood ?? self[index].mood
        } else {
            append(MessageStep(stepId: event.stepId, title: event.title, detail: event.detail,
                               isActive: event.state == .active, contentOffset: event.contentOffset, mood: event.mood))
        }
        if event.state == .active {
            for index in indices where self[index].stepId != event.stepId { self[index].isActive = false }
        }
        if thinkingLocked {
            for index in indices where self[index].contentOffset == nil { self[index].isActive = false }
        }
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
        self.persona = persisted.persona
        self.steps = persisted.stepsJSON
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([MessageStep].self, from: $0) }
        self.thinkingDurationSeconds = persisted.thinkingDurationSeconds
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
