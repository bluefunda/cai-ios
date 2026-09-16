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
    /// Persona active when this message was sent/answered (bluefunda/cai-ios#207).
    /// Absent on messages written before this field existed — reads back as nil,
    /// not an error (SwiftData default-value migration).
    var persona: String?
    /// JSON-encoded `[MessageStep]` (bluefunda/cai-ios#310 follow-up) — stored as
    /// a plain string rather than a `@Relationship`/structured column since it's
    /// small, self-contained, and never queried on its own. Absent on messages
    /// written before this field existed, same additive-optional pattern as
    /// `persona` above — reads back as nil, not an error.
    var stepsJSON: String?
    /// Wall-clock seconds from the first step to stream end (bluefunda/cai-ios#310
    /// follow-up) — same additive-optional pattern as `persona`/`stepsJSON`.
    var thinkingDurationSeconds: Int?
    var conversation: PersistedConversation?

    init(
        id: String, conversationId: String, roleRaw: String, content: String, timestamp: Date, persona: String? = nil,
        stepsJSON: String? = nil, thinkingDurationSeconds: Int? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.roleRaw = roleRaw
        self.content = content
        self.timestamp = timestamp
        self.persona = persona
        self.stepsJSON = stepsJSON
        self.thinkingDurationSeconds = thinkingDurationSeconds
    }
}
