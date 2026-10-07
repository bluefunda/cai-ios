import Foundation
import SwiftData

extension ChatManager {
    // MARK: - Message History

    /// Loads full message history for a conversation from the API (lazy on selection).
    /// - Parameter force: Bypasses the "only fetch if empty" guard — used by
    ///   `reconcileAfterBackground()` to pull the authoritative server copy
    ///   over locally-cached messages after a stream was interrupted.
    /// True while a reply is streaming into this conversation. Its local messages are then
    /// ahead of the server (the server only has the user prompt until the stream ends), so a
    /// fetch must not replace them — doing so wiped the in-flight reply placeholder right after
    /// a new chat's first send, hiding "Thinking…" until the first stream event re-added it.
    func hasTurnInFlight(_ conversationId: String) -> Bool {
        guard isStreaming, let streamingId = streamingMessageId else { return false }
        return conversations.first(where: { $0.id == conversationId })?
            .messages.contains(where: { $0.id == streamingId }) ?? false
    }

    func loadMessages(for conversationId: String, force: Bool = false) async {
        if !force, hasTurnInFlight(conversationId) { return }
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
            // A turn may have started while this fetch was in flight — its local copy wins.
            if !force, hasTurnInFlight(conversationId) { return }
            // cai-mcp-go now persists steps/thinkingDurationSeconds itself, so the server is
            // authoritative and syncs across devices/reinstalls — but only for messages
            // persisted AFTER that support was added. The local SwiftData cache is the fallback
            // for anything the server doesn't have yet (older history, or a persist call that
            // failed), by message id. Mirrors cai-android's ChatRepository.loadMessages.
            let convId = conversationId
            let cachedById: [String: PersistedMessage] = {
                let desc = FetchDescriptor<PersistedConversation>(predicate: #Predicate { $0.id == convId })
                guard let persisted = try? modelContext?.fetch(desc).first else { return [:] }
                return Dictionary(uniqueKeysWithValues: persisted.messages.map { ($0.id, $0) })
            }()
            let messages = dtos.map { dto -> ChatMessage in
                var message = ChatMessage(
                    id: dto.id ?? UUID().uuidString,
                    role: MessageRole(rawValue: dto.normalizedRoleString) ?? .user,
                    content: dto.content,
                    timestamp: dto.createdAt.flatMap(Date.fromISO8601) ?? Date(),
                    fileUrl: dto.fileUrl,
                    fileMetadata: dto.fileMetadata?.map(MessageFileMetadata.init(from:)),
                    persona: dto.persona,
                    steps: dto.steps,
                    thinkingDurationSeconds: dto.thinkingDurationSeconds
                )
                if message.steps?.isEmpty ?? true,
                   let cached = cachedById[message.id], let cachedMessage = ChatMessage(from: cached) {
                    message.steps = cachedMessage.steps
                    message.thinkingDurationSeconds = message.thinkingDurationSeconds ?? cachedMessage.thinkingDurationSeconds
                }
                return message
            }
            // Never let an empty server response wipe messages already on screen (restored
            // from the local cache, or just streamed) — that read as a valid chat rendering
            // for a moment and then flipping to "No messages found". Leave it un-confirmed so
            // a later open fetches again instead.
            if messages.isEmpty && !conversations[idx].messages.isEmpty {
                print("[ChatManager] loadMessages: server returned no messages for \(conversationId); keeping local copy")
            } else {
                var messages = messages
                var confirmed = true
                // A just-stopped reply is saved server-side a moment after Stop; a fetch that
                // lands first (Stop → switch chat → back) is exactly one reply behind. Keep the
                // reply that's on screen and fetch again next time instead of dropping it.
                let local = conversations[idx].messages
                if let localReply = local.last, localReply.role == .assistant, !localReply.content.isEmpty,
                   messages.count == local.count - 1, messages.last?.role == .user,
                   !messages.contains(where: { $0.id == localReply.id }) {
                    messages.append(localReply)
                    confirmed = false
                }
                conversations[idx].messages = messages
                conversations[idx].messagesLoaded = confirmed
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
        // With messages to show, the view's scroll-settle task drops the cover once the chat
        // sits at its bottom; dropping it here, on the same frame the rows arrive, showed a long
        // chat jumping into place (flicker). Nothing to settle → drop it now.
        if currentConversation?.id == conversationId, currentConversation?.messages.isEmpty ?? true {
            isSwitchingConversation = false
        }
    }

    // MARK: - Chat List

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
            retryStuckTitles(dtos)
        } catch {
            // Don't surface load errors — user can still create new chats
            print("[ChatManager] loadChats error: \(error)")
        }

        isLoadingChats = false
    }

    // MARK: - Message Patching

    /// Patches a user message's fileUrl once an attachment upload resolves — beginUserTurn shows
    /// the message immediately with the local filename (so the chip renders right away, above the
    /// prompt, without waiting on the network), and this swaps in the real remote URL once known.
    func updateUserMessageFileUrl(_ fileUrl: String, messageId: String, in conversationId: String) {
        guard var conversation = conversations.first(where: { $0.id == conversationId }),
              let index = conversation.messages.firstIndex(where: { $0.id == messageId }) else { return }

        conversation.messages[index].fileUrl = fileUrl
        updateConversation(conversation)

        if currentConversation?.id == conversationId {
            currentConversation = conversation
        }
    }
}
