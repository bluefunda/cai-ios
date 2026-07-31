import Foundation

// MARK: - LLM Models (/models)

/// Flexible container for /models response.
/// Backend returns {"llmInfo": [{name, label, modelId}]} or {"llmModels": [...]}
/// or legacy {"models": [...]} or a flat array.
struct ModelsResponse: Codable {
    let models: [LLMModelDTO]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let m = try? container.decode([LLMModelDTO].self, forKey: .llmInfo)   { self.models = m; return }
            if let m = try? container.decode([LLMModelDTO].self, forKey: .llmModels) { self.models = m; return }
            if let m = try? container.decode([LLMModelDTO].self, forKey: .models)    { self.models = m; return }
        }
        let container = try decoder.singleValueContainer()
        self.models = try container.decode([LLMModelDTO].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(models, forKey: .models)
    }

    enum CodingKeys: String, CodingKey {
        case models, llmInfo, llmModels
    }
}

/// Backend format: {name: "deepseek", label: "DeepSeek", modelId: 1}
/// Legacy iOS format: {id: "deepseek", name: "DeepSeek", provider: "..."}
struct LLMModelDTO: Codable, Identifiable {
    let id: String       // alias sent to backend
    let name: String     // display name
    let provider: String?
    let description: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId    = try? c.decode(String.self, forKey: .id)
        let rawName  = try? c.decode(String.self, forKey: .name)
        let rawLabel = try? c.decode(String.self, forKey: .label)

        if rawId == nil, let alias = rawName {
            // Backend format: name is the alias/ID, label is the display name
            self.id   = alias
            self.name = rawLabel.flatMap { $0.isEmpty ? nil : $0 } ?? alias.capitalized
        } else {
            // Legacy format: id and name are already separated
            self.id   = rawId ?? rawName ?? UUID().uuidString
            self.name = rawLabel ?? rawName ?? ""
        }
        self.provider    = try? c.decode(String.self, forKey: .provider)
        self.description = try? c.decode(String.self, forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,   forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(provider,    forKey: .provider)
        try c.encodeIfPresent(description, forKey: .description)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, label, provider, description
    }
}

// MARK: - Chats (/chats)

/// Flexible container for /chats response.
struct ChatListResponse: Codable {
    let chats: [ChatSummaryDTO]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let chats = try? container.decode([ChatSummaryDTO].self, forKey: .chats) {
            self.chats = chats
            return
        }
        let container = try decoder.singleValueContainer()
        self.chats = (try? container.decode([ChatSummaryDTO].self)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chats, forKey: .chats)
    }

    enum CodingKeys: String, CodingKey { case chats }
}

struct ChatSummaryDTO: Codable, Identifiable {
    let id: String
    let title: String?
    let firstMessage: String?
    let model: String?
    let createdAt: String?
    let updatedAt: String?
    let messageCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "chatId"
        case title = "chatTitle"
        case firstMessage = "firstPrompt"   // BFF field name
        case model
        case createdAt
        case updatedAt
        case messageCount
    }
}

// MARK: - Chat Messages (/chats/{id}/messages)

struct ChatMessagesResponse: Codable {
    let messages: [ChatMessageDTO]

    // BFF returns { "chatHistory": [...] } — also handle "messages" and flat arrays.
    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let msgs = try? container.decode([ChatMessageDTO].self, forKey: .chatHistory) {
                self.messages = msgs; return
            }
            if let msgs = try? container.decode([ChatMessageDTO].self, forKey: .messages) {
                self.messages = msgs; return
            }
        }
        let container = try decoder.singleValueContainer()
        self.messages = (try? container.decode([ChatMessageDTO].self)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messages, forKey: .messages)
    }

    enum CodingKeys: String, CodingKey {
        case chatHistory, messages
    }
}

struct ChatMessageDTO: Codable {
    let id: String?
    let role: String       // "Human", "AI", "user", "assistant"
    let content: String
    let createdAt: String?
    /// Durable reference to a user-attached file, relayed by cai-bff from history.
    let fileUrl: String?
    /// Ready-to-use URL for an LLM-generated file.
    let fileDownloadUrl: String?
    /// Structured reference(s) for LLM-generated files.
    let fileMetadata: [FileMetadataDTO]?

    enum CodingKeys: String, CodingKey {
        case id, role, content, createdAt, fileUrl, fileDownloadUrl
        case fileMetadata = "file_metadata"
    }

    /// Converts web role names ("Human", "AI") to canonical role strings ("user", "assistant")
    var normalizedRoleString: String {
        switch role.lowercased() {
        case "human", "user": return "user"
        case "ai", "assistant": return "assistant"
        case "system": return "system"
        default: return "user"
        }
    }
}

/// Structured, durable reference for a file involved in a chat message —
/// mirrors cai-bff's `FileMetadata` (relayed from cai-llm-router via cai-mcp-go).
struct FileMetadataDTO: Codable, Hashable {
    let originalURL: String?
    let s3Path: String?
    let downloadURL: String?
    let fileName: String?
    let fileSize: Int64?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case originalURL = "original_url"
        case s3Path = "s3_path"
        case downloadURL = "download_url"
        case fileName = "file_name"
        case fileSize = "file_size"
        case source
    }
}

