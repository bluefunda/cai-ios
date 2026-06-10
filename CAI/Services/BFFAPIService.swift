import Foundation

// MARK: - BFF REST API Service
// Handles all non-streaming REST calls to cai-bff endpoints.
// Token injection and refresh is delegated to the APIClient via tokenProvider.

final class BFFAPIService {
    private let client: APIClient

    init(baseURL: String, tokenProvider: @escaping TokenProvider) {
        client = APIClient(baseURL: baseURL, tokenProvider: tokenProvider)
    }

    // MARK: - User

    func fetchUserInfo() async throws -> UserInfoDTO {
        try await client.get("/userinfo")
    }

    func fetchSettings() async throws -> UserSettingsDTO {
        try await client.get("/settings")
    }

    // MARK: - Models

    func fetchModels() async throws -> [LLMModelDTO] {
        let response: ModelsResponse = try await client.get("/models")
        return response.models
    }

    // MARK: - Chats

    func fetchChats() async throws -> [ChatSummaryDTO] {
        let response: ChatListResponse = try await client.get("/chats")
        return response.chats
    }

    func fetchChatMessages(chatId: String) async throws -> [ChatMessageDTO] {
        let response: ChatMessagesResponse = try await client.get("/chats/\(chatId)/messages")
        return response.messages
    }

    func fetchChatContext(chatId: String) async throws -> [ChatContextItemDTO] {
        let response: ChatContextResponse = try await client.get("/chats/\(chatId)/context")
        return response.context
    }

    func persistMessage(chatId: String, role: String, content: String) async throws {
        try await client.postIgnoringResponse("/chats/\(chatId)/persist", body: [
            "role": role,
            "content": content
        ])
    }

    func generateTitle(chatId: String, message: String) async throws -> String {
        // BFF reads the "prompt" key — verified against cai-bff (req.Prompt),
        // the cai web app ({ prompt }), and the Postman collection. Sending the
        // wrong key left the prompt empty, so the model returned a generic
        // "New Chat" that then got persisted.
        let response: TitleResponse = try await client.post("/chats/\(chatId)/title", body: ["prompt": message])
        if let title = response.title, !title.isBlank, title != "New Chat" {
            return title
        }
        return message.truncated(to: 60)
    }

    func stopStream(chatId: String) async throws {
        try await client.postIgnoringResponse("/chats/\(chatId)/stop", body: [:])
    }

    // MARK: - MCP Servers

    func fetchAllMCPServers() async throws -> [MCPServerDTO] {
        let response: MCPListResponse = try await client.get("/mcp")
        return response.servers
    }

    func fetchUserMCPServers() async throws -> [MCPServerDTO] {
        let response: MCPListResponse = try await client.get("/mcp/user")
        return response.servers
    }

    func selectMCPServer(serverId: String) async throws {
        try await client.postIgnoringResponse("/mcp/select", body: ["server_id": serverId])
    }

    // MARK: - Rate Limit

    func fetchRateLimit() async throws -> RateLimitDTO {
        try await client.get("/rate-limit")
    }

    // MARK: - Greetings

    func fetchGreetings() async throws -> GreetingsDTO {
        try await client.get("/greetings")
    }

    // MARK: - Storage

    func listStorage(bucket: String, prefix: String = "") async throws -> [StorageObjectDTO] {
        let response: StorageListDTO = try await client.get(
            "/storage/list",
            queryItems: [
                URLQueryItem(name: "bucket", value: bucket),
                URLQueryItem(name: "prefix", value: prefix)
            ]
        )
        return response.objects
    }

    func storageStats(bucket: String) async throws -> StorageStatsDTO {
        try await client.get("/storage/stats", queryItems: [URLQueryItem(name: "bucket", value: bucket)])
    }

    func getPresignedURL(bucket: String, key: String, action: String = "get") async throws -> String? {
        let response: PresignedURLDTO = try await client.get(
            "/storage/presigned-url",
            queryItems: [
                URLQueryItem(name: "bucket", value: bucket),
                URLQueryItem(name: "key", value: key),
                URLQueryItem(name: "action", value: action)
            ]
        )
        return response.resolvedURL
    }

    func deleteStorageObject(bucket: String, key: String) async throws {
        try await client.deleteIgnoringResponse(
            "/storage/delete",
            queryItems: [
                URLQueryItem(name: "bucket", value: bucket),
                URLQueryItem(name: "key", value: key)
            ]
        )
    }

    func createFolder(bucket: String, folder: String) async throws {
        try await client.postIgnoringResponse("/storage/folder", body: [
            "bucket": bucket,
            "folder": folder
        ])
    }

    func uploadFile(
        data: Data,
        filename: String,
        mimeType: String,
        bucket: String = "abaper"
    ) async throws -> String? {
        let raw = try await client.uploadMultipart(
            "/storage/upload",
            data: data,
            filename: filename,
            mimeType: mimeType,
            queryItems: [URLQueryItem(name: "bucket", value: bucket)]
        )
        let result = try JSONDecoder().decode(FileUploadResultDTO.self, from: raw)
        return result.resolvedURL
    }

    // MARK: - Stripe

    func fetchSubscription() async throws -> StripeSubscriptionDTO {
        try await client.get("/stripe/subscription")
    }

    func fetchPlans() async throws -> [StripePlanDTO] {
        let response: StripePlansDTO = try await client.get("/stripe/plans")
        return response.plans
    }
}

// MARK: - Convenience: AuthManager token provider factory

extension BFFAPIService {
    /// Creates a BFFAPIService wired to an AuthManager for token provision.
    static func make(baseURL: String, authManager: AuthManager) -> BFFAPIService {
        BFFAPIService(baseURL: baseURL) {
            try await authManager.refreshTokenIfNeeded()
            guard let token = await authManager.accessToken else {
                throw APIError.unauthorized
            }
            return token
        }
    }
}
