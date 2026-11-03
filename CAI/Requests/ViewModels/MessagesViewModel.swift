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
    /// Uploads and opens message attachments — the same file store as comment attachments.
    let attachmentService: AttachmentServicing?

    init(service: MessagesServicing, currentUserId: String?, attachmentService: AttachmentServicing? = nil) {
        self.service = service
        self.currentUserId = currentUserId
        self.attachmentService = attachmentService
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
        ConversationViewModel(conversation: conversation, service: service, currentUserId: currentUserId,
                              attachmentService: attachmentService)
    }
}

// MARK: - New Conversation

/// The web's New message drawer (createNewChat.js): pick recipients from the tenant's
/// active users, a topic, and a first message.
@MainActor
final class NewConversationViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var matches: [RQAdminUser] = []
    @Published private(set) var recipients: [RQAdminUser] = []
    @Published var topic = ""
    @Published var message = ""
    @Published private(set) var isSearching = false
    @Published private(set) var isSending = false
    @Published var error: String?

    /// Set once POST /discussions succeeds, so a retry after the first message fails
    /// re-sends only the message instead of creating a second conversation.
    @Published private(set) var createdConversationId: String?

    private let messagesService: MessagesServicing
    private let searchUsers: (String) async throws -> [RQAdminUser]
    private let currentUserId: String?

    init(messagesService: MessagesServicing,
         searchUsers: @escaping (String) async throws -> [RQAdminUser],
         currentUserId: String?) {
        self.messagesService = messagesService
        self.searchUsers = searchUsers
        self.currentUserId = currentUserId
    }

    var canSend: Bool {
        !isSending && !recipients.isEmpty
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Active users matching `searchText`, minus the current user and anyone already added.
    func search() async {
        isSearching = true
        defer { isSearching = false }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        do {
            let found = try await searchUsers(query)
            // A slower, older search must not overwrite a newer one's results.
            guard query == searchText.trimmingCharacters(in: .whitespaces) else { return }
            let chosen = Set(recipients.map(\.id))
            matches = found.filter { $0.id != currentUserId && !chosen.contains($0.id) }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    func add(_ user: RQAdminUser) {
        guard !recipients.contains(user) else { return }
        recipients.append(user)
        matches.removeAll { $0.id == user.id }
    }

    /// Recipients can't change once the conversation exists (only the message is retried).
    func remove(_ user: RQAdminUser) {
        guard createdConversationId == nil else { return }
        recipients.removeAll { $0.id == user.id }
    }

    /// The new conversation's id, or nil (with `error` set) if it couldn't be created.
    func send() async -> String? {
        guard canSend else { return nil }
        isSending = true
        error = nil
        defer { isSending = false }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let conversationId: String
            if let existing = createdConversationId {
                conversationId = existing
            } else {
                conversationId = try await messagesService.createConversation(
                    topic: title.isEmpty ? String(text.prefix(80)) : title,
                    recipientIds: recipients.map(\.id)
                )
                createdConversationId = conversationId
            }
            try await messagesService.send(text, conversationId: conversationId)
            return conversationId
        } catch {
            self.error = createdConversationId == nil
                ? error.localizedDescription
                : "The conversation was created but the message didn't send. Press Send to try again."
            return nil
        }
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
    /// Uploaded and waiting to go with the next message, as the web's chat box holds them.
    @Published private(set) var pendingAttachments: [RQAttachment] = []
    @Published private(set) var isUploadingAttachment = false

    let conversation: RQConversation
    let currentUserId: String?
    private let service: MessagesServicing
    private let attachmentService: AttachmentServicing?

    static let batchSize = 30

    init(conversation: RQConversation, service: MessagesServicing, currentUserId: String?,
         attachmentService: AttachmentServicing? = nil) {
        self.conversation = conversation
        self.service = service
        self.currentUserId = currentUserId
        self.attachmentService = attachmentService
    }

    var canAttach: Bool { attachmentService != nil && !isUploadingAttachment && !isSending }

    var canSend: Bool {
        !isSending && !isUploadingAttachment
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
    }

    func attach(fileURL: URL) async {
        guard let attachmentService else { return }
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }
        do {
            pendingAttachments.append(try await attachmentService.upload(fileURL: fileURL))
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removePending(_ attachment: RQAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func download(_ attachment: RQAttachment) async throws -> (data: Data, mimeType: String?, fileName: String) {
        guard let attachmentService else { throw RequestsAPIError.invalidURL }
        return try await attachmentService.download(id: attachment.id)
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
        guard canSend else { return }
        isSending = true
        error = nil
        do {
            try await service.send(text, attachments: pendingAttachments, conversationId: conversation.id)
            draft = ""
            pendingAttachments = []
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
