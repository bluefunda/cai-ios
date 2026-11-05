import Foundation

// MARK: - Messages List

@MainActor
final class MessagesListViewModel: ObservableObject {
    @Published private(set) var conversations: [RQConversation] = []
    @Published private(set) var isLoading = false
    /// True once a load has finished — see TeamsListViewModel.hasLoaded.
    @Published private(set) var hasLoaded = false
    @Published var searchText = ""
    @Published var error: String?

    let service: MessagesServicing
    let currentUserId: String?

    init(service: MessagesServicing, currentUserId: String?) {
        self.service = service
        self.currentUserId = currentUserId
    }

    var filteredConversations: [RQConversation] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return conversations }
        return conversations.filter { conversation in
            conversation.topic.lowercased().contains(query)
                || conversation.participants.contains { $0.name.lowercased().contains(query) }
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            let loaded = try await service.listConversations()
            conversations = loaded.sorted { lhs, rhs in
                let left: Date = lhs.lastMessage?.createdAt ?? .distantPast
                let right: Date = rhs.lastMessage?.createdAt ?? .distantPast
                return left > right
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true
    }

    func makeConversationModel(for conversation: RQConversation) -> ConversationViewModel {
        ConversationViewModel(conversation: conversation, service: service, currentUserId: currentUserId)
    }
}

// MARK: - Conversation

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published private(set) var messages: [RQMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingEarlier = false
    @Published private(set) var hasEarlier = false
    @Published private(set) var isSending = false
    @Published var draft = ""
    @Published var error: String?

    let conversation: RQConversation
    let currentUserId: String?
    private let service: MessagesServicing

    static let batchSize = 30

    init(conversation: RQConversation, service: MessagesServicing, currentUserId: String?) {
        self.conversation = conversation
        self.service = service
        self.currentUserId = currentUserId
    }

    var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isMine(_ message: RQMessage) -> Bool {
        message.senderId == currentUserId
    }

    /// The latest page, then marks the conversation seen (as the web app does on open).
    func load() async {
        isLoading = true
        error = nil
        do {
            let page = try await service.messages(conversationId: conversation.id, before: nil,
                                                 batchSize: Self.batchSize)
            merge(page)
            hasEarlier = page.count >= Self.batchSize
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        try? await service.markSeen(conversationId: conversation.id)
    }

    /// The page before the oldest message shown.
    func loadEarlier() async {
        guard hasEarlier, !isLoadingEarlier, let oldest = messages.first?.createdAtRaw else { return }
        isLoadingEarlier = true
        do {
            let countBefore = messages.count
            let page = try await service.messages(conversationId: conversation.id, before: oldest,
                                                 batchSize: Self.batchSize)
            merge(page)
            hasEarlier = messages.count > countBefore && page.count >= Self.batchSize
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingEarlier = false
    }

    /// New messages since the latest one shown — after sending, and while the screen is open.
    func refreshLatest() async {
        guard let page = try? await service.messages(conversationId: conversation.id, before: nil,
                                                    batchSize: Self.batchSize) else { return }
        let countBefore = messages.count
        merge(page)
        if messages.count > countBefore {
            try? await service.markSeen(conversationId: conversation.id)
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        error = nil
        do {
            try await service.send(text, conversationId: conversation.id)
            draft = ""
            await refreshLatest()
        } catch {
            self.error = error.localizedDescription
        }
        isSending = false
    }

    /// Pages overlap — the backend's page is inclusive of its boundary timestamp — so messages
    /// are merged by id and kept oldest first (trm#155's duplicates came from appending).
    private func merge(_ page: [RQMessage]) {
        var byId = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for message in page { byId[message.id] = message }
        messages = byId.values.sorted { lhs, rhs in
            let left: Date = lhs.createdAt ?? .distantPast
            let right: Date = rhs.createdAt ?? .distantPast
            return left == right ? lhs.id < rhs.id : left < right
        }
    }
}
