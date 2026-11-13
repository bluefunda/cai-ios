import Foundation

// MARK: - BFF REST API Service
// Handles all non-streaming REST calls to cai-bff endpoints.
// Token injection and refresh is delegated to the APIClient via tokenProvider.

final class BFFAPIService {
    private let client: APIClient

    init(baseURL: String, tokenProvider: @escaping TokenProvider, session: URLSession = .shared) {
        client = APIClient(baseURL: baseURL, tokenProvider: tokenProvider, session: session)
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

    /// Chats per sidebar page; more load as the list is scrolled to its end (cai-ios#370).
    static let chatPageSize = 30

    /// One page of chats, newest activity first. Pass the previous page's `nextCursor` for the
    /// next one; the first page (nil cursor) also carries every pinned chat.
    func fetchChatPage(cursor: String?) async throws -> ChatPageResponse {
        var items = [URLQueryItem(name: "paged", value: "true"),
                     URLQueryItem(name: "limit", value: String(Self.chatPageSize))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await client.get("/chats", queryItems: items)
    }

    /// Searches chat titles and message text (cai-ios#370), one page at a time.
    func searchChats(query: String, cursor: String?) async throws -> ChatSearchResponse {
        var items = [URLQueryItem(name: "q", value: query),
                     URLQueryItem(name: "limit", value: "20")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await client.get("/chats/search", queryItems: items)
    }

    /// Pins or unpins a chat (cai-ios#335).
    func setChatPinned(chatId: String, pinned: Bool) async throws {
        try await client.postIgnoringResponse("/chats/\(chatId)/pin", body: ["pinned": pinned])
    }

    /// A fresh download link for a file the assistant created in a chat (#371): the link saved
    /// with the reply expires. 404 when the file is gone.
    func fileLink(chatId: String, s3Path: String) async throws -> String {
        let response: FileLinkResponse = try await client.post("/chats/\(chatId)/file-link", body: ["s3_path": s3Path])
        return response.downloadUrl
    }

    func fetchChatMessages(chatId: String) async throws -> [ChatMessageDTO] {
        let response: ChatMessagesResponse = try await client.get("/chats/\(chatId)/messages")
        return response.messages
    }

    func fetchChatContext(chatId: String) async throws -> [ChatContextItemDTO] {
        let response: ChatContextResponse = try await client.get("/chats/\(chatId)/context")
        return response.context
    }

    /// - Parameters:
    ///   - steps/thinkingDurationSeconds: Only meaningful on an "AI" persist call. Sent so
    ///     cai-mcp-go can store them server-side (previously on-device only, via SwiftData) —
    ///     without this, reopening the same chat on a different device or after a reinstall
    ///     never showed thinking history for a turn, even though it had one.
    func persistMessage(
        chatId: String, role: String, content: String,
        steps: [MessageStep]? = nil, thinkingDurationSeconds: Int? = nil
    ) async throws {
        var body: [String: Any] = [
            "role": role,
            "content": content
        ]
        if let steps, !steps.isEmpty {
            body["steps"] = steps.map { ["stepId": $0.stepId, "title": $0.title, "detail": $0.detail] }
        }
        if let thinkingDurationSeconds {
            body["thinkingDurationSeconds"] = thinkingDurationSeconds
        }
        try await client.postIgnoringResponse("/chats/\(chatId)/persist", body: body)
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

    /// Tells cai-bff which app opened a connect flow, so its result page sends the sign-in
    /// sheet back to `cai://oauth/<connector>/done` — ASWebAuthenticationSession's callback
    /// scheme — and the sheet closes by itself once connected.
    private static let oauthClient = URLQueryItem(name: "client", value: "ios")

    // MARK: - GitHub OAuth (bluefunda/cai-llm-router#345 Phase 2)

    func fetchGitHubOAuthStatus() async throws -> OAuthStatusDTO {
        try await client.get("/oauth/github/status")
    }

    func fetchGitHubAuthorizeURL() async throws -> URL {
        let response: OAuthAuthorizeDTO = try await client.get("/oauth/github/authorize", queryItems: [Self.oauthClient])
        guard let url = URL(string: response.authorizeUrl) else {
            throw ChatServiceError.invalidResponse
        }
        return url
    }

    func disconnectGitHub() async throws {
        try await client.postIgnoringResponse("/oauth/github/disconnect", body: [:])
    }

    // MARK: - Figma OAuth (bluefunda/infra#54)

    func fetchFigmaOAuthStatus() async throws -> OAuthStatusDTO {
        try await client.get("/oauth/figma/status")
    }

    func fetchFigmaAuthorizeURL() async throws -> URL {
        let response: OAuthAuthorizeDTO = try await client.get("/oauth/figma/authorize", queryItems: [Self.oauthClient])
        guard let url = URL(string: response.authorizeUrl) else {
            throw ChatServiceError.invalidResponse
        }
        return url
    }

    func disconnectFigma() async throws {
        try await client.postIgnoringResponse("/oauth/figma/disconnect", body: [:])
    }

    // MARK: - SAP Credentials (ABAPer connector, bluefunda/cai-bff#160)

    func fetchSAPCredentialsStatus() async throws -> SAPCredentialsStatusDTO {
        try await client.get("/sap/status")
    }

    func connectSAP(host: String, client sapClient: String, username: String, password: String) async throws {
        let _: StatusAckDTO = try await client.post(
            "/sap/connect",
            body: SAPCredentialsConnectRequest(host: host, client: sapClient, username: username, password: password)
        )
    }

    func disconnectSAP() async throws {
        try await client.postIgnoringResponse("/sap/disconnect", body: [:])
    }

    // MARK: - OData connection (OData connector, cai-bff odatacreds)

    func fetchODataConnectionStatus() async throws -> ODataConnectionStatusDTO {
        try await client.get("/odata/status")
    }

    func connectOData(_ request: ODataConnectRequest) async throws {
        let _: StatusAckDTO = try await client.post("/odata/connect", body: request)
    }

    func disconnectOData() async throws {
        try await client.postIgnoringResponse("/odata/disconnect", body: [:])
    }

    // MARK: - One-tap connectors (Apollo.io; cai-bff connectors)

    /// Server names this user connected, on any device, e.g. ["apollo-mcp"].
    func fetchOneTapConnectors() async throws -> OneTapConnectorsDTO {
        try await client.get("/connectors/status")
    }

    func connectOneTapConnector(_ name: String) async throws -> OneTapConnectorsDTO {
        try await client.post("/connectors/connect", body: ["name": name])
    }

    func disconnectOneTapConnector(_ name: String) async throws -> OneTapConnectorsDTO {
        try await client.post("/connectors/disconnect", body: ["name": name])
    }

    // MARK: - Personas

    func fetchPersonas() async throws -> [Persona] {
        let response: PersonasResponse = try await client.get("/personas")
        return response.personas
    }

    // MARK: - Rate Limit

    func fetchRateLimit() async throws -> RateLimitDTO {
        try await client.get("/rate-limit")
    }

    // MARK: - Subscription

    /// Registers an Apple IAP transaction with the backend so it can verify the
    /// purchase with Apple and cache the subscription state.
    func registerAppleSubscription(originalTransactionId: String) async throws {
        try await client.postIgnoringResponse("/subscription/apple", body: [
            "original_transaction_id": originalTransactionId
        ])
    }

    /// Returns the user's active plan from whichever payment source (Stripe or
    /// Apple IAP) grants the highest tier.
    func fetchSubscription() async throws -> SubscriptionDTO {
        try await client.get("/subscription")
    }

    // MARK: - Greetings

    func fetchGreetings() async throws -> GreetingsDTO {
        try await client.get("/greetings")
    }

    // MARK: - Storage
    // The web's Cloud Storage route: cai-gw /rest/{space}/v1/storage/* goes straight to
    // trm-s3 with the service credentials it requires, and trm-s3 reads the user from the
    // Access-Token header every APIClient request carries. The bucket is the user's space,
    // and the path segment is that same space, as the web sends it.

    private func storagePath(_ bucket: String, _ action: String) -> String {
        "/rest/\(bucket)/v1/storage/\(action)"
    }

    /// The payload of a storage reply, or its error.
    private func storageData<T>(_ envelope: StorageEnvelope<T>) throws -> T {
        guard envelope.success, let data = envelope.data else {
            throw StorageError(message: envelope.error ?? "Files couldn't be reached. Try again in a moment.")
        }
        return data
    }

    func listStorage(bucket: String, prefix: String = "") async throws -> StorageListDTO {
        let envelope: StorageEnvelope<StorageListDTO> = try await client.get(
            storagePath(bucket, "list"),
            queryItems: [URLQueryItem(name: "bucket", value: bucket), URLQueryItem(name: "prefix", value: prefix)]
        )
        return try storageData(envelope)
    }

    func storageStats(bucket: String) async throws -> StorageStatsDTO {
        let envelope: StorageEnvelope<StorageStatsDTO> = try await client.get(
            storagePath(bucket, "stats"), queryItems: [URLQueryItem(name: "bucket", value: bucket)])
        return try storageData(envelope)
    }

    /// A download link for `key`, valid for an hour.
    func getPresignedURL(bucket: String, key: String) async throws -> String? {
        let envelope: StorageEnvelope<PresignedURLDTO> = try await client.get(
            storagePath(bucket, "presigned-url"),
            queryItems: [
                URLQueryItem(name: "bucket", value: bucket),
                URLQueryItem(name: "key", value: key),
                URLQueryItem(name: "action", value: "download")
            ]
        )
        return try storageData(envelope).url
    }

    /// Deletes a file, or a folder (a key ending in "/") with everything in it.
    func deleteStorageObject(bucket: String, key: String) async throws {
        let envelope: StorageEnvelope<[String: String]> = try await client.delete(
            storagePath(bucket, "delete"),
            queryItems: [URLQueryItem(name: "bucket", value: bucket), URLQueryItem(name: "key", value: key)]
        )
        _ = try storageData(envelope)
    }

    func createFolder(bucket: String, folder: String) async throws {
        let envelope: StorageEnvelope<[String: String]> = try await client.post(
            storagePath(bucket, "folder"), body: ["bucket": bucket, "folderPath": folder])
        _ = try storageData(envelope)
    }

    /// Uploads into `prefix` (a folder path ending in "/", or "" for the top level).
    func uploadFile(data: Data, filename: String, mimeType: String, bucket: String, prefix: String) async throws {
        let raw = try await client.uploadMultipart(
            storagePath(bucket, "upload"),
            data: data,
            filename: filename,
            mimeType: mimeType,
            fields: ["prefix": prefix],
            queryItems: [URLQueryItem(name: "bucket", value: bucket)]
        )
        _ = try storageData(JSONDecoder().decode(StorageEnvelope<FileUploadResultDTO>.self, from: raw))
    }

    /// Uploads a file to attach to a chat prompt via `/fileupload` — the same
    /// endpoint/contract the web app's chat-attach flow uses (no `/api/v1`
    /// prefix, no bucket concept). Deliberately separate from `uploadFile`
    /// above, the bucket-scoped storage upload the Files browser uses.
    func uploadFileForPrompt(data: Data, filename: String, mimeType: String, userId: String) async throws -> String? {
        let raw = try await client.uploadMultipart(
            "/fileupload",
            data: data,
            filename: filename,
            mimeType: mimeType,
            fields: ["userid": userId, "path": userId]
        )
        let result = try JSONDecoder().decode(FileUploadForPromptResponseDTO.self, from: raw)
        return result.resolvedURL
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
