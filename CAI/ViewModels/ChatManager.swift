import Foundation
import SwiftData

// MARK: - Chat Manager
// Coordinates between UI, streaming chat service (BFFChatService), and REST API service (BFFAPIService).

@MainActor
final class ChatManager: ObservableObject {

    // MARK: - Published State

    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var isStreaming = false
    @Published var isLoadingChats = false
    @Published var error: String? {
        didSet { if error != nil, oldValue == nil { Haptic.notify(.error) } }
    }
    @Published var connectionStatus: ConnectionStatus = .disconnected

    @Published var selectedModel: LLMModel = LLMModel.defaultModel
    @Published var selectedMCPServer: MCPServer?

    /// Reasoning effort sent with each message. Persisted across launches.
    @Published var thinkingMode: ThinkingMode = {
        let raw = UserDefaults.standard.string(forKey: "cai_thinking_mode") ?? "auto"
        return ThinkingMode(rawValue: raw) ?? .auto
    }() {
        didSet { UserDefaults.standard.set(thinkingMode.rawValue, forKey: "cai_thinking_mode") }
    }

    /// True when the user explicitly picked an LLM (vs. letting the thinking
    /// mode drive model selection). Mirrors the web app's `modelExplicit`.
    /// Not persisted — resets to false each launch so a mode is active by default.
    @Published var userPickedModel: Bool = false

    /// Select a thinking mode — clears the explicit-model flag so the mode
    /// drives model selection on the backend.
    func selectThinkingMode(_ mode: ThinkingMode) {
        thinkingMode = mode
        userPickedModel = false
    }

    /// Select a specific LLM — marks the model as explicit so the backend
    /// uses it and ignores the thinking mode.
    func selectModel(_ model: LLMModel) {
        selectedModel = model
        userPickedModel = true
    }

    @Published var availableModels: [LLMModel] = LLMModel.defaultModels
    @Published var availableMCPServers: [MCPServer] = []
    @Published var subscribedMCPServerIds: Set<String> = []

    @Published var rateLimit: RateLimitInfo?
    @Published var showRateLimitModal = false
    // Fallback data from the rate_limited event itself, used when API call fails
    private(set) var rateLimitEventPeriod: String = "daily"
    private(set) var rateLimitEventResetSeconds: Int = 0
    @Published var greeting: String = ""
    /// True only when a fresh draft was just created via newConversation(). Cleared on first use.
    @Published var shouldAutoFocusInput: Bool = false

    // MARK: - Private

    private let service: ChatServiceProtocol
    var apiService: BFFAPIService?
    private var streamingTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    /// Latest access token — updated by CAIApp whenever AuthManager refreshes.
    private var currentBFFToken: String = ""
    /// Source of truth for auth. Used to refresh the access token before each
    /// request and to expire the session when it can no longer be refreshed.
    private weak var authManager: AuthManager?

    // MARK: - Init

    init(service: ChatServiceProtocol) {
        self.service = service
    }

    // Called once by CAIApp to hand off the AuthManager, the source of truth for
    // token refresh. Without it, ChatManager falls back to the last-known token.
    func bind(authManager: AuthManager) {
        self.authManager = authManager
    }

    /// Update the stored access token (called from CAIApp on auth state changes).
    func updateToken(_ token: String) {
        currentBFFToken = token
    }

    /// Returns a fresh, non-empty access token, refreshing via AuthManager when
    /// one is bound. Returns nil only when there is no usable token (the caller
    /// should treat that as an expired session).
    private func freshToken() async -> String? {
        if let auth = authManager, let token = await auth.validAccessToken() {
            currentBFFToken = token
            return token
        }
        return currentBFFToken.isEmpty ? nil : currentBFFToken
    }

    /// Refreshes the access token if needed and pushes it into the streaming
    /// service before a send. Returns false when the session has expired — at
    /// which point AuthManager has already flipped the app back to sign-in.
    private func ensureFreshSession() async -> Bool {
        // No AuthManager bound (e.g. unit tests) → proceed with existing token.
        guard let auth = authManager else { return true }
        guard let token = await auth.validAccessToken() else { return false }
        currentBFFToken = token
        if let credentials = auth.getCredentials() {
            try? await service.connect(credentials: credentials)
        }
        return true
    }

    // MARK: - Connection