// MARK: - Chat Context (/chats/{id}/context)

struct ChatContextResponse: Codable {
    let context: [ChatContextItemDTO]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            // Try both key names used by backend
            if let ctx = try? container.decode([ChatContextItemDTO].self, forKey: .chatContext) {
                self.context = ctx; return
            }
            if let ctx = try? container.decode([ChatContextItemDTO].self, forKey: .context) {
                self.context = ctx; return
            }
        }
        let container = try decoder.singleValueContainer()
        self.context = (try? container.decode([ChatContextItemDTO].self)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(context, forKey: .context)
    }

    enum CodingKeys: String, CodingKey {
        case chatContext, context
    }
}

struct ChatContextItemDTO: Codable {
    let role: String
    let content: String
}

// MARK: - Title (/chats/{id}/title)

struct TitleResponse: Codable {
    let title: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Backend may use different key names
        title = (try? container.decode(String.self, forKey: .generatedTitle))
             ?? (try? container.decode(String.self, forKey: .title))
             ?? (try? container.decode(String.self, forKey: .chatTitle))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
    }

    enum CodingKeys: String, CodingKey {
        case generatedTitle, title, chatTitle
    }
}

// MARK: - User Info (/userinfo)

struct UserInfoDTO: Codable {
    let sub: String
    let email: String?
    let name: String?
    let givenName: String?
    let familyName: String?
    let preferredUsername: String?
    let realmAccess: RealmAccessDTO?

    enum CodingKeys: String, CodingKey {
        case sub, email, name
        case givenName = "given_name"
        case familyName = "family_name"
        case preferredUsername = "preferred_username"
        case realmAccess = "realm_access"
    }
}

struct RealmAccessDTO: Codable {
    let roles: [String]
}

// MARK: - Settings (/settings)

/// Settings are opaque — decode as raw JSON for flexibility.
struct UserSettingsDTO: Codable {
    let raw: [String: AnyCodable]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = (try? container.decode([String: AnyCodable].self)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    subscript(key: String) -> AnyCodable? { raw[key] }
}

/// Wrapper that allows encoding/decoding arbitrary JSON values.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v }
        else if let v = try? container.decode([AnyCodable].self) { value = v }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:   try container.encode(v)
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as [String: AnyCodable]: try container.encode(v)
        case let v as [AnyCodable]: try container.encode(v)
        default: try container.encodeNil()
        }
    }
}

// MARK: - Rate Limit (/rate-limit)

struct RateLimitStatsDTO: Codable {
    let planName: String?
    let dailyTokensUsed: Int?
    let dailyTokensLimit: Int?
    let monthlyTokensUsed: Int?
    let monthlyTokensLimit: Int?
    let hourlyTokensUsed: Int?
    let hourlyTokensLimit: Int?

    enum CodingKeys: String, CodingKey {
        case planName = "plan_name"
        case dailyTokensUsed = "daily_tokens_used"
        case dailyTokensLimit = "daily_tokens_limit"
        case monthlyTokensUsed = "monthly_tokens_used"
        case monthlyTokensLimit = "monthly_tokens_limit"
        case hourlyTokensUsed = "hourly_tokens_used"
        case hourlyTokensLimit = "hourly_tokens_limit"
    }
}

struct RateLimitDTO: Codable {
    let stats: RateLimitStatsDTO?
    let isBlocked: Bool?
    let blockReason: String?
    let resetInSeconds: Int?
    let resetLabel: String?

    enum CodingKeys: String, CodingKey {
        case stats
        case isBlocked = "is_blocked"
        case blockReason = "block_reason"
        case resetInSeconds = "reset_in_seconds"
        case resetLabel = "reset_label"
    }

    var dailyUsagePercent: Double {
        guard let used = stats?.dailyTokensUsed, let limit = stats?.dailyTokensLimit, limit > 0 else { return 0 }
        return min(Double(used) / Double(limit), 1.0)
    }

    var monthlyUsagePercent: Double {
        guard let used = stats?.monthlyTokensUsed, let limit = stats?.monthlyTokensLimit, limit > 0 else { return 0 }
        return min(Double(used) / Double(limit), 1.0)
    }
}

// MARK: - MCP Servers (/mcp, /mcp/user)

/// Backend returns {"mcpInfo": [{server_id, name, mcp_server_url, ...}]}
struct MCPListResponse: Codable {
    let servers: [MCPServerDTO]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let s = try? container.decode([MCPServerDTO].self, forKey: .mcpInfo)    { self.servers = s; return }
            if let s = try? container.decode([MCPServerDTO].self, forKey: .mcpForUser) { self.servers = s; return }
            if let s = try? container.decode([MCPServerDTO].self, forKey: .servers)    { self.servers = s; return }
        }
        let container = try decoder.singleValueContainer()
        self.servers = (try? container.decode([MCPServerDTO].self)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(servers, forKey: .servers)
    }

    enum CodingKeys: String, CodingKey { case servers, mcpInfo, mcpForUser }
}

struct SubscriptionStripeDTO: Codable {
    let hasSubscription: Bool
    let plan: String

