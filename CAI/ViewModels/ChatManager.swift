import Foundation

// MARK: - Chat Manager
// Coordinates between UI, streaming chat service (BFFChatService), and REST API service (BFFAPIService).

@MainActor
final class ChatManager: ObservableObject {

    // MARK: - Published State

    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var isStreaming = false
    @Published var isLoadingChats = false
    @Published var error: String?
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

    @Published var availableModels: [LLMModel] = LLMModel.defaultModels
    @Published var availableMCPServers: [MCPServer] = []
    @Published var subscribedMCPServerIds: Set<String> = []

    @Published var rateLimit: RateLimitInfo?
    @Published var greeting: String = ""

    // MARK: - Private

    private let service: ChatServiceProtocol
    var apiService: BFFAPIService?
    private var streamingTask: Task<Void, Never>?
    /// Latest access token — updated by CAIApp whenever AuthManager refreshes.
    private var currentBFFToken: String = ""

    // MARK: - Init

    init(service: ChatServiceProtocol) {
        self.service = service
    }

    // Called once by CAIApp to hand off the initial token and set up BFFAPIService.
    func bind(authManager: AuthManager) {
        // No-op; kept for API compatibility if needed later.
        // Token updates come via updateToken(_:).
    }

    /// Update the stored access token (called from CAIApp on auth state changes).
    func updateToken(_ token: String) {
        currentBFFToken = token
    }

    // MARK: - Connection

    func connect(credentials: ServiceCredentials) async {
        currentBFFToken = credentials.accessToken

        do {
            connectionStatus = .connecting
            try await service.connect(credentials: credentials)
            connectionStatus = .connected

            // Wire up REST API service; token provider reads the latest stored token.
            if let bffURL = credentials.bffBaseURL {
                apiService = BFFAPIService(baseURL: bffURL, tokenProvider: { [weak self] in
                    let token = await MainActor.run { self?.currentBFFToken ?? "" }
                    guard !token.isEmpty else { throw APIError.unauthorized }
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
            // Merge server-side chats with any in-memory ones not yet persisted
            let existingIds = Set(loaded.map(\.id))
            let localOnly = conversations.filter { !existingIds.contains($0.id) }
            conversations = loaded + localOnly
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
                planName: dto.planName ?? "—",
                dailyUsed: dto.dailyTokensUsed ?? 0,
                dailyLimit: dto.dailyTokensLimit ?? 0,
                monthlyUsed: dto.monthlyTokensUsed ?? 0,
                monthlyLimit: dto.monthlyTokensLimit ?? 0,
                isBlocked: dto.isBlocked ?? false,
                blockReason: dto.blockReason
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
        } catch {
            print("[ChatManager] loadMessages error: \(error)")
        }
    }

    // MARK: - Conversations

    func newConversation() {
        let conversation = Conversation(
            id: UUID().uuidString,
            title: "New Chat",
            messages: [],
            model: selectedModel.id,
            createdAt: Date()
        )
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
    }

    func selectConversation(_ conversation: Conversation) {
        currentConversation = conversation
        Task { await loadMessages(for: conversation.id) }
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }
    }

    // MARK: - Messaging

    func sendMessage(_ text: String) async {
        guard !text.isBlank, !isStreaming else { return }

        if currentConversation == nil { newConversation() }
        guard var conversation = currentConversation else { return }

        let isFirstMessage = conversation.messages.isEmpty

        // Append user message
        let userMessage = ChatMessage(role: .user, content: text)
        conversation.messages.append(userMessage)

        // Append empty assistant placeholder
        var assistantMessage = ChatMessage(role: .assistant, content: "")
        conversation.messages.append(assistantMessage)

        currentConversation = conversation
        updateConversation(conversation)

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
            thinkingMode: thinkingMode.rawValue
        )

        isStreaming = true
        error = nil

        streamingTask = Task {
            var finalContent = ""
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

                        // Generate title after first exchange
                        if isFirstMessage {
                            updateConversationTitle(conversation.id, from: text)
                        }

                    case .heartbeat:
                        break

                    case .error(let message, _):
                        self.error = message
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }

            isStreaming = false
        }
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

    static let defaultModel = LLMModel(id: "groq", name: "Groq (Llama 3.3 70B)", provider: "Groq")

    static let defaultModels: [LLMModel] = [
        LLMModel(id: "groq", name: "Groq (Llama 3.3 70B)", provider: "Groq"),
        LLMModel(id: "openai", name: "OpenAI GPT-4o", provider: "OpenAI"),
        LLMModel(id: "deepseek", name: "DeepSeek Chat", provider: "DeepSeek"),
    ]
}

struct MCPServer: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let description: String?
}

struct RateLimitInfo {
    let planName: String
    let dailyUsed: Int
    let dailyLimit: Int
    let monthlyUsed: Int
    let monthlyLimit: Int
    let isBlocked: Bool
    let blockReason: String?

    var dailyPercent: Double {
        guard dailyLimit > 0 else { return 0 }
        return min(Double(dailyUsed) / Double(dailyLimit), 1.0)
    }

    var monthlyPercent: Double {
        guard monthlyLimit > 0 else { return 0 }
        return min(Double(monthlyUsed) / Double(monthlyLimit), 1.0)
    }
}