    func connect(credentials: ServiceCredentials) async {
        currentBFFToken = credentials.accessToken

        do {
            connectionStatus = .connecting
            try await service.connect(credentials: credentials)
            connectionStatus = .connected

            // Wire up REST API service; the token provider refreshes via
            // AuthManager so long-lived sessions don't send a stale access token.
            if let bffURL = credentials.bffBaseURL {
                apiService = BFFAPIService(baseURL: bffURL, tokenProvider: { [weak self] in
                    guard let self else { throw APIError.unauthorized }
                    guard let token = await self.freshToken() else { throw APIError.unauthorized }
                    return token
                })
            }

            // Load initial data in parallel
            await loadInitialData()

        } catch {
            self.error = error.localizedDescription
            connectionStatus = .error(error.localizedDescription)
        }
    }

    func disconnect() async {
        await service.disconnect()
        connectionStatus = .disconnected
        apiService = nil
        conversations = []
        currentConversation = nil
        subscribedMCPServerIds = []
        selectedMCPServer = nil
        rateLimit = nil
    }

    // MARK: - Data Loading

    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadChats() }
            group.addTask { await self.loadModels() }
            group.addTask { await self.loadMCPServers() }
            group.addTask { await self.loadGreeting() }
        }
    }

    func loadChats() async {
        guard let api = apiService else { return }
        isLoadingChats = true

        do {
            let dtos = try await api.fetchChats()
            let loaded = dtos.map { dto -> Conversation in
                Conversation(
                    id: dto.id,
                    title: dto.title ?? dto.firstMessage?.truncated(to: 50) ?? "Chat",
                    messages: [],
                    model: dto.model ?? selectedModel.id,
                    createdAt: dto.createdAt.flatMap(Date.fromISO8601) ?? Date()
                )
            }
            // Merge: keep cached messages for conversations that were already loaded
            let mergedIds = Set(conversations.map(\.id))
            let merged = loaded.map { conv -> Conversation in
                if let cached = conversations.first(where: { $0.id == conv.id }), !cached.messages.isEmpty {
                    return Conversation(id: conv.id, title: conv.title,
                                        messages: cached.messages, model: conv.model, createdAt: conv.createdAt)
                }
                return conv
            }
            let localOnly = conversations.filter { !mergedIds.contains($0.id) }
            conversations = merged + localOnly
            cacheConversations(loaded)
        } catch {
            // Don't surface load errors — user can still create new chats
            print("[ChatManager] loadChats error: \(error)")
        }

        isLoadingChats = false
    }

    func loadModels() async {
        guard let api = apiService else { return }

        do {
            let dtos = try await api.fetchModels()
            guard !dtos.isEmpty else { return }

            availableModels = dtos.map { dto in
                LLMModel(id: dto.id, name: dto.name, provider: dto.provider ?? dto.id)
            }

            // Keep selected model valid
            if !availableModels.contains(where: { $0.id == selectedModel.id }),
               let first = availableModels.first {
                selectedModel = first
            }
        } catch {
            // Fallback to hardcoded defaults already in place
            print("[ChatManager] loadModels error: \(error)")
        }
    }

    func loadMCPServers() async {
        guard let api = apiService else { return }

        async let allServers = api.fetchAllMCPServers()
        async let userServers = api.fetchUserMCPServers()

        do {
            let (all, user) = try await (allServers, userServers)
            let subscribedIds = Set(user.map(\.id))
            subscribedMCPServerIds = subscribedIds

            availableMCPServers = all.map { dto in
                MCPServer(id: dto.id, name: dto.name, url: dto.resolvedURL, description: dto.description)
            }
        } catch {
            print("[ChatManager] loadMCPServers error: \(error)")
        }
    }

    func loadRateLimit() async {
        guard let api = apiService else { return }

        do {
            let dto = try await api.fetchRateLimit()
            rateLimit = RateLimitInfo(
                planName: dto.stats?.planName ?? "—",
                dailyUsed: dto.stats?.dailyTokensUsed ?? 0,
                dailyLimit: dto.stats?.dailyTokensLimit ?? 0,
                monthlyUsed: dto.stats?.monthlyTokensUsed ?? 0,
                monthlyLimit: dto.stats?.monthlyTokensLimit ?? 0,
                isBlocked: dto.isBlocked ?? false,
                blockReason: dto.blockReason,
                resetInSeconds: dto.resetInSeconds ?? 0
            )
        } catch {
            print("[ChatManager] loadRateLimit error: \(error)")
        }
    }

    private func loadGreeting() async {
        guard let api = apiService else { return }

        do {
            let dto = try await api.fetchGreetings()
            let text = dto.displayGreeting
            if !text.isEmpty { greeting = text }
        } catch {
            // Non-critical
        }
    }

    // MARK: - Message History

    /// Loads full message history for a conversation from the API (lazy on selection).
    func loadMessages(for conversationId: String) async {
        guard let api = apiService,
              let idx = conversations.firstIndex(where: { $0.id == conversationId }),
              conversations[idx].messages.isEmpty else { return }

        do {
            let dtos = try await api.fetchChatMessages(chatId: conversationId)
            let messages = dtos.map { dto -> ChatMessage in
                ChatMessage(
                    id: dto.id ?? UUID().uuidString,
                    role: MessageRole(rawValue: dto.normalizedRoleString) ?? .user,
                    content: dto.content,
                    timestamp: dto.createdAt.flatMap(Date.fromISO8601) ?? Date()
                )
            }
            conversations[idx].messages = messages
            if currentConversation?.id == conversationId {
                currentConversation = conversations[idx]
            }
            cacheMessages(messages, for: conversationId)
        } catch {
            // Offline fallback: show whatever is cached
            if conversations[idx].messages.isEmpty {
                let convId = conversationId
                let desc = FetchDescriptor<PersistedConversation>(predicate: #Predicate { $0.id == convId })
                if let persisted = try? modelContext?.fetch(desc).first, !persisted.messages.isEmpty {
                    let cached = persisted.messages
                        .sorted(by: { $0.timestamp < $1.timestamp })
                        .compactMap { ChatMessage(from: $0) }
                    conversations[idx].messages = cached
                    if currentConversation?.id == conversationId {
                        currentConversation = conversations[idx]
                    }
                }
            }
            print("[ChatManager] loadMessages error: \(error)")
        }
    }

    // MARK: - Conversations

    func newConversation(focus: Bool = true) {
        // Create a draft only — it is NOT added to history until the first
        // message is sent (see sendMessage → upsertConversation). This keeps
        // empty "New Chat" entries out of the sidebar when the user taps New
        // Chat without typing anything (ChatGPT-style).
        currentConversation = Conversation(
            id: UUID().uuidString,
            title: "New Chat",
            messages: [],
            model: selectedModel.id,
            createdAt: Date()
        )
        if focus { shouldAutoFocusInput = true }
    }

    func selectConversation(_ conversation: Conversation) {
        Haptic.selection()
        shouldAutoFocusInput = false
        currentConversation = conversation
        Task { await loadMessages(for: conversation.id) }
    }

    func deleteConversation(_ conversation: Conversation) {
        Haptic.impact(.rigid)
        conversations.removeAll { $0.id == conversation.id }
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }
        deleteFromCache(conversation)
    }

    // MARK: - Messaging

    func sendMessage(_ text: String, fileUrl: String? = nil) async {
        guard !text.isBlank, !isStreaming else { return }
        Haptic.impact(.medium)   // message sent

        // Refresh the session *before* touching the conversation. If it has
        // expired, AuthManager routes the app back to sign-in — so we bail out
        // instead of appending a doomed message and then surfacing an "LLM error".
        guard await ensureFreshSession() else { return }

        if currentConversation == nil { newConversation(focus: false) }
        guard var conversation = currentConversation else { return }

        let isFirstMessage = conversation.messages.isEmpty

        // Append user message
        let userMessage = ChatMessage(role: .user, content: text)
        conversation.messages.append(userMessage)

        // Append empty assistant placeholder
        var assistantMessage = ChatMessage(role: .assistant, content: "")
        conversation.messages.append(assistantMessage)

        // Show truncated prompt immediately so sidebar isn't blank while API generates a real title.
        if isFirstMessage { conversation.title = text.truncated(to: 50) }
        currentConversation = conversation
        // Insert the draft into history now that it has its first message.
        upsertConversation(conversation)

        // Persist user message server-side (best-effort, non-blocking)
        if let api = apiService {
            Task {
                try? await api.persistMessage(chatId: conversation.id, role: "user", content: text)
            }
        }

        let request = ChatRequest(
            chatId: conversation.id,
            prompt: text,
            model: selectedModel.id,
            isNewChat: isFirstMessage,
            mcpServerName: selectedMCPServer?.name,
            mcpServerURL: selectedMCPServer?.url,
            thinkingMode: thinkingMode.rawValue,
            modelExplicit: userPickedModel,
            fileUrl: fileUrl,
            agentName: agentNameForSelectedServer
        )

        isStreaming = true
        error = nil

        streamingTask = Task {
            var finalContent = ""
            var wasRateLimited = false
            do {
                for try await event in service.sendMessage(request) {
                    switch event {
                    case .streamStart:
                        break

                    case .chunk(let content, _, _):
                        finalContent += content
                        assistantMessage = ChatMessage(
                            id: assistantMessage.id,
                            role: .assistant,
                            content: finalContent,
                            timestamp: assistantMessage.timestamp
                        )
                        updateLastMessage(assistantMessage, in: conversation.id)

                    case .streamEnd(_, let full, _):
                        if !full.isEmpty { finalContent = full }
                        assistantMessage = ChatMessage(
                            id: assistantMessage.id,
                            role: .assistant,
                            content: finalContent,
                            timestamp: assistantMessage.timestamp
                        )
                        updateLastMessage(assistantMessage, in: conversation.id)
                        Haptic.impact(.light)   // response complete

                        // Persist AI message (best-effort)
                        if let api = apiService, !finalContent.isEmpty {
                            Task {
                                try? await api.persistMessage(
                                    chatId: conversation.id,
                                    role: "AI",
                                    content: finalContent
                                )
                            }
                        }

                    case .heartbeat:
                        break

                    case .error(let message, _):
                        self.error = message

                    case .rateLimited(let period, let resetInSeconds):
                        // Remove the empty assistant placeholder — keep the user message visible.
                        if var conv = currentConversation,
                           !conv.messages.isEmpty,
                           conv.messages.last?.role == .assistant,
                           conv.messages.last?.content.isEmpty == true {
                            conv.messages.removeLast()
                            currentConversation = conv
                            updateConversation(conv)
                        }
                        wasRateLimited = true
                        rateLimitEventPeriod = period
                        rateLimitEventResetSeconds = resetInSeconds
                        // Show modal immediately with event data; API refresh enhances it
                        showRateLimitModal = true
                        Task { await loadRateLimit() }
                    }
                }
            } catch is CancellationError {
                // User stopped the stream — not an error.
            } catch ChatServiceError.unauthorized {
                // Token was rejected mid-stream (expired/revoked). Route to
                // sign-in rather than showing a generic error popup.
                authManager?.expireSession()
            } catch {
                self.error = error.localizedDescription
            }

            // The stream ended without any text and without an explicit error
            // (e.g. the backend returned an empty completion). Don't leave a
            // blank assistant bubble with nothing shown — surface a clear,
            // retryable message. Skipped on user-stop and on session expiry.
            if !Task.isCancelled,
               !wasRateLimited,
               finalContent.isEmpty,
               self.error == nil,
               authManager?.isAuthenticated != false {
                assistantMessage = ChatMessage(
                    id: assistantMessage.id,
                    role: .assistant,
                    content: "I couldn't generate a response for that. Please try rephrasing or send it again.",
                    timestamp: assistantMessage.timestamp
                )
                updateLastMessage(assistantMessage, in: conversation.id)
            }

            isStreaming = false

            // Now that the chat exists on the server (stream_start has fired),
            // call the title API. This avoids a 404 when the POST /title fires
            // before the backend has created the chat record.
            if isFirstMessage {
                updateConversationTitle(conversation.id, from: text)
            }

            // Persist the completed exchange locally
            if let conv = currentConversation {
                cacheConversations([conv])
                cacheMessages(conv.messages, for: conv.id)
            }
        }
    }

    /// Maps the selected MCP server to a backend agent name.
    /// Convention: strip the "-mcp" suffix (e.g. "abaper-mcp" → "abaper").
    private var agentNameForSelectedServer: String? {
        guard let server = selectedMCPServer else { return nil }
        if server.name.hasSuffix("-mcp") {
            return String(server.name.dropLast(4))
        }
        return server.name
    }

    func uploadAttachment(data: Data, filename: String, mimeType: String) async throws -> String? {
        guard let api = apiService else { throw ChatServiceError.notConnected }
        return try await api.uploadFile(data: data, filename: filename, mimeType: mimeType)
    }

    func stopStreaming() async {
        guard isStreaming, let conversation = currentConversation else { return }

        streamingTask?.cancel()
        streamingTask = nil

        do {
            try await service.stopStreaming(chatId: conversation.id)
        } catch {
            // Ignore
        }

        isStreaming = false
    }

    // MARK: - Private Helpers

    private func updateConversation(_ conversation: Conversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        }
    }

    /// Updates the conversation in place, or inserts it at the top of history
    /// if it isn't there yet (used when a draft sends its first message).
    private func upsertConversation(_ conversation: Conversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
    }

    private func updateLastMessage(_ message: ChatMessage, in conversationId: String) {
        guard var conversation = conversations.first(where: { $0.id == conversationId }),
              !conversation.messages.isEmpty else { return }

        conversation.messages[conversation.messages.count - 1] = message
        updateConversation(conversation)

        if currentConversation?.id == conversationId {
            currentConversation = conversation
        }
    }

    private func updateConversationTitle(_ conversationId: String, from prompt: String) {
        Task {
            let title: String
            if let api = apiService {
                do {
                    title = try await api.generateTitle(chatId: conversationId, message: prompt)
                } catch {
                    title = prompt.truncated(to: 50)
                }
            } else {
                title = prompt.truncated(to: 50)
            }

            guard var conversation = conversations.first(where: { $0.id == conversationId }) else { return }
            conversation.title = title
            updateConversation(conversation)
            if currentConversation?.id == conversationId {
                currentConversation = conversation
            }
            cacheUpdateTitle(title, for: conversationId)
        }
    }

    // MARK: - SwiftData persistence

    /// Call once from CAIApp after ModelContainer is ready.
    func configureStorage(_ context: ModelContext) {
        modelContext = context
        loadCachedConversations()
    }

    /// Pre-populates the sidebar from the local cache before the API responds.
    private func loadCachedConversations() {
        guard let ctx = modelContext else { return }
        var desc = FetchDescriptor<PersistedConversation>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        desc.fetchLimit = 200
        guard let cached = try? ctx.fetch(desc), !cached.isEmpty else { return }
        conversations = cached.map { Conversation(from: $0) }
    }

    /// Upserts conversation metadata (title, model) — does not touch messages.
    private func cacheConversations(_ convs: [Conversation]) {
        guard let ctx = modelContext else { return }
        for conv in convs {
            let id = conv.id
            let desc = FetchDescriptor<PersistedConversation>(predicate: #Predicate { $0.id == id })
            if let existing = try? ctx.fetch(desc).first {
                existing.title = conv.title
                existing.model = conv.model
            } else {
                ctx.insert(PersistedConversation(id: conv.id, title: conv.title,
                                                  model: conv.model, createdAt: conv.createdAt))
            }
        }
        try? ctx.save()
    }

    /// Upserts messages for a conversation — adds new ones without duplicating.
    private func cacheMessages(_ messages: [ChatMessage], for conversationId: String) {
        guard let ctx = modelContext else { return }
        let convId = conversationId
        let convDesc = FetchDescriptor<PersistedConversation>(predicate: #Predicate { $0.id == convId })
        guard let persisted = try? ctx.fetch(convDesc).first else { return }
        let existingIds = Set(persisted.messages.map(\.id))
        for msg in messages where !existingIds.contains(msg.id) {
            let pm = PersistedMessage(id: msg.id, conversationId: conversationId,
                                      roleRaw: msg.role.rawValue, content: msg.content,
                                      timestamp: msg.timestamp)
            pm.conversation = persisted
            ctx.insert(pm)
        }
        try? ctx.save()
    }

    private func cacheUpdateTitle(_ title: String, for conversationId: String) {
        guard let ctx = modelContext else { return }
        let id = conversationId
        let desc = FetchDescriptor<PersistedConversation>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(desc).first {
            existing.title = title
            try? ctx.save()
        }
    }

    private func deleteFromCache(_ conversation: Conversation) {
        guard let ctx = modelContext else { return }
        let id = conversation.id
        let desc = FetchDescriptor<PersistedConversation>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(desc).first {
            ctx.delete(existing)
            try? ctx.save()
        }
    }
}

// MARK: - Supporting Models

struct Conversation: Identifiable, Equatable {
    let id: String
    var title: String
    var messages: [ChatMessage]
    var model: String
    let createdAt: Date

    static func == (lhs: Conversation, rhs: Conversation) -> Bool { lhs.id == rhs.id }

    /// Markdown export of the whole transcript for the iOS share sheet.
    var markdownExport: String {
        var out = "# \(title)\n\n"
        for message in messages where !message.content.isEmpty {
            let who = message.role == .user ? "You" : "BlueFunda AI"
            out += "**\(who):** \(message.content)\n\n"
        }
        return out
    }

}

extension Conversation {
    init(from persisted: PersistedConversation) {
        self.id = persisted.id
        self.title = persisted.title
        self.model = persisted.model
        self.createdAt = persisted.createdAt
        self.messages = persisted.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .compactMap { ChatMessage(from: $0) }
    }
}

// Reasoning effort, mirrors the cai web app's thinking-mode selector.
enum ThinkingMode: String, CaseIterable, Identifiable {
    case auto
    case quick
    case deep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:  return "Auto"
        case .quick: return "Quick Response"
        case .deep:  return "Think Deeper"
        }
    }

    var detail: String {
        switch self {
        case .auto:  return "Balanced speed and quality"
        case .quick: return "Answers right away"
        case .deep:  return "Thinks longer for better answers"
        }
    }

    var icon: String {
        switch self {
        case .auto:  return "wand.and.stars"
        case .quick: return "bolt"
        case .deep:  return "brain"
        }
    }
}

