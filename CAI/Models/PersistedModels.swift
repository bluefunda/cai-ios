import SwiftData
import Foundation

// MARK: - SwiftData persistence models (local cache; backend is source of truth)

@Model final class PersistedConversation {
    @Attribute(.unique) var id: String
    var title: String
    var model: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var messages: [PersistedMessage] = []

    init(id: String, title: String, model: String, createdAt: Date) {
        self.id = id
        self.title = title
        self.model = model
        self.createdAt = createdAt
    }
}

@Model final class PersistedMessage {
    @Attribute(.unique) var id: String
    var conversationId: String
    var roleRaw: String
    var content: String
    var timestamp: Date
    var conversation: PersistedConversation?

    init(id: String, conversationId: String, roleRaw: String, content: String, timestamp: Date) {
        self.id = id
        self.conversationId = conversationId
        self.roleRaw = roleRaw
        self.content = content
        self.timestamp = timestamp
    }
}
