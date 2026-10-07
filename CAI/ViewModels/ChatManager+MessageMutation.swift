import Foundation

// Private message-mutation helpers used by beginUserTurn/continueSendingMessage/stopStreaming —
// split out of the main class body to stay under SwiftLint's type_body_length limit
// (bluefunda/cai-ios#261 precedent — see ChatManager+Background.swift). Not marked `private`
// since that's file-scoped in Swift; these are internal (the module-default access level) so
// ChatManager.swift itself can still call them.
extension ChatManager {

    func updateConversation(_ conversation: Conversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        }
    }

    /// Updates the conversation in place, or inserts it at the top of history
    /// if it isn't there yet (used when a draft sends its first message).
    func upsertConversation(_ conversation: Conversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
    }

    /// Drops the trailing assistant placeholder if it's still empty — used when a stream ends
    /// in a way that will never fill it in (a server error, or a rate limit hit before any text
    /// arrived). Left in place, an empty placeholder renders as a permanently blank response
    /// bubble: no spinner, since isStreaming is about to end, and no text, since none ever came.
    ///
    /// Also requires steps to be empty: stopping mid-thinking (before any answer text has
    /// streamed yet) left content empty but steps non-empty, and this used to delete the whole
    /// message — wiping out the thinking card the user was watching. claude.ai keeps its
    /// thought process visible after Stop; a message with real steps is never "nothing worth
    /// keeping" even if content hasn't started yet.
    func removeTrailingEmptyAssistantPlaceholder(in conversationId: String) {
        guard var conversation = conversations.first(where: { $0.id == conversationId }),
              conversation.messages.last?.role == .assistant,
              conversation.messages.last?.content.isEmpty == true,
              conversation.messages.last?.steps?.isEmpty ?? true else { return }

        conversation.messages.removeLast()

        // An attachment-only send (no typed text) stopped before any response arrived leaves
        // nothing worth keeping — without this, the user bubble would show just an attachment
        // chip with no text, as if the turn never really happened. Text turns are left alone:
        // the user's own words are always worth keeping even if the reply never came.
        if let lastMessage = conversation.messages.last, lastMessage.role == .user, lastMessage.content.isEmpty {
            conversation.messages.removeLast()
        }

        updateConversation(conversation)

        if currentConversation?.id == conversationId {
            currentConversation = conversation
        }
    }

    func updateLastMessage(_ message: ChatMessage, in conversationId: String) {
        guard var conversation = conversations.first(where: { $0.id == conversationId }),
              !conversation.messages.isEmpty else { return }

        conversation.messages[conversation.messages.count - 1] = message
        updateConversation(conversation)

        if currentConversation?.id == conversationId {
            currentConversation = conversation
        }
    }

    func updateConversationTitle(_ conversationId: String, from prompt: String) {
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
}