struct LLMModel: Identifiable, Hashable {
    let id: String
    let name: String
    let provider: String

    static let defaultModel = LLMModel(id: "deepseek", name: "DeepSeek", provider: "DeepSeek")

    static let defaultModels: [LLMModel] = [
        LLMModel(id: "deepseek",  name: "DeepSeek",  provider: "DeepSeek"),
        LLMModel(id: "gemini",    name: "Gemini",    provider: "Gemini"),
        LLMModel(id: "anthropic", name: "Anthropic", provider: "Anthropic"),
        LLMModel(id: "llama",     name: "Llama",     provider: "Groq"),
        LLMModel(id: "sarvam",    name: "Sarvam",    provider: "Sarvam"),
        LLMModel(id: "openai",    name: "OpenAI",    provider: "OpenAI"),
    ]
}

struct MCPServer: Identifiable, Hashable {
    let id: String
    let name: String        // technical ID sent to backend (e.g. "abaper-mcp")
    let url: String
    let description: String?

    /// User-facing label: shortDescription from BFF when set, otherwise the
    /// technical name cleaned up (strip "-mcp", title-case each word).
    var displayName: String {
        if let d = description, !d.isEmpty { return d }
        return name
            .replacingOccurrences(of: "-mcp", with: "")
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

enum RateLimitStatus {
    case normal
    case warning   // daily >= 80%
    case exceeded  // daily >= 100%
    case blocked
}

struct RateLimitInfo {
    let planName: String
    let dailyUsed: Int
    let dailyLimit: Int
    let monthlyUsed: Int
    let monthlyLimit: Int
    let isBlocked: Bool
    let blockReason: String?
    let resetInSeconds: Int

    var dailyPercent: Double {
        guard dailyLimit > 0 else { return 0 }
        return min(Double(dailyUsed) / Double(dailyLimit), 1.0)
    }

    var monthlyPercent: Double {
        guard monthlyLimit > 0 else { return 0 }
        return min(Double(monthlyUsed) / Double(monthlyLimit), 1.0)
    }

    var resetLabel: String {
        let s = resetInSeconds
        guard s > 0 else { return "midnight" }
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        if d > 0 && h > 0 { return "\(d)d \(h)h" }
        if d > 0 { return "\(d)d" }
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    var status: RateLimitStatus {
        if isBlocked { return .blocked }
        if dailyPercent >= 1.0 || monthlyPercent >= 1.0 { return .exceeded }
        if dailyPercent >= 0.8 || monthlyPercent >= 0.8 { return .warning }
        return .normal
    }
}
