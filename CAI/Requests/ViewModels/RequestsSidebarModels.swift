import SwiftUI

// MARK: - Recently Viewed Requests
// The Requests space's sidebar context list keeps the last few change requests the
// user opened (docs/BLUEREQUESTS_INTEGRATION.md P3, layer 3b). Stored locally as JSON
// in UserDefaults — just enough to draw a row and reopen the request.

struct RecentRequest: Codable, Equatable, Identifiable {
    let id: String
    let number: String
    let title: String
}

@MainActor
final class RecentRequestsStore: ObservableObject {
    @Published private(set) var items: [RecentRequest] = []

    static let limit = 8
    static let storageKey = "requests_recently_viewed"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([RecentRequest].self, from: data) {
            items = Array(decoded.prefix(Self.limit))
        }
    }

    /// Moves `request` to the top, keeping at most `limit` entries.
    func record(_ request: RecentRequest) {
        var updated = items.filter { $0.id != request.id }
        updated.insert(request, at: 0)
        items = Array(updated.prefix(Self.limit))
        persist()
    }

    func record(_ changeRequest: ChangeRequest) {
        record(RecentRequest(id: changeRequest.id, number: changeRequest.requestNumber, title: changeRequest.title))
    }

    /// Drops one request — after it's deleted, its sidebar link would lead nowhere.
    func remove(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    /// Clears everything — called when a different user signs in, so one account's
    /// requests never show up in another's sidebar.
    func removeAll() {
        items = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Quick Filters
// One-tap presets in the Requests sidebar. The API has no reviewer facet, so there's no
// "Needs my review"; the presets are All, Mine, and one per wire status.

enum RequestsQuickFilter: Hashable, Identifiable {
    case all
    case mine
    case status(ChangeRequestStatus)

    static var allCases: [RequestsQuickFilter] {
        [.all, .mine] + ChangeRequestStatus.allCases.map { .status($0) }
    }

    var id: String {
        switch self {
        case .all: return "all"
        case .mine: return "mine"
        case .status(let status): return "status.\(status.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .all: return "All requests"
        case .mine: return "Mine"
        case .status(let status): return status.style.label
        }
    }

    /// Server-side facets: Mine scopes owner and assignee to the current user; every other
    /// preset widens to anyone (a status preset shows that status across the team).
    var advancedFilters: ChangeRequestAdvancedFilters {
        var filters = ChangeRequestAdvancedFilters()
        let mine = self == .mine
        filters.ownerIsMe = mine
        filters.assigneeIsMe = mine
        return filters
    }

    /// Client-side status facet.
    var statusFilter: ChangeRequestStatus? {
        if case .status(let status) = self { return status }
        return nil
    }

    /// Which preset (if any) the list's current filters correspond to — drives the
    /// sidebar's selected row.
    static func matching(advanced: ChangeRequestAdvancedFilters, status: ChangeRequestStatus?) -> RequestsQuickFilter? {
        guard !advanced.isCustom else { return nil }
        if let status {
            return (!advanced.ownerIsMe && !advanced.assigneeIsMe) ? .status(status) : nil
        }
        if advanced.ownerIsMe && advanced.assigneeIsMe { return .mine }
        if !advanced.ownerIsMe && !advanced.assigneeIsMe { return .all }
        return nil
    }
}

extension ChangeRequestListViewModel {
    func apply(_ quickFilter: RequestsQuickFilter) {
        setStatusFilter(quickFilter.statusFilter)
        advancedFilters = quickFilter.advancedFilters
    }

    var activeQuickFilter: RequestsQuickFilter? {
        RequestsQuickFilter.matching(advanced: advancedFilters, status: statusFilter)
    }
}

// MARK: - Request ↔ Chat Links
// "Ask AI about this request" (docs/BLUEREQUESTS_INTEGRATION.md P8): a chat started from a
// change request carries that request as context, and the two stay linked — the request's
// AI tab lists its chats, and a linked chat's sidebar row shows the request number. Links
// are local, as the plan asks: per user, in UserDefaults.

/// What the assistant is told about a request, captured when the chat starts.
struct RequestChatContext: Codable, Equatable {
    let requestId: String
    let number: String
    let title: String
    var description: String?
    var status: String
    var platforms: [String] = []
    var stage: Int?
    var totalStages: Int?
    var stageName: String?
    /// The latest activity first, at most `timelineLimit`, as one line each.
    var timeline: [String] = []

    static let timelineLimit = 10

    init(requestId: String, number: String, title: String, description: String? = nil, status: String,
         platforms: [String] = [], stage: Int? = nil, totalStages: Int? = nil, stageName: String? = nil,
         timeline: [String] = []) {
        self.requestId = requestId
        self.number = number
        self.title = title
        self.description = description
        self.status = status
        self.platforms = platforms
        self.stage = stage
        self.totalStages = totalStages
        self.stageName = stageName
        self.timeline = timeline
    }

    init(_ request: ChangeRequest) {
        let entries = request.timeline
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(Self.timelineLimit)
            .map { entry -> String in
                var line = [entry.userName ?? "Someone", entry.actionVerb, entry.actionDetail]
                    .compactMap { $0 }.joined(separator: " ")
                if let date = entry.createdAt {
                    line += " (\(date.formatted(date: .abbreviated, time: .shortened)))"
                }
                return line
            }
        self.init(
            requestId: request.id, number: request.requestNumber, title: request.title,
            description: request.description, status: request.status.style.label,
            platforms: request.platforms.compactMap(\.description),
            stage: request.currentStage?.order ?? request.stage,
            totalStages: request.stages.isEmpty ? request.totalStages : request.stages.count,
            stageName: request.currentStage?.description,
            timeline: Array(entries)
        )
    }

    /// The request's status for the chip's mini stage rail.
    var railStatus: ChangeRequestStatus {
        ChangeRequestStatus.allCases.first { $0.style.label == status } ?? .other(status)
    }
}

/// A chat linked to a request. `number` and `title` are the request's.
struct RequestChatLink: Codable, Equatable, Identifiable {
    let conversationId: String
    let requestId: String
    let number: String
    let title: String
    let linkedAt: Date

    var id: String { conversationId }
}

/// The links, and the request attached to a chat that hasn't sent its first message yet.
@MainActor
@Observable
final class RequestChatLinks {
    private(set) var links: [String: RequestChatLink] = [:]
    /// Attached to a new chat, waiting for its first message (which carries the context).
    private(set) var pending: [String: RequestChatContext] = [:]

    static let storagePrefix = "requests_chat_links_"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var userId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads the signed-in user's links, so one account's links never show in another's.
    func setUser(_ id: String?) {
        guard id != userId else { return }
        userId = id
        pending = [:]
        guard let id, let data = defaults.data(forKey: Self.storagePrefix + id),
              let decoded = try? JSONDecoder().decode([RequestChatLink].self, from: data) else {
            links = [:]
            return
        }
        links = Dictionary(decoded.map { ($0.conversationId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func attach(_ context: RequestChatContext, to conversationId: String) {
        pending[conversationId] = context
    }

    func detach(from conversationId: String) {
        pending[conversationId] = nil
    }

    func pendingContext(for conversationId: String?) -> RequestChatContext? {
        conversationId.flatMap { pending[$0] }
    }

    /// The prompt for a chat's first message when a request is attached: links the chat and
    /// returns the question wrapped in the request's context; nil when nothing is attached.
    func consumePrompt(for conversationId: String?, question: String) -> String? {
        guard let conversationId, let context = pending.removeValue(forKey: conversationId) else { return nil }
        link(conversationId: conversationId, requestId: context.requestId, number: context.number, title: context.title)
        return RequestPromptBuilder.buildPrompt(question: question, request: context)
    }

    func link(conversationId: String, requestId: String, number: String, title: String) {
        links[conversationId] = RequestChatLink(
            conversationId: conversationId, requestId: requestId, number: number, title: title, linkedAt: Date())
        persist()
    }

    func link(forConversation conversationId: String) -> RequestChatLink? {
        links[conversationId]
    }

    /// A request's chats, newest first.
    func conversations(forRequest requestId: String) -> [RequestChatLink] {
        links.values.filter { $0.requestId == requestId }.sorted { $0.linkedAt > $1.linkedAt }
    }

    func unlink(conversationId: String) {
        links[conversationId] = nil
        pending[conversationId] = nil
        persist()
    }

    private func persist() {
        guard let userId, let data = try? JSONEncoder().encode(Array(links.values)) else { return }
        defaults.set(data, forKey: Self.storagePrefix + userId)
    }
}

/// Builds what's sent for the first message of a chat about a request — the user's own
/// question stays what their bubble shows, as ST22PromptBuilder does for a dump.
enum RequestPromptBuilder {
    static func buildPrompt(question: String, request: RequestChatContext) -> String {
        var lines = ["Title: \(request.title)", "Status: \(request.status)"]
        if let stage = request.stage, let total = request.totalStages {
            lines.append("Stage: \(stage) of \(total)" + (request.stageName.map { " (\($0))" } ?? ""))
        }
        if !request.platforms.isEmpty {
            lines.append("Platforms: \(request.platforms.joined(separator: ", "))")
        }
        if let description = request.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            lines.append("Description:\n\(description)")
        }
        if !request.timeline.isEmpty {
            lines.append("Recent activity (newest first):\n" + request.timeline.map { "- \($0)" }.joined(separator: "\n"))
        }
        let ask = question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Summarise this change request and suggest next steps."
            : question
        return """
        The user is asking about change request \(request.number) from BlueRequests. \
        Use its details below to answer.

        \(lines.joined(separator: "\n"))

        Question: \(ask)
        """
    }
}

/// New Request prefilled from an assistant answer ("Create change request…"): the title
/// from the chat's title, the description from the answer as plain text.
struct NewRequestPrefill: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let description: String
    /// The chat the answer came from, linked to the request once it's created.
    let conversationId: String?

    static let titleLimit = 120

    init(chatTitle: String?, answerMarkdown: String, conversationId: String?) {
        let plain = Self.plainText(answerMarkdown)
        let chat = chatTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // A chat not yet titled is "New Chat"; the answer's first line says more.
        let fallback = plain.split(separator: "\n").first.map(String.init) ?? ""
        title = String((chat.isEmpty || chat == "New Chat" ? fallback : chat).prefix(Self.titleLimit))
        description = plain
        self.conversationId = conversationId
    }

    /// Markdown to readable text: formatting marks dropped, paragraphs and list items
    /// kept on their own lines.
    static func plainText(_ markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let attributed = try? AttributedString(markdown: markdown, options: options) else {
            return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var lines: [String] = []
        var lastIdentity: Int?
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            let identity = run.presentationIntent?.components.first?.identity
            if identity != lastIdentity || lines.isEmpty {
                let prefix = run.presentationIntent?.components.contains { if case .listItem = $0.kind { return true }; return false } == true ? "- " : ""
                lines.append(prefix + text)
                lastIdentity = identity
            } else {
                lines[lines.count - 1] += text
            }
        }
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

// MARK: - Bridge Actions
// What the request screens and the chat ask the shell to do across spaces. Set by
// ContentView, which owns both spaces; nil elsewhere (previews, Settings), where the
// actions are simply not offered.

/// Equatable as always-equal: the closures only capture long-lived objects, and a new
/// instance on every ContentView render would otherwise redraw every chat message that
/// reads it, including while an answer streams.
struct RequestBridgeActions: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { true }

    /// Starts a new chat in the Assistant space with `request` attached.
    let askAI: (ChangeRequest) -> Void
    /// Opens a linked chat in the Assistant space.
    let openConversation: (RequestChatLink) -> Void
    /// Opens New Request prefilled from an assistant answer (markdown).
    let createRequest: (_ answerMarkdown: String) -> Void
    /// A chat's current title, if it's loaded.
    let chatTitle: (_ conversationId: String) -> String?
}

private struct RequestBridgeActionsKey: EnvironmentKey {
    static let defaultValue: RequestBridgeActions? = nil
}

private struct RequestChatLinksKey: EnvironmentKey {
    static let defaultValue: RequestChatLinks? = nil
}

extension EnvironmentValues {
    var requestBridge: RequestBridgeActions? {
        get { self[RequestBridgeActionsKey.self] }
        set { self[RequestBridgeActionsKey.self] = newValue }
    }

    var requestChatLinks: RequestChatLinks? {
        get { self[RequestChatLinksKey.self] }
        set { self[RequestChatLinksKey.self] = newValue }
    }
}
