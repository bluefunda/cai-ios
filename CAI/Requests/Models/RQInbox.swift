import Foundation

// MARK: - In-app notifications (the bell)
// trm-gw GET /notifications/inbox → trm-bff → trm-backend-go GET /v1/notifications:
// the caller's own work activity on change requests (approvals, decisions, stage moves,
// owners, @mentions) and direct messages, one entry per conversation.

struct InboxItem: Decodable, Identifiable, Equatable {
    let id: String
    let type: String
    let changeRequestId: Int?
    /// A direct-message entry's conversation; opening it opens that conversation.
    var conversationId: String?
    let title: String
    let summary: String
    let actorName: String
    let createdAt: Date
    var readAt: Date?

    var isUnread: Bool { readAt == nil }

    /// An icon and tone for each kind, so a list can be scanned (as on the web).
    var kind: InboxKind { InboxKind(type: type) }
}

enum InboxKind {
    case action, good, bad, info

    init(type: String) {
        switch type {
        case "cr.approval_requested", "cr.owner_assigned": self = .action
        case "cr.approved", "cr.completed": self = .good
        case "cr.rejected": self = .bad
        default: self = .info
        }
    }
}

extension InboxItem {
    /// The SF Symbol for this kind of notification.
    var symbol: String {
        switch type {
        case "cr.approval_requested": return "person.badge.clock"
        case "cr.owner_assigned": return "person.badge.plus"
        case "cr.approved": return "checkmark.circle"
        case "cr.completed": return "checkmark.seal"
        case "cr.rejected": return "xmark.circle"
        case "cr.stage_moved": return "arrow.right.circle"
        case "comment.mentioned": return "at"
        case "message.received": return "bubble.left"
        default: return "bell"
        }
    }
}

struct InboxPage: Decodable, Equatable {
    let items: [InboxItem]
    let unreadCount: Int
    /// The next page's `before`, nil on the last page.
    let nextBefore: Date?
}
