import Foundation

// MARK: - Chat list: paging, pinning, search (cai-ios#370, #335)
extension ChatManager {

    /// Loads the first page of the chat list, plus every pinned chat.
    func loadChats() async {
        guard let api = apiService else { return }
        isLoadingChats = true

        do {
            let page = try await api.fetchChatPage(cursor: nil)
            let pinnedDTOs = page.pinnedChats ?? []
            let loaded = pinnedDTOs.map { conversation(from: $0) } + page.chats.map { conversation(from: $0) }
            let serverIds = Set(loaded.map(\.id))
            // Chats the server doesn't list yet are kept only while they're genuinely local — the
            // open chat, or one still streaming (sent moments ago). The open chat may also simply
            // be on a later page (opened from search, or after scrolling), so it stays too.
            let localOnly = conversations.filter {
                !serverIds.contains($0.id) && ($0.id == currentConversation?.id || hasTurnInFlight($0.id))
            }
            conversations = loaded.map(keepingCachedMessages) + localOnly
            chatListNextCursor = page.nextCursor.flatMap { $0.isEmpty ? nil : $0 }
            cacheConversations(loaded)
            // Only the complete list proves a cached chat is gone (deleted elsewhere, or from
            // another backend). With more pages to come, a chat missing from this one is just
            // older — pruning then would wipe its cached messages.
            if chatListNextCursor == nil {
                pruneCachedConversations(keeping: serverIds.union(localOnly.map(\.id)))
            }
            retryStuckTitles(pinnedDTOs + page.chats)
        } catch {
            // Don't surface load errors — user can still create new chats
            print("[ChatManager] loadChats error: \(error)")
        }

        isLoadingChats = false
    }

    /// Appends the next page of the chat list. Called as the sidebar is scrolled to its end;
    /// a no-op while a page is already loading or once the last page is in.
    func loadMoreChats() async {
        guard let api = apiService, let cursor = chatListNextCursor, !isLoadingMoreChats else { return }
        isLoadingMoreChats = true
        defer { isLoadingMoreChats = false }

        do {
            let page = try await api.fetchChatPage(cursor: cursor)
            // The list may have been reloaded while this page was in flight — its cursor is
            // stale then, and this page no longer continues the list.
            guard chatListNextCursor == cursor else { return }
            let known = Set(conversations.map(\.id))
            let more = page.chats.map { conversation(from: $0) }.filter { !known.contains($0.id) }
            conversations.append(contentsOf: more)
            chatListNextCursor = page.nextCursor.flatMap { $0.isEmpty ? nil : $0 }
            cacheConversations(more)
            retryStuckTitles(page.chats)
        } catch {
            print("[ChatManager] loadMoreChats error: \(error)")
        }
    }

    /// Pins or unpins a chat. Updates the list right away and reverts if the server refuses.
    func setPinned(_ conversation: Conversation, _ pinned: Bool) {
        guard let api = apiService else { return }
        Haptic.selection()
        applyPinned(pinned, to: conversation.id)
        Task {
            do {
                try await api.setChatPinned(chatId: conversation.id, pinned: pinned)
            } catch {
                print("[ChatManager] setPinned error: \(error)")
                applyPinned(!pinned, to: conversation.id)
                self.error = pinned ? "Couldn't pin the chat. Try again." : "Couldn't unpin the chat. Try again."
            }
        }
    }

    func searchChats(query: String, cursor: String?) async throws -> ChatSearchResponse {
        guard let api = apiService else { throw URLError(.notConnectedToInternet) }
        return try await api.searchChats(query: query, cursor: cursor)
    }

    /// The conversation for a chat picked from search results. It may not be in the loaded list
    /// yet (an older page); then it's added, so the sidebar can show it selected.
    func conversation(forSearchResult result: ChatSearchResultDTO) -> Conversation {
        if let existing = conversations.first(where: { $0.id == result.id }) {
            return existing
        }
        var found = Conversation(
            id: result.id, title: result.title ?? "Chat", messages: [],
            model: selectedModel.id, createdAt: result.lastUpdatedAt.flatMap(Date.fromISO8601) ?? Date()
        )
        found.isPinned = result.pinned ?? false
        conversations.append(found)
        return found
    }

    private func applyPinned(_ pinned: Bool, to id: String) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].isPinned = pinned
        }
        if currentConversation?.id == id {
            currentConversation?.isPinned = pinned
        }
    }

    private func conversation(from dto: ChatSummaryDTO) -> Conversation {
        var conv = Conversation(
            id: dto.id,
            title: dto.title ?? dto.firstMessage?.truncated(to: 50) ?? "Chat",
            messages: [],
            model: dto.model ?? selectedModel.id,
            createdAt: dto.createdAt.flatMap(Date.fromISO8601) ?? Date()
        )
        conv.isPinned = dto.pinned ?? false
        return conv
    }

    /// Keeps messages already loaded for a chat when the list refreshes its metadata.
    private func keepingCachedMessages(_ conv: Conversation) -> Conversation {
        guard let cached = conversations.first(where: { $0.id == conv.id }), !cached.messages.isEmpty else {
            return conv
        }
        var merged = Conversation(id: conv.id, title: conv.title, messages: cached.messages,
                                  model: conv.model, createdAt: conv.createdAt)
        merged.isPinned = conv.isPinned
        return merged
    }
}
