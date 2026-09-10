import Foundation
import SwiftData

// MARK: - SwiftData persistence
// Split from the main ChatManager body to stay under SwiftLint's
// file_length limit, same as ChatManager+FileHistory.swift et al.
extension ChatManager {
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
    /// Not `private`: also called from `ChatManager.swift` proper.
    func cacheConversations(_ convs: [Conversation]) {
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
    /// Not `private`: also called from `ChatManager.swift` proper.
    func cacheMessages(_ messages: [ChatMessage], for conversationId: String) {
        guard let ctx = modelContext else { return }
        let convId = conversationId
        let convDesc = FetchDescriptor<PersistedConversation>(predicate: #Predicate { $0.id == convId })
        guard let persisted = try? ctx.fetch(convDesc).first else { return }
        let existingIds = Set(persisted.messages.map(\.id))
        for msg in messages where !existingIds.contains(msg.id) {
            let pm = PersistedMessage(id: msg.id, conversationId: conversationId,
                                      roleRaw: msg.role.rawValue, content: msg.content,
                                      timestamp: msg.timestamp, persona: msg.persona)
            pm.conversation = persisted
            ctx.insert(pm)
        }
        try? ctx.save()
    }

    /// Not `private`: also called from `retryStuckTitles` in `ChatManager+FileHistory.swift`.
    func cacheUpdateTitle(_ title: String, for conversationId: String) {
        guard let ctx = modelContext else { return }
        let id = conversationId
        let desc = FetchDescriptor<PersistedConversation>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(desc).first {
            existing.title = title
            try? ctx.save()
        }
    }

    /// Not `private`: also called from `ChatManager.swift` proper.
    func deleteFromCache(_ conversation: Conversation) {
        guard let ctx = modelContext else { return }
        let id = conversation.id
        let desc = FetchDescriptor<PersistedConversation>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(desc).first {
            ctx.delete(existing)
            try? ctx.save()
        }
    }
}
