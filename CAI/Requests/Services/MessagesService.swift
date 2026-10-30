import Foundation

// MARK: - Messages Service
// The BlueRequests web app's Messages calls (trm/src/apiCalls/messagesApis.js), on the
// same trm-gw base URL — see RQMessages.swift for the routes and response shapes.

protocol MessagesServicing {
    func listConversations() async throws -> [RQConversation]
    /// One page of a conversation, newest first from the backend: messages at or before
    /// `before` (its raw timestamp), up to `batchSize`. nil starts from the latest message.
    func messages(conversationId: String, before: String?, batchSize: Int) async throws -> [RQMessage]
    func send(_ text: String, conversationId: String) async throws
    func markSeen(conversationId: String) async throws
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
        // The backend needs a timestamp; "now" (inclusive) means the latest page.
        query.append(URLQueryItem(name: "lastMessageTimestamp",
                                  value: before ?? ISO8601DateFormatter().string(from: Date())))
        let history: RQConversationHistory = try await client.get(
            "/conversations/\(conversationId)/messages", queryItems: query
        )
        return history.messages
    }

    func send(_ text: String, conversationId: String) async throws {
        let userId = try await currentUserId()
        let body = RQNewMessage(
            senderId: userId,
            message: text,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            mentions: [],
            attachments: [],
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

    func send(_ text: String, conversationId: String) async throws {
        let next = (store[conversationId]?.map(\.id).max() ?? 0) + 1
        store[conversationId, default: []].append(
            RQMessage(id: next, senderId: "me", text: text,
                      createdAtRaw: ISO8601DateFormatter().string(from: Date()), sender: nil)
        )
    }

    func markSeen(conversationId: String) async throws {}
}