    enum CodingKeys: String, CodingKey {
        case hasSubscription = "has_subscription"
        case plan
    }
}

struct SubscriptionAppleDTO: Codable {
    let registered: Bool
    let plan: String
    let status: String
}

struct SubscriptionDTO: Codable {
    let plan: String
    let source: String
    let isPro: Bool
    let stripe: SubscriptionStripeDTO
    let apple: SubscriptionAppleDTO

    enum CodingKeys: String, CodingKey {
        case plan, source
        case isPro = "is_pro"
        case stripe, apple
    }
}

/// Backend MCPInfo: {server_id (int), name, mcp_server_url, shortDescription, isAvailable}
struct MCPServerDTO: Codable, Identifiable {
    let id: String           // derived from server_id (int → string)
    let name: String
    let url: String?
    let description: String?
    let enabled: Bool?

    var resolvedURL: String { url ?? "" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // server_id is an int in the new backend format; fall back to string "id"
        if let intId = try? c.decode(Int.self, forKey: .serverId) {
            self.id = String(intId)
        } else {
            self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        self.name        = (try? c.decode(String.self, forKey: .name)) ?? ""
        // mcp_server_url is the canonical URL field; fall back to "url"
        self.url         = (try? c.decode(String.self, forKey: .mcpServerUrl))
                        ?? (try? c.decode(String.self, forKey: .url))
        // shortDescription is the canonical description field
        self.description = (try? c.decode(String.self, forKey: .shortDescription))
                        ?? (try? c.decode(String.self, forKey: .description))
        self.enabled     = (try? c.decode(Bool.self, forKey: .isAvailable))
                        ?? (try? c.decode(Bool.self, forKey: .enabled))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,   forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(url,         forKey: .url)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(enabled,     forKey: .enabled)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, url, description, enabled
        case serverId        = "server_id"
        case mcpServerUrl    = "mcp_server_url"
        case shortDescription = "shortDescription"
        case isAvailable     = "isAvailable"
    }
}

// MARK: - Storage (/storage/*)

struct StorageListDTO: Codable {
    let objects: [StorageObjectDTO]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let objs = try? container.decode([StorageObjectDTO].self, forKey: .objects) {
                self.objects = objs; return
            }
            if let objs = try? container.decode([StorageObjectDTO].self, forKey: .files) {
                self.objects = objs; return
            }
        }
        let container = try decoder.singleValueContainer()
        self.objects = (try? container.decode([StorageObjectDTO].self)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(objects, forKey: .objects)
    }

    enum CodingKeys: String, CodingKey { case objects, files }
}

struct StorageObjectDTO: Codable, Identifiable {
    let key: String
    let name: String?
    let size: Int64?
    let lastModified: String?
    let contentType: String?

    var id: String { key }
    var displayName: String { name ?? key.split(separator: "/").last.map(String.init) ?? key }

    var formattedSize: String {
        guard let size = size else { return "—" }
        let bytes = Double(size)
        if bytes < 1024 { return "\(size) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", bytes / 1024) }
        return String(format: "%.1f MB", bytes / 1_048_576)
    }
}

struct FileUploadResultDTO: Codable {
    let url: String?
    let key: String?
    let path: String?
    let message: String?

    var resolvedURL: String? { url ?? key ?? path }
}

/// Response shape for `POST /fileupload` — the shared chat-attachment upload
/// contract also used by the web app (`{ file: [{ url, name, size, ... }] }`,
/// verified against the live gateway response — cai-gw's `is_collection`/
/// `mapping` config on this endpoint wraps trm-s3's raw JSON array under a
/// top-level "file" key, with no additional "data" nesting).
/// Deliberately separate from `FileUploadResultDTO`, which is the bucket-scoped
/// `/storage/upload` response used by the unrelated Storage browser feature.
struct FileUploadForPromptResponseDTO: Codable {
    struct FileEntry: Codable {
        let url: String?
    }
    let file: [FileEntry]?

    var resolvedURL: String? { file?.first?.url }
}

struct StorageStatsDTO: Codable {
    let totalSize: Int64?
    let fileCount: Int?
    let bucketName: String?

    enum CodingKeys: String, CodingKey {
        case totalSize = "total_size"
        case fileCount = "file_count"
        case bucketName = "bucket_name"
    }
}

struct PresignedURLDTO: Codable {
    let url: String?
    let presignedUrl: String?

    var resolvedURL: String? { url ?? presignedUrl }

    enum CodingKeys: String, CodingKey {
        case url
        case presignedUrl = "presigned_url"
    }
}

// MARK: - Greetings (/greetings)

struct GreetingsDTO: Codable {
    let greetings: [String]?
    let greeting: String?
    let message: String?

    var displayGreeting: String {
        if let greetings = greetings, !greetings.isEmpty {
            return greetings.randomElement() ?? ""
        }
        return greeting ?? message ?? ""
    }
}

// MARK: - Generic API Error

struct APIErrorDTO: Codable {
    let error: String?
    let message: String?
    let code: Int?

    var displayMessage: String {
        message ?? error ?? "An unknown error occurred"
    }
}
