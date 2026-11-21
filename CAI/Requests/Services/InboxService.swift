import Foundation

// MARK: - Inbox Service
// The bell's calls, as the web makes them (cai notificationsApis.js):
//   GET  /notifications/inbox?before=&limit=   → InboxPage, newest first
//   GET  /notifications/inbox/unread-count     → { unreadCount }
//   POST /notifications/inbox/{id}/read        → 204
//   POST /notifications/inbox/read-all         → { marked }

protocol InboxServicing {
    func page(before: Date?, limit: Int) async throws -> InboxPage
    func unreadCount() async throws -> Int
    func markRead(id: String) async throws
    func markAllRead() async throws
}

struct InboxService: InboxServicing {
    let client: RequestsAPIClient

    func page(before: Date?, limit: Int) async throws -> InboxPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            query.append(URLQueryItem(name: "before", value: Self.timestamp(before)))
        }
        return try await client.get("/notifications/inbox", queryItems: query)
    }

    func unreadCount() async throws -> Int {
        let body: UnreadCountBody = try await client.get("/notifications/inbox/unread-count")
        return body.unreadCount
    }

    func markRead(id: String) async throws {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try await client.postDiscardingResponse("/notifications/inbox/\(escaped)/read", body: NoBody())
    }

    func markAllRead() async throws {
        try await client.postDiscardingResponse("/notifications/inbox/read-all", body: NoBody())
    }

    /// RFC 3339 with fractional seconds, so a page boundary isn't rounded past a row.
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private struct UnreadCountBody: Decodable { let unreadCount: Int }
    private struct NoBody: Encodable {}
}
