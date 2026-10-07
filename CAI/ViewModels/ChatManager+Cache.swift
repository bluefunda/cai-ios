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

    /// Removes cached chats the server no longer lists (deleted on another device, or cached from a
    /// different backend). The cache only ever grew, so those reappeared at every launch until the
    /// server's list replaced them a few seconds later.
    func pruneCachedConversations(keeping ids: Set<String>) {
        guard let ctx = modelContext else { return }
        guard let cached = try? ctx.fetch(FetchDescriptor<PersistedConversation>()) else { return }
        for conversation in cached where !ids.contains(conversation.id) {
            for message in conversation.messages { ctx.delete(message) }
            ctx.delete(conversation)
        }
        try? ctx.save()
    }

    /// Not `private`: also called from `ChatManager.swift` proper.
    /// Mirrors the conversation's complete message list into the cache (both callers pass the
    /// full list: a history load, and a finished reply). It used to only ever ADD messages, so when
    /// the server's copy (server id) replaced the one sent from this device (local id), both stayed
    /// cached — reopening the chat showed the prompt twice until the server copy replaced it.
    func cacheMessages(_ messages: [ChatMessage], for conversationId: String) {
        guard let ctx = modelContext else { return }
        let convId = conversationId
        let convDesc = FetchDescriptor<PersistedConversation>(predicate: #Predicate { $0.id == convId })
        guard let persisted = try? ctx.fetch(convDesc).first else { return }
        let keepIds = Set(messages.map(\.id))
        for stale in persisted.messages where !keepIds.contains(stale.id) {
            ctx.delete(stale)
        }
        let cachedById = Dictionary(persisted.messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for msg in messages {
            let stepsJSON = msg.steps.flatMap { steps in
                (try? JSONEncoder().encode(steps)).flatMap { String(data: $0, encoding: .utf8) }
            }
            if let cached = cachedById[msg.id], keepIds.contains(cached.id) {
                // Keep a finished reply's thinking record current (it may have arrived after
                // the message was first cached).
                if stepsJSON != nil { cached.stepsJSON = stepsJSON }
                if let seconds = msg.thinkingDurationSeconds { cached.thinkingDurationSeconds = seconds }
                continue
            }
            let pm = PersistedMessage(id: msg.id, conversationId: conversationId,
                                      roleRaw: msg.role.rawValue, content: msg.content,
                                      timestamp: msg.timestamp, persona: msg.persona,
                                      stepsJSON: stepsJSON,
                                      thinkingDurationSeconds: msg.thinkingDurationSeconds)
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
    /// Wipes every locally cached conversation and message. Called on sign-out: the cache
    /// isn't scoped to a user, realm or server, so without this the next sign-in (another
    /// account, a migrated Keycloak realm/org, or a different backend) was shown the previous
    /// session's chats, and loadMessages' "keep local copy on an empty server response" guard
    /// kept displaying their messages too.
    func clearCache() {
        guard let ctx = modelContext else { return }
        // Explicit per-model deletes: a batch delete doesn't apply the relationship's
        // cascade rule, so messages are removed directly rather than relied on to follow.
        try? ctx.delete(model: PersistedMessage.self)
        try? ctx.delete(model: PersistedConversation.self)
        try? ctx.save()
    }

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
