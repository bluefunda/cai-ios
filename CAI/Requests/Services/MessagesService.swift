import Foundation

// MARK: - Messages Service
// The BlueRequests web app's Messages calls (trm/src/apiCalls/messagesApis.js), on the
// same trm-gw base URL — see RQMessages.swift for the routes and response shapes.

protocol MessagesServicing {
    func listConversations() async throws -> [RQConversation]
    /// One page of a conversation, newest first from the backend: messages at or before
    /// `before` (its raw timestamp), up to `batchSize`. nil starts from the latest message.
    func messages(conversationId: String, before: String?, batchSize: Int) async throws -> [RQMessage]
    /// `attachments` are files already uploaded (AttachmentService), sent by id.
    func send(_ text: String, attachments: [RQAttachment], conversationId: String) async throws
    func markSeen(conversationId: String) async throws
    /// Starts a conversation with `recipientIds` (the current user is added) and returns
    /// its id. The first message is a separate `send`, as in the web's New message drawer.
    func createConversation(topic: String, recipientIds: [String]) async throws -> String
}

extension MessagesServicing {
    func send(_ text: String, conversationId: String) async throws {
        try await send(text, attachments: [], conversationId: conversationId)
    }
}

struct MessagesService: MessagesServicing {
    let client: RequestsAPIClient
    let currentUserProvider: @Sendable () async -> User?

    func listConversations() async throws -> [RQConversation] {
        let userId = try await currentUserId()
        let response: RQConversationsResponse = try await client.get("/users/\(userId)/conversations")
        return response.conversations
    }

    func messages(conversationId: String, before: String?, batchSize: Int) async throws -> [RQMessage] {
        var query = [URLQueryItem(name: "batchSize", value: String(batchSize))]
        // Only an earlier page sends a cursor (the oldest shown message's time, inclusive).
        // The latest page leaves it out and the backend uses its own now: a device "now"
        // in whole seconds left out a message sent within the same second.
        if let before {
            query.append(URLQueryItem(name: "lastMessageTimestamp", value: before))
        }
        let history: RQConversationHistory = try await client.get(
            "/conversations/\(conversationId)/messages", queryItems: query
        )
        return history.messages
    }

    func send(_ text: String, attachments: [RQAttachment], conversationId: String) async throws {
        let userId = try await currentUserId()
        // With milliseconds, as the web's toISOString() sends it: history is ordered and
        // paged by this time, and whole seconds tie between quick messages.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body = RQNewMessage(
            senderId: userId,
            message: text,
            createdAt: formatter.string(from: Date()),
            mentions: [],
            attachments: attachments.map { CommentAttachmentRef(id: $0.id, fileName: $0.fileName) },
            conversationId: conversationId
        )
        try await client.postDiscardingResponse("/discussions/\(conversationId)/messages", body: body)
    }

    func markSeen(conversationId: String) async throws {
        let userId = try await currentUserId()
        try await client.putDiscardingResponse(
            "/discussions/\(conversationId)/seen",
            body: RQMarkSeen(userId: userId, conversationId: conversationId)
        )
    }

    func createConversation(topic: String, recipientIds: [String]) async throws -> String {
        let userId = try await currentUserId()
        var seen: Set<String> = [userId]
        let body = RQNewConversation(
            userIDs: recipientIds.filter { seen.insert($0).inserted } + [userId],
            creatorId: userId,
            topic: topic,
            changeRequestId: RQNewConversation.changeRequestId(inTopic: topic)
        )
        let created: RQCreatedConversation = try await client.post("/discussions", body: body)
        return created.conversationId
    }

    private func currentUserId() async throws -> String {
        guard let user = await currentUserProvider() else { throw RequestsAPIError.notSignedIn }
        return user.id
    }
}

// MARK: - Fixtures

/// Canned conversations for `-bf_requests_fixtures YES` (no network), like the other
/// Fixture*Service types.
actor FixtureMessagesService: MessagesServicing {
    private var store: [String: [RQMessage]] = [
        "fixture-1": [
            RQMessage(id: 1, senderId: "fixture-user", text: "Hello",
                      createdAtRaw: "2026-02-09T04:44:59Z",
                      sender: RQParticipant(id: "fixture-user", name: "Phani", profileImage: nil))
        ]
    ]

    func listConversations() async throws -> [RQConversation] {
        [RQConversation(
            id: "fixture-1", topic: "Hello", isGroup: false,
            lastMessage: store["fixture-1"]?.last,
            participants: [RQParticipant(id: "fixture-user", name: "Phani", profileImage: nil)],
            unreadCount: 0
        )]
    }

    func messages(conversationId: String, before: String?, batchSize: Int) async throws -> [RQMessage] {
        Array((store[conversationId] ?? []).reversed().prefix(batchSize))
    }

    func send(_ text: String, attachments: [RQAttachment], conversationId: String) async throws {
        let next = (store[conversationId]?.map(\.id).max() ?? 0) + 1
        store[conversationId, default: []].append(
            RQMessage(id: next, senderId: "me", text: text,
                      createdAtRaw: ISO8601DateFormatter().string(from: Date()), sender: nil,
                      attachments: attachments)
        )
    }

    func markSeen(conversationId: String) async throws {}

    func createConversation(topic: String, recipientIds: [String]) async throws -> String {
        let id = "fixture-\(store.count + 1)"
        store[id] = []
        return id
    }
}
