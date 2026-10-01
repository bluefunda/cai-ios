import Foundation
import SwiftData

extension ChatManager {
    // MARK: - Message History

    /// Loads full message history for a conversation from the API (lazy on selection).
    /// - Parameter force: Bypasses the "only fetch if empty" guard — used by
    ///   `reconcileAfterBackground()` to pull the authoritative server copy
    ///   over locally-cached messages after a stream was interrupted.
    func loadMessages(for conversationId: String, force: Bool = false) async {
        guard let api = apiService,
              let startIdx = conversations.firstIndex(where: { $0.id == conversationId }),
              force || !conversations[startIdx].messagesLoaded else {
            // Already loaded (or unknown) — no fetch will conclude to clear the switching cover.
            // A non-empty chat's scroll-settle task clears it; an empty one has nothing to settle.
            if currentConversation?.id == conversationId, currentConversation?.messages.isEmpty ?? true {
                isSwitchingConversation = false
            }
            return
        }

        do {
            let dtos = try await api.fetchChatMessages(chatId: conversationId)
            // Re-resolve after the await: loadChats() can rebuild/reorder `conversations`
            // mid-fetch, so an index captured before it may now point at a different chat.
            guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else {
                if currentConversation?.id == conversationId { isSwitchingConversation = false }
                return
            }
            let messages = dtos.map { dto -> ChatMessage in
                ChatMessage(
                    id: dto.id ?? UUID().uuidString,
                    role: MessageRole(rawValue: dto.normalizedRoleString) ?? .user,
                    content: dto.content,
                    timestamp: dto.createdAt.flatMap(Date.fromISO8601) ?? Date(),
                    fileUrl: dto.fileUrl,
                    fileMetadata: dto.fileMetadata?.map(MessageFileMetadata.init(from:)),
                    persona: dto.persona
                )
            }
            // Never let an empty server response wipe messages already on screen (restored
            // from the local cache, or just streamed) — that read as a valid chat rendering
            // for a moment and then flipping to "No messages found". Leave it un-confirmed so
            // a later open fetches again instead.
            if messages.isEmpty && !conversations[idx].messages.isEmpty {
                print("[ChatManager] loadMessages: server returned no messages for \(conversationId); keeping local copy")
            } else {
                conversations[idx].messages = messages
                conversations[idx].messagesLoaded = true
                if currentConversation?.id == conversationId {
                    currentConversation = conversations[idx]
                }
                cacheMessages(messages, for: conversationId)
                persistHistoryFileReferences(messages, conversationId: conversationId)
            }
        } catch {
            // Offline fallback: show whatever is cached
            if let idx = conversations.firstIndex(where: { $0.id == conversationId }),
               conversations[idx].messages.isEmpty {
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

        // Unconditional, regardless of success/failure/empty-result: once this fetch attempt
        // has concluded, there is nothing left to switch/settle for. Relying only on a
        // downstream success-path signal (isConfirmedEmptyConversation) left the cover spinner
        // stuck whenever the fetch itself failed or kept retrying — e.g. a token refresh
        // triggered by opening a chat after the app sat idle long enough for the access token
        // to actually expire, which takes meaningfully longer than the still-valid-token path a
        // quick test exercises. Guarded on this still being the current selection so a slow,
        // now-superseded load can't clobber a newer switch already in flight.
        if currentConversation?.id == conversationId {
            isSwitchingConversation = false
        }
    }
}
