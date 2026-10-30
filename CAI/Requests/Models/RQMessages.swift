import Foundation

// MARK: - Messages (discussions)
// The same conversations the BlueRequests web app's Messages screen shows, from the same
// trm-gw routes (trm-bff → trm-backend over NATS):
//   GET  /users/{userId}/conversations                     → RQConversationsResponse
//   GET  /conversations/{id}/messages?lastMessageTimestamp=&batchSize=  → RQConversationHistory
//   POST /discussions/{id}/messages                        ← RQNewMessage
//   PUT  /discussions/{id}/seen                            ← RQMarkSeen
// trm-backend v2 sends `conversationId`; responses from before v2 used `ConversationId`,
// so both are read.

/// A participant or message sender (trm-backend's model.User, trimmed to what's shown).
struct RQParticipant: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let profileImage: String?

    private enum CodingKeys: String, CodingKey { case id, name, profileImage }

    init(id: String, name: String, profileImage: String?) {
        self.id = id
        self.name = name
        self.profileImage = profileImage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        profileImage = (try? c.decode(String.self, forKey: .profileImage)).flatMap { $0.isEmpty ? nil : $0 }
    }
}

struct RQMessage: Identifiable, Decodable, Hashable {
    let id: Int
    let senderId: String
    let text: String
    let createdAt: Date?
    /// The timestamp exactly as the backend sent it — paging sends it back as
    /// `lastMessageTimestamp`, so it isn't re-formatted.
    let createdAtRaw: String?
    let sender: RQParticipant?

    private enum CodingKeys: String, CodingKey {
        case id, senderId, message, createdAt
        case sender = "SenderInfo"
    }

    init(id: Int, senderId: String, text: String, createdAtRaw: String?, sender: RQParticipant?) {
        self.id = id
        self.senderId = senderId
        self.text = text
        self.createdAtRaw = createdAtRaw
        self.createdAt = createdAtRaw.flatMap { Date.fromISO8601($0) }
        self.sender = sender
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        senderId = (try? c.decode(String.self, forKey: .senderId)) ?? ""
        text = (try? c.decode(String.self, forKey: .message)) ?? ""
        createdAtRaw = try? c.decode(String.self, forKey: .createdAt)
        // COALESCEd NULLs arrive as Go's zero time (year 1) — treat as unknown.
        createdAt = createdAtRaw.flatMap { Date.fromISO8601($0) }.flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil }
        sender = try? c.decode(RQParticipant.self, forKey: .sender)
    }
}

struct RQConversation: Identifiable, Decodable, Hashable {
    let id: String
    let topic: String
    let isGroup: Bool
    let lastMessage: RQMessage?
    let participants: [RQParticipant]
    let unreadCount: Int

    private enum CodingKeys: String, CodingKey {
        case conversationId, legacyConversationId = "ConversationId"
        case topic, isGroup, participants
        case lastMessage = "lastMessageInfo"
        case unreadCount = "UnreadMessageCount"
    }

    init(id: String, topic: String, isGroup: Bool, lastMessage: RQMessage?,
         participants: [RQParticipant], unreadCount: Int) {
        self.id = id
        self.topic = topic
        self.isGroup = isGroup
        self.lastMessage = lastMessage
        self.participants = participants
        self.unreadCount = unreadCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .conversationId))
            ?? (try? c.decode(String.self, forKey: .legacyConversationId)) ?? ""
        topic = (try? c.decode(String.self, forKey: .topic)) ?? ""
        isGroup = (try? c.decode(Bool.self, forKey: .isGroup)) ?? false
        lastMessage = try? c.decode(RQMessage.self, forKey: .lastMessage)
        participants = (try? c.decode([RQParticipant].self, forKey: .participants)) ?? []
        unreadCount = (try? c.decode(Int.self, forKey: .unreadCount)) ?? 0
    }

    /// Everyone but the signed-in user, for the row's avatars and title fallback.
    func others(excluding userId: String?) -> [RQParticipant] {
        participants.filter { $0.id != userId }
    }
}

/// `{"UserConversations": {"discussionsInfo": [...]}}` — either level may be missing for a
/// user with no conversations.
struct RQConversationsResponse: Decodable, EmptyDecodableResponse {
    let conversations: [RQConversation]

    static var empty: Self { .init(conversations: []) }

    private enum CodingKeys: String, CodingKey { case userConversations = "UserConversations" }
    private enum InnerKeys: String, CodingKey { case discussionsInfo }

    init(conversations: [RQConversation]) { self.conversations = conversations }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let inner = try? c.nestedContainer(keyedBy: InnerKeys.self, forKey: .userConversations)
        conversations = (try? inner?.decode([RQConversation].self, forKey: .discussionsInfo)) ?? []
    }
}

/// `{"conversationId": "…", "discussionDetail": {…, "Messages": [...]}}`.
struct RQConversationHistory: Decodable, EmptyDecodableResponse {
    let messages: [RQMessage]

    static var empty: Self { .init(messages: []) }

    private enum CodingKeys: String, CodingKey { case discussionDetail }
    private enum DetailKeys: String, CodingKey { case messages = "Messages" }

    init(messages: [RQMessage]) { self.messages = messages }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let detail = try? c.nestedContainer(keyedBy: DetailKeys.self, forKey: .discussionDetail)
        messages = (try? detail?.decode([RQMessage].self, forKey: .messages)) ?? []
    }
}

/// The web app's send payload (messageChatbox.js).
struct RQNewMessage: Encodable {
    let senderId: String
    let message: String
    let createdAt: String
    let mentions: [String]
    let attachments: [String]
    let conversationId: String
}

struct RQMarkSeen: Encodable {
    let userId: String
    let conversationId: String
}
