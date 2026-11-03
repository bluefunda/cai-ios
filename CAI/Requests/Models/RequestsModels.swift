import Foundation

// MARK: - BlueRequests Wire Models
// Ported from trm-ios (TRM/Models/APIModels.swift) with its defensive decoding and
// its notes on which fields are confirmed vs. guessed. Types that collide with cai's
// own or read too generically here carry an `RQ` prefix (RQProject, RQComment,
// RQAttachment, RQTeam, RQRelease); the signed-in user is cai's own `User`.

// MARK: - User Profile
// GET /rest/trm/v1/user?id={sub} — confirmed against trm-gw's krakend templates and
// trm's own frontend (src/components/profile/profile.js, src/components/settings/settings.js).
// The JWT already gives us name/email (cai's `User`, decoded by AuthManager); this adds
// the fields that only live server-side: department, role, team, and the notification
// preference. Decoded defensively (no live sample seen for this one, unlike ChangeRequest) — every field but
// `name` is optional and simply doesn't render if absent rather than crashing decode.

struct UserProfile: Decodable {
    let id: String?
    let name: String
    let email: String?
    let department: String?
    let role: String?
    let teamName: String?
    let notification: Bool?
}

struct UserProfileListResponse: Decodable {
    let users: [UserProfile]
}

/// Partial update — only the fields actually being changed are sent, matching trm's own
/// `updateuserDetails({updatedBy, notification?, workPlace?}, sub)` call. `workPlace`
/// (List/Grid workspace view) is a desktop-only concept with no mobile equivalent, so it's
/// never sent here.
struct UpdateUserRequest: Encodable {
    let updatedBy: String
    let notification: Bool?
}

// MARK: - Change Request
//
// The real wire format (confirmed against trm's own frontend source — changeRequestHome.js,
// changeRequestDetail.js, changeReqApis.js; there is no OpenAPI spec anywhere in trm,
// trm-bff, trm-backend-go, or trm-gw) nests everything under `combinedResponse[]`. Each
// element pairs a `changeRequest` core object with sibling lookup/label data
// (severityData, requestTypeData, userTimeline, …) — and, confusingly, a *second*,
// envelope-level `requestId` (the human-readable display code, e.g. "CR123") that is NOT
// the same field as `changeRequest.requestId` (usually empty). `ChangeRequest` flattens
// all of that into the shape the rest of the app wants via a custom Decodable init, so
// views/view-models just see plain `cr.title`, `cr.status`, etc.

struct ChangeRequest: Identifiable {
    let id: String                     // changeRequest.id (Int on the wire), stringified
    let requestNumber: String          // envelope-level `requestId` display code
    let title: String                  // changeRequest.shortDescription
    let description: String?           // changeRequest.description
    let status: ChangeRequestStatus
    let severity: String?              // severityData.type (a resolved label, not on changeRequest itself)
    let requestTypeLabel: String?      // requestTypeData.type (ditto)
    let requestedByUserId: String?     // changeRequest.requestedBy — a user id, resolved to a
                                        // name+avatar via the response's top-level userProfile
                                        // dict (see ChangeRequestService.resolveNames)
    var createdByName: String?
    var createdByAvatarURL: String? = nil  // userProfile[requestedBy].profileImage
    let projectId: String?             // changeRequest.projectId — resolved to a name via a
                                        // separate /rest/trm/v1/projects fetch (no name field
                                        // comes back with the change request itself); only
                                        // populated on the single-item detail fetch — trm's own
                                        // list screen (changeRequestHome.js) never shows project
                                        // name, so the list fetch doesn't resolve it either
    var projectName: String?
    let platforms: [ChangeRequestPlatform]  // changeRequest.platform — SAP systems this request
                                             // touches; labeled literally "platform" in trm's
                                             // own UI, not "source system"
    let timeline: [ChangeRequestTimelineEntry]  // the "activity log" — embedded per-request,
                                                 // not a separate endpoint like the original guess
    let createdAt: Date?  // changeRequest.createdAt — real field, confirmed from a live response,
                           // despite trm's own frontend never reading it (it only uses per-event
                           // userTimeline dates) — trust the wire over the frontend's usage here.
    let stage: Int?           // changeRequest.stage — UNCONFIRMED key name (no live sample seen
    let totalStages: Int?     // changeRequest.totalStages — for this one, unlike the rest of this
    let stageStatus: String?  // changeRequest.stageStatus — struct); decoded defensively so a
                               // wrong guess just hides the Stage row instead of breaking decode.
    var isArchived: Bool = false  // changeRequest.archive — same field the archive/unarchive
                                    // update action sets; defaults false so older fixtures
                                    // constructed before this field existed still compile.
    var ticketUrl: String? = nil  // changeRequest.ticketUrl — the external ticket link the
                                   // web shows on detail and prefills on edit.
    var currentStage: RQStage? = nil  // envelope `stage[0].stage` — the stage the request is at
    var stages: [RQStage] = []        // envelope `stageData` — every stage, in order
    var currentStageOwnerName: String? = nil  // envelope `stage[0].user.name`

    /// The web offers Edit and Delete only at the first stage (changeRequestDetail.js). A
    /// request with no stages (created without a template) has nothing to be past.
    var isAtFirstStage: Bool { currentStage.map { $0.order == 1 } ?? true }

    /// Prefers the real `createdAt` field; falls back to the earliest timeline entry only if
    /// that's ever absent (defensive — trm's frontend suggests it might not always be sent).
    var submittedAt: Date? {
        createdAt ?? timeline.compactMap(\.createdAt).min()
    }

    static func == (lhs: ChangeRequest, rhs: ChangeRequest) -> Bool { lhs.id == rhs.id }
}

/// One step of a request's lifecycle (trm-backend-go `Stage`, changeRequest.go).
struct RQStage: Decodable, Hashable {
    let order: Int
    let description: String
    let statusCode: String
    let completed: Bool
    let current: Bool
    let ownerId: String?
    let qaDeploy: Bool

    private enum CodingKeys: String, CodingKey {
        case order, description, statusCode, completed, current, owner, qaDeploy
    }

    init(order: Int, description: String, statusCode: String = "", completed: Bool = false,
         current: Bool = false, ownerId: String? = nil, qaDeploy: Bool = false) {
        self.order = order
        self.description = description
        self.statusCode = statusCode
        self.completed = completed
        self.current = current
        self.ownerId = ownerId
        self.qaDeploy = qaDeploy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? c.decode(Int.self, forKey: .order)) ?? 0
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        statusCode = (try? c.decodeIfPresent(String.self, forKey: .statusCode)) ?? ""
        completed = (try? c.decodeIfPresent(Bool.self, forKey: .completed)) ?? false
        current = (try? c.decodeIfPresent(Bool.self, forKey: .current)) ?? false
        // A uuid.NullUUID: a plain string, or null when unassigned.
        ownerId = ((try? c.decodeIfPresent(String.self, forKey: .owner)) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
        qaDeploy = (try? c.decodeIfPresent(Bool.self, forKey: .qaDeploy)) ?? false
    }
}

/// The envelope's `stage` entries pair a stage with its owner's profile.
private struct RQStageEntry: Decodable {
    struct Owner: Decodable { let name: String? }
    let stage: RQStage?
    let user: Owner?
}

/// One application the request touches (an `application` row, copied onto the request):
/// whether it's an SAP system and whether it deploys through Git decide what Deploy to QA
/// does on the web.
struct ChangeRequestPlatform: Codable, Hashable {
    var id: String? = nil
    let description: String?
    var isSAP = false
    var usesGit = false

    private enum CodingKeys: String, CodingKey { case id, description, sap, git }

    init(id: String? = nil, description: String?, isSAP: Bool = false, usesGit: Bool = false) {
        self.id = id
        self.description = description
        self.isSAP = isSAP
        self.usesGit = usesGit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? nil
        isSAP = (try? c.decodeIfPresent(Bool.self, forKey: .sap)) ?? false
        usesGit = (try? c.decodeIfPresent(Bool.self, forKey: .git)) ?? false
    }

    /// As the web's create form sends a selected application: `{id, description, sap, git}`.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(isSAP, forKey: .sap)
        try c.encode(usesGit, forKey: .git)
    }
}

extension ChangeRequest: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ChangeRequest: Decodable {
    private enum EnvelopeKeys: String, CodingKey {
        case changeRequest, requestId, severityData, requestTypeData, userTimeline
        case stage, stageData
    }
    private enum CoreKeys: String, CodingKey {
        case id, description, shortDescription, status, requestedBy, projectId, platform, createdAt
        case stage, totalStages, stageStatus, archive, ticketUrl
    }
    private enum LabelKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let envelope = try decoder.container(keyedBy: EnvelopeKeys.self)
        let core = try envelope.nestedContainer(keyedBy: CoreKeys.self, forKey: .changeRequest)

        let rawId = try core.decode(Int.self, forKey: .id)
        id = String(rawId)
        requestNumber = (try? envelope.decodeIfPresent(String.self, forKey: .requestId)) ?? id
        title = (try? core.decodeIfPresent(String.self, forKey: .shortDescription)) ?? ""
        description = (try? core.decodeIfPresent(String.self, forKey: .description)) ?? nil
        let rawStatus = (try? core.decodeIfPresent(String.self, forKey: .status)) ?? nil
        status = ChangeRequestStatus(raw: rawStatus ?? "")
        requestedByUserId = (try? core.decodeIfPresent(String.self, forKey: .requestedBy)) ?? nil
        createdByName = nil
        createdByAvatarURL = nil
        if let intProjectId = try? core.decode(Int.self, forKey: .projectId) {
            projectId = String(intProjectId)
        } else {
            projectId = (try? core.decodeIfPresent(String.self, forKey: .projectId)) ?? nil
        }
        projectName = nil
        platforms = (try? core.decodeIfPresent([ChangeRequestPlatform].self, forKey: .platform)) ?? []
        createdAt = (try? core.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil
        let entries = (try? envelope.decodeIfPresent([RQStageEntry].self, forKey: .stage)) ?? nil
        currentStage = entries?.compactMap(\.stage).first
        currentStageOwnerName = entries?.first?.user?.name.flatMap { $0.isEmpty ? nil : $0 }
        stages = ((try? envelope.decodeIfPresent([RQStage].self, forKey: .stageData)) ?? nil)?
            .sorted { $0.order < $1.order } ?? []
        // The real data is the envelope's stage/stageData; the core keys are the earlier guess.
        stage = (try? core.decodeIfPresent(Int.self, forKey: .stage)) ?? currentStage?.order
        totalStages = (try? core.decodeIfPresent(Int.self, forKey: .totalStages))
            ?? (stages.isEmpty ? nil : stages.count)
        stageStatus = (try? core.decodeIfPresent(String.self, forKey: .stageStatus))
            ?? currentStage.flatMap { $0.description.isEmpty ? nil : $0.description }
        isArchived = (try? core.decodeIfPresent(Bool.self, forKey: .archive)) ?? false
        ticketUrl = (try? core.decodeIfPresent(String.self, forKey: .ticketUrl)) ?? nil

        if let severityContainer = try? envelope.nestedContainer(keyedBy: LabelKeys.self, forKey: .severityData) {
            severity = (try? severityContainer.decodeIfPresent(String.self, forKey: .type)) ?? nil
        } else {
            severity = nil
        }
        if let typeContainer = try? envelope.nestedContainer(keyedBy: LabelKeys.self, forKey: .requestTypeData) {
            requestTypeLabel = (try? typeContainer.decodeIfPresent(String.self, forKey: .type)) ?? nil
        } else {
            requestTypeLabel = nil
        }
        timeline = (try? envelope.decodeIfPresent([ChangeRequestTimelineEntry].self, forKey: .userTimeline)) ?? []
    }
}

// Fixtures/tests construct ChangeRequest via the compiler-synthesized memberwise init
// (the custom Decodable init above lives in an extension, so it doesn't suppress it).

/// The full real status vocabulary, confirmed against trm's own Kanban board keys
/// (changeRequestHome.js's `taskList` state: blocked/planned/inprogress/completed) and its
/// list-view label mapping — only four values exist on the wire, not the larger guessed set
/// this used to carry.
enum ChangeRequestStatus: Hashable {
    case blocked
    case planned
    case inProgress
    case completed
    /// Anything the wire sends that doesn't match a known case — displayed as-is rather
    /// than silently dropped or crashing decode.
    case other(String)

    /// Matches trm's own Kanban column order (changeRequestHome.js's `taskList` state).
    static var allCases: [ChangeRequestStatus] {
        [.blocked, .planned, .inProgress, .completed]
    }

    init(raw: String) {
        let normalized = raw.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "blocked": self = .blocked
        case "planned": self = .planned
        case "inprogress", "progress": self = .inProgress
        case "completed", "complete": self = .completed
        default: self = .other(raw)
        }
    }

    /// The exact wire value — used to build server-side filter query params
    /// (matches trm's own lowercase, no-separator status strings).
    var rawValue: String {
        switch self {
        case .blocked: return "blocked"
        case .planned: return "planned"
        case .inProgress: return "inprogress"
        case .completed: return "completed"
        case .other(let raw): return raw
        }
    }

    /// Matches trm's own list-view label mapping exactly: `inprogress` → "In Progress",
    /// everything else shown as-is with CSS `text-transform: capitalize`.
    var displayName: String {
        switch self {
        case .blocked: return "Blocked"
        case .planned: return "Planned"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .other(let raw): return raw.isBlank ? "Unknown" : raw.capitalized
        }
    }
}

/// One entry in a change request's embedded activity/status-change timeline
/// (`userTimeline` in the wire format) — this *is* the "logs" feature, there's no
/// separate logs endpoint.
/// trm-backend-go never sends a combined action phrase ("edited Order") — just a raw
/// `fieldName` key ("status", "stage", or another field's name) plus `fromStatus`/
/// `toStatus` (confirmed against trm-backend-go's `Timeline` struct, timeline.go:44-53).
/// trm web's own frontend derives "created"/"edited"/"moved status to" client-side from
/// those three values (changeRequestDetail.js:1161-1191) — `actionVerb`/`actionDetail`
/// below replicate that exact branching rather than assuming any phrase arrives pre-built.
struct ChangeRequestTimelineEntry: Identifiable {
    let id = UUID()
    let userName: String?
    let fieldName: String?
    let fromStatus: String?
    let toStatus: String?
    let createdAt: Date?

    var actionVerb: String {
        switch fieldName {
        case "status": return fromStatus == "created" ? "created" : "edited"
        case "stage": return "moved status to"
        // A stage move or owner change (trm-backend-go compareStageFields: tableName
        // "stage", values like "stage-QA" and "stage-QA-owner-<uuid>").
        case "order": return "moved the request to"
        case "owner": return "changed the stage owner"
        default: return "edited"
        }
    }

    var actionDetail: String? {
        switch fieldName {
        case "status":
            guard fromStatus != "created" else { return nil }
            return toStatus.map { "status to \($0)" }
        case "stage":
            return toStatus
        case "order":
            return toStatus.map { $0.hasPrefix("stage-") ? String($0.dropFirst("stage-".count)) : $0 }
        case "owner":
            return nil
        default:
            return fieldName
        }
    }
}

extension ChangeRequestTimelineEntry: Decodable {
    private enum EnvelopeKeys: String, CodingKey {
        case user, timeline
    }
    private enum UserKeys: String, CodingKey {
        case name
    }
    private enum TimelineKeys: String, CodingKey {
        case fieldName, fromStatus, toStatus, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: EnvelopeKeys.self)
        if let userContainer = try? container.nestedContainer(keyedBy: UserKeys.self, forKey: .user) {
            userName = (try? userContainer.decodeIfPresent(String.self, forKey: .name)) ?? nil
        } else {
            userName = nil
        }
        if let timelineContainer = try? container.nestedContainer(keyedBy: TimelineKeys.self, forKey: .timeline) {
            fieldName = (try? timelineContainer.decodeIfPresent(String.self, forKey: .fieldName)) ?? nil
            fromStatus = (try? timelineContainer.decodeIfPresent(String.self, forKey: .fromStatus)) ?? nil
            toStatus = (try? timelineContainer.decodeIfPresent(String.self, forKey: .toStatus)) ?? nil
            createdAt = (try? timelineContainer.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil
        } else {
            fieldName = nil
            fromStatus = nil
            toStatus = nil
            createdAt = nil
        }
    }
}

// MARK: - Change Request List / Detail Response Envelope

struct ChangeRequestListResponse: Decodable, EmptyDecodableResponse {
    let combinedResponse: [ChangeRequest]
    let userProfile: [String: UserProfileEntry]?

    static var empty: Self { Self(combinedResponse: [], userProfile: nil) }

    init(combinedResponse: [ChangeRequest], userProfile: [String: UserProfileEntry]?) {
        self.combinedResponse = combinedResponse
        self.userProfile = userProfile
    }

    private enum CodingKeys: String, CodingKey {
        case combinedResponse, userProfile
    }

    /// A filter match with zero rows comes back as `combinedResponse: null` (confirmed live,
    /// e.g. the Archive tab with no archived requests) rather than `[]` — decoding `null`
    /// into a non-optional array throws, which used to surface as a "Failed to parse
    /// response" alert for what is really just an empty result. `decodeIfPresent` treats a
    /// present-but-null value the same as a missing key, so both collapse to `[]` here.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        combinedResponse = try container.decodeIfPresent([ChangeRequest].self, forKey: .combinedResponse) ?? []
        userProfile = try container.decodeIfPresent([String: UserProfileEntry].self, forKey: .userProfile)
    }
}

struct UserProfileEntry: Decodable {
    let name: String?
    let profileImage: String?
}

// MARK: - Projects
// GET /rest/trm/v1/projects — a change request only carries a projectId; the display name
// comes from this separate list, joined client-side (same pattern as requestedBy → userProfile).

struct RQProject: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    /// The project's Git repositories, offered on the New Request form for a Git platform.
    var repos: [String] = []

    private enum CodingKeys: String, CodingKey {
        case id, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Untitled Project"
    }
}

extension RQProject {
    init(id: String, name: String, repos: [String] = []) {
        self.id = id
        self.name = name
        self.repos = repos
    }
}

// MARK: - Comments
// GET /comments/change-request/{id} returns `{"comments": [...]}`, not a bare array.
// Each comment's body is HTML (the web app renders it via dangerouslySetInnerHTML), and
// the author is a nested `user` object, not flat author_name/author_id strings.

struct RQComment: Identifiable {
    let id: String
    let bodyHTML: String
    let authorName: String?
    let createdAt: Date?
    let attachments: [RQAttachment]

    /// Strips HTML tags for a readable plain-text display until a proper HTML renderer
    /// is worth adding.
    var plainTextBody: String {
        bodyHTML
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension RQComment: Hashable {
    static func == (lhs: RQComment, rhs: RQComment) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension RQComment: Decodable {
    private enum CodingKeys: String, CodingKey {
        case comment, createdAt, user, attachments
    }
    private enum UserKeys: String, CodingKey {
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The API doesn't appear to return a stable per-comment id (trm's own frontend
        // keys comment rows off array index) — synthesize one for SwiftUI List identity.
        id = UUID().uuidString
        bodyHTML = (try? container.decodeIfPresent(String.self, forKey: .comment)) ?? ""
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil
        if let userContainer = try? container.nestedContainer(keyedBy: UserKeys.self, forKey: .user) {
            authorName = (try? userContainer.decodeIfPresent(String.self, forKey: .name)) ?? nil
        } else {
            authorName = nil
        }
        attachments = (try? container.decodeIfPresent([RQAttachment].self, forKey: .attachments)) ?? []
    }
}

/// Plain constructor for fixtures/tests and for the optimistic local comment appended
/// right after a successful post (see CommentService.postComment — the create endpoint's
/// response shape isn't confirmed, so posting doesn't try to decode one back).
extension RQComment {
    init(bodyHTML: String, authorName: String?, createdAt: Date?, attachments: [RQAttachment] = []) {
        self.id = UUID().uuidString
        self.bodyHTML = bodyHTML
        self.authorName = authorName
        self.createdAt = createdAt
        self.attachments = attachments
    }
}

struct NewCommentRequest: Encodable {
    /// `{read, userId}` — trm-backend-go's Mention, as the web's comment box sends it.
    struct Mention: Encodable, Equatable {
        var read = false
        let userId: String
    }

    let comment: String
    let createdBy: String
    let changeRequestId: Int
    var mentions: [Mention] = []
    var attachments: [CommentAttachmentRef] = []
}

/// A comment's text with the people @mentioned in it. The web's editor (react-draft-wysiwyg
/// → draftjs-to-html) posts HTML with each mention as
/// `<a href="{userId}" class="wysiwyg-mention" data-mention data-value="{name}">@{name}</a>`;
/// this builds the same markup, so a mention reads the same on the web.
enum CommentComposition {
    /// The mentions still present in `text` as "@Name", in order, without repeats. Longer
    /// names match first and use up their text, so "@Ann Lee" doesn't also mention "Ann".
    static func mentions(in text: String, from candidates: [ProjectTeamMember]) -> [ProjectTeamMember] {
        var remaining = text
        var found: [(person: ProjectTeamMember, offset: Int)] = []
        for person in candidates.sorted(by: { $0.name.count > $1.name.count }) where !person.name.isEmpty {
            let tag = "@" + person.name
            guard let first = remaining.range(of: tag),
                  !found.contains(where: { $0.person.id == person.id }) else { continue }
            found.append((person, remaining.distance(from: remaining.startIndex, to: first.lowerBound)))
            remaining = remaining.replacingOccurrences(of: tag, with: String(repeating: " ", count: tag.count))
        }
        return found.sorted { $0.offset < $1.offset }.map(\.person)
    }

    /// The body to post: the plain text unchanged when nobody is mentioned (as the app has
    /// always sent it), otherwise escaped HTML with the mention links, in a paragraph.
    static func body(for text: String, mentioning people: [ProjectTeamMember]) -> String {
        guard !people.isEmpty else { return text }
        // One pass, left to right; at each "@" the longest matching name wins, so
        // "@Ann Lee" is never split into a link for "Ann".
        let byLength = people.filter { !$0.name.isEmpty }.sorted { $0.name.count > $1.name.count }
        var html = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "@",
               let person = byLength.first(where: { text[index...].hasPrefix("@" + $0.name) }) {
                let name = escape(person.name)
                html += "<a href=\"\(escape(person.id))\" class=\"wysiwyg-mention\" data-mention data-value=\"\(name)\">@\(name)</a>"
                index = text.index(index, offsetBy: person.name.count + 1)
            } else {
                html += text[index] == "\n" ? "<br>" : escape(String(text[index]))
                index = text.index(after: index)
            }
        }
        return "<p>" + html + "</p>"
    }

    /// The text being typed after an "@" at the end of `text`, or nil when not mentioning.
    static func activeQuery(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let query = text[text.index(after: at)...]
        guard !query.contains("\n"), query.count <= 40 else { return nil }
        return String(query)
    }

    /// `text` with the trailing "@query" replaced by the chosen person's "@Name ".
    static func complete(_ text: String, with person: ProjectTeamMember) -> String {
        guard let at = text.lastIndex(of: "@") else { return text }
        return String(text[..<at]) + "@" + person.name + " "
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// `{id, fileName}` — confirmed against trm-backend-go's `Attach` struct (commentsPost.go);
/// note the field is `fileName` here, not `name` like the read-side `RQAttachment` below.
struct CommentAttachmentRef: Encodable {
    let id: String
    let fileName: String
}

// MARK: - Attachments
// Confirmed shape is minimal — `{id, name}` — from trm's own comment-attachment usage.
// Real download goes through trm-backend-go's `/file/{id}` directly, which is not
// necessarily reachable from a mobile client sitting behind trm-gw the way the web app's
// same-origin browser session reaches it — no working download path is wired up yet.

struct RQAttachment: Identifiable {
    let id: String
    let fileName: String
}

extension RQAttachment: Hashable {}

extension RQAttachment: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, fileName
    }

    /// Comment attachments name the file `name`; a message's attachments are stored as
    /// the web sent them, `{id, fileName}`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        fileName = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil)
            ?? ((try? container.decodeIfPresent(String.self, forKey: .fileName)) ?? nil)
            ?? "Attachment"
    }
}

// MARK: - Generic File Upload / Download (Postgres `files` table — comment attachments)
// POST /rest/trm/v1/upload -> {"file": [{id, name, mimeType, ...}]}
// GET  /rest/trm/v1/file/{id} -> {"file": [{id, name, mimeType, data (base64), ...}]}
// Confirmed against trm-backend-go's filesUpload.go `File` struct and trm's own
// changeRequestComments.js upload/download handlers.

struct FileUploadResponse: Decodable {
    let file: [UploadedFileEntry]
}

struct UploadedFileEntry: Decodable {
    let id: String
    let name: String

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Attachment"
    }
}

struct FileDownloadResponse: Decodable {
    let file: [DownloadedFileEntry]
}

struct DownloadedFileEntry: Decodable {
    let name: String
    let mimeType: String?
    /// Base64-encoded file bytes — the web app does `atob(data)` client-side; Swift decodes
    /// this straight to `Data` via the default base64 `Decodable` conformance.
    let data: Data
}

// MARK: - Reference / Lookup Data
// Populate the Create/Edit Change Request pickers. All three are direct-gateway GETs
// (same `/rest/trm/v1/...` family as /projects and /user), confirmed against trm's own
// createUpdateChangeRequestForm.js. Decoded defensively (id/type/name only) — everything
// else these endpoints return (createdAt, department, team, etc.) is unused by a picker.

struct RequestTypeOption: Identifiable, Decodable, Hashable {
    let id: String
    let type: String

    private enum CodingKeys: String, CodingKey { case id, type }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "Unknown"
    }
}

struct SeverityOption: Identifiable, Decodable, Hashable {
    let id: String
    let type: String

    private enum CodingKeys: String, CodingKey { case id, type }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "Unknown"
    }
}

struct UserOption: Identifiable, Decodable, Hashable {
    let id: String
    let name: String

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Unknown"
    }
}

extension RequestTypeOption {
    init(id: String, type: String) {
        self.id = id
        self.type = type
    }
}

extension SeverityOption {
    init(id: String, type: String) {
        self.id = id
        self.type = type
    }
}

extension UserOption {
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

struct RequestTypeListResponse: Decodable, EmptyDecodableResponse {
    let requestTypes: [RequestTypeOption]
    static var empty: Self { Self(requestTypes: []) }
    init(requestTypes: [RequestTypeOption]) { self.requestTypes = requestTypes }
    private enum CodingKeys: String, CodingKey { case requestTypes }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestTypes = try container.decodeIfPresent([RequestTypeOption].self, forKey: .requestTypes) ?? []
    }
}

struct SeverityListResponse: Decodable, EmptyDecodableResponse {
    let severities: [SeverityOption]
    static var empty: Self { Self(severities: []) }
    init(severities: [SeverityOption]) { self.severities = severities }
    private enum CodingKeys: String, CodingKey { case severities }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severities = try container.decodeIfPresent([SeverityOption].self, forKey: .severities) ?? []
    }
}


// MARK: - Project Detail
// GET /rest/trm/v1/projects?id={id} — same endpoint/family as the already-working project
// list call, just filtered to one row. Confirmed against trm's own projectDetails.js: the
// page shows name/type/team/jira/description, but deliberately does NOT use this response's
// embedded `changeRequests` array for the CR list (too thin — no severity/type/stage joins);
// that list comes from a separate ChangeRequestService fetch scoped by projectId instead.

struct ProjectDetail: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let jira: String?
    let projectTypeLabel: String?
    let ownerName: String?
    let requestCount: Int?
    let team: [ProjectTeamMember]
    var repos: [String] = []
}

/// `projectUsers` entries — confirmed against trm-backend-go's `projectUser` struct
/// (`projectUsers.go:11-15`): `{id, name, ProfileImage}`. Note the capitalized `ProfileImage`
/// JSON key — inconsistent with `profileImage` used elsewhere in this backend (e.g.
/// `UserProfileEntry`), but that's the real, confirmed wire key for this specific struct.
struct ProjectTeamMember: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let profileImageURL: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case profileImageURL = "ProfileImage"
    }
}

extension ProjectDetail: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, description, jira, projectTypeData, ownerUser, requestCount, projectUsers, repos
    }
    private enum LabelKeys: String, CodingKey { case description }
    private enum UserKeys: String, CodingKey { case name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Untitled Project"
        description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? nil
        jira = (try? container.decodeIfPresent(String.self, forKey: .jira)) ?? nil
        requestCount = (try? container.decodeIfPresent(Int.self, forKey: .requestCount)) ?? nil
        team = (try? container.decodeIfPresent([ProjectTeamMember].self, forKey: .projectUsers)) ?? []
        repos = ((try? container.decodeIfPresent([String].self, forKey: .repos)) ?? nil)?
            .filter { !$0.isEmpty } ?? []

        if let typeContainer = try? container.nestedContainer(keyedBy: LabelKeys.self, forKey: .projectTypeData) {
            projectTypeLabel = (try? typeContainer.decodeIfPresent(String.self, forKey: .description)) ?? nil
        } else {
            projectTypeLabel = nil
        }
        if let ownerContainer = try? container.nestedContainer(keyedBy: UserKeys.self, forKey: .ownerUser) {
            ownerName = (try? ownerContainer.decodeIfPresent(String.self, forKey: .name)) ?? nil
        } else {
            ownerName = nil
        }
    }
}

/// Live-confirmed 2026-09-09: unlike every other list endpoint in this app (which wrap their
/// collection in a named key, e.g. `{"projects": [...]}` on the direct-gateway route this BFF
/// route replaced), the BFF-proxied `GET /projects` (and, confirmed the same day, `GET /teams`)
/// returns a **bare JSON array** at the root — trm-bff's passthrough forwards trm-backend-go's
/// raw `[]Project`/`[]TeamWithMembers` encoding verbatim, without the direct-gateway route's
/// "collection" response-wrapping. Decoding these as plain arrays (not a wrapper struct) is the
/// honest representation of the wire shape, not a simplification. One unconstrained
/// conformance covers every element type — Swift doesn't allow two separate conditional
/// `Array: EmptyDecodableResponse` conformances for different concrete `Element`s in the same
/// module, and `[]` is a valid `empty` for any element type anyway.
extension Array: EmptyDecodableResponse {
    static var empty: Self { [] }
}

// MARK: - Change Request Create / Update
// POST /rest/trm/v1/change-request/create and PUT /rest/trm/v1/change-request — both
// direct-gateway, confirmed against trm's own createUpdateChangeRequestForm.js. Create sends
// only the fields a human is actually required to fill in on the real web form (see the
// trm-ios plan's field-scope table) — platform/SAP/git/template fields are optional even
// there and are deliberately not exposed here. Update sends a partial payload — only the
// changed field(s) plus id/CreatedBy/UpdatedBy — matching the backend's GORM `.Updates(c)`
// partial-write behavior and how the real web app's own Kanban-drag status change and
// archive toggle already call this same endpoint.

/// The create endpoint's response is the flat created `ChangeRequest` Go struct, not the
/// `combinedResponse`-wrapped envelope the list/detail endpoint returns — decoded just for
/// `id` here, which is all that's needed to immediately re-fetch the new row through the
/// existing, proven `changeRequest(id:)` path and get the fully-resolved (severity/type/
/// owner-name) version the rest of the app expects.
///
/// A failed create still answers 200, with the backend's error list
/// `[{"status":"error","message":…}]`; that decodes with `id` nil and the message kept.
struct CreatedChangeRequestResponse: Decodable {
    let id: Int?
    let errorMessage: String?

    private struct ErrorEntry: Decodable { let message: String? }
    private enum CodingKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        if let entries = try? decoder.singleValueContainer().decode([ErrorEntry].self) {
            id = nil
            errorMessage = entries.first?.message ?? "The request couldn't be created."
            return
        }
        id = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .id)
        errorMessage = nil
    }
}

/// POST /rest/trm/v1/change-request/create, as the web's createUpdateChangeRequestForm sends
/// it. `projectId` is a number on the wire (trm-backend-go decodes it into an int).
struct NewChangeRequestPayload: Encodable {
    /// A template stage as the request's own stage: the first is current, and the owner is
    /// left out when unassigned (the backend reads `owner` as a nullable UUID).
    struct Stage: Encodable, Equatable {
        let order: Int
        let description: String
        let statusCode: String
        let qaDeploy: Bool
        let owner: String?
        let current: Bool
        let completed = false
        let updatedBy: String

        private enum CodingKeys: String, CodingKey {
            case order, description, statusCode, qaDeploy, owner, current, completed, updatedBy
        }
    }

    /// `system` is "qa" or "prd"; the web always sends both.
    struct DeploymentBranch: Encodable, Equatable {
        let system: String
        var source = ""
        var target = ""
    }

    let shortDescription: String
    let description: String
    let projectId: Int
    let requestType: String
    let severity: String
    let requestedBy: String
    let createdBy: String
    let ticketUrl: String
    var archive = false
    var platform: [ChangeRequestPlatform] = []
    /// A template id, or nil for a request without stages.
    var template: String?
    var stage: [Stage] = []
    /// The optional request number; the backend refuses one already in use.
    var requestId = ""
    var deploymentBranches = [DeploymentBranch(system: "qa"), DeploymentBranch(system: "prd")]
    var repo = ""
    /// Only sent for an SAP platform.
    var sapSourceSystemId: String?
    /// The column's own default. trm-backend-go's synchronous create path otherwise inserts
    /// "", which the `enum_quality_check_status` column refuses.
    let qualityCheck = "pending"

    var updatedBy: String { createdBy }

    private enum CodingKeys: String, CodingKey {
        case shortDescription, description, projectId, requestType, severity, requestedBy, createdBy
        case updatedBy, ticketUrl, archive, platform, template, stage, requestId, deploymentBranches, repo
        case sapSourceSystemId, qualityCheck
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shortDescription, forKey: .shortDescription)
        try c.encode(description, forKey: .description)
        try c.encode(projectId, forKey: .projectId)
        try c.encode(requestType, forKey: .requestType)
        try c.encode(severity, forKey: .severity)
        try c.encode(requestedBy, forKey: .requestedBy)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(updatedBy, forKey: .updatedBy)
        try c.encode(ticketUrl, forKey: .ticketUrl)
        try c.encode(archive, forKey: .archive)
        try c.encode(platform, forKey: .platform)
        try c.encode(template, forKey: .template)  // null without a template, as the web sends
        try c.encode(stage, forKey: .stage)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(deploymentBranches, forKey: .deploymentBranches)
        try c.encode(repo, forKey: .repo)
        try c.encodeIfPresent(sapSourceSystemId, forKey: .sapSourceSystemId)
        try c.encode(qualityCheck, forKey: .qualityCheck)
    }
}

/// All-optional so only the fields actually being changed get encoded — `CreatedBy`/
/// `UpdatedBy` (capitalized; matches the exact keys trm's own web frontend sends on every
/// update call, confirmed against changeRequestPut.go) are always included.
/// PUT /rest/trm/v1/change-request-delete — the web sends the numeric id.
struct ChangeRequestDeletePayload: Encodable {
    let id: Int
    let updatedBy: String
}

struct ChangeRequestUpdatePayload: Encodable {
    var shortDescription: String?
    var description: String?
    var requestType: String?
    var severity: String?
    var requestedBy: String?
    var ticketUrl: String?
    var status: String?
    var archive: Bool?
    let createdBy: String
    let updatedBy: String

    private enum CodingKeys: String, CodingKey {
        case id, shortDescription, description, requestType, severity, requestedBy, ticketUrl, status, archive
        case createdBy = "CreatedBy"
        case updatedBy = "UpdatedBy"
    }

    let id: String

    init(
        id: String,
        createdBy: String,
        updatedBy: String,
        shortDescription: String? = nil,
        description: String? = nil,
        requestType: String? = nil,
        severity: String? = nil,
        requestedBy: String? = nil,
        ticketUrl: String? = nil,
        status: String? = nil,
        archive: Bool? = nil
    ) {
        self.id = id
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.shortDescription = shortDescription
        self.description = description
        self.requestType = requestType
        self.severity = severity
        self.requestedBy = requestedBy
        self.ticketUrl = ticketUrl
        self.status = status
        self.archive = archive
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // A number on the wire: trm-backend-go decodes `id` into an int, and a string fails
        // the whole update ("decode failed", in a 200 body).
        if let numericId = Int(id) {
            try container.encode(numericId, forKey: .id)
        } else {
            try container.encode(id, forKey: .id)
        }
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(updatedBy, forKey: .updatedBy)
        try container.encodeIfPresent(shortDescription, forKey: .shortDescription)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(requestType, forKey: .requestType)
        try container.encodeIfPresent(severity, forKey: .severity)
        try container.encodeIfPresent(requestedBy, forKey: .requestedBy)
        try container.encodeIfPresent(ticketUrl, forKey: .ticketUrl)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(archive, forKey: .archive)
    }
}

// MARK: - Teams
// GET /teams (BFF-proxied, unprefixed) — confirmed registered in trm-bff's *production*
// config.yaml (unlike a couple of sibling BFF routes found dead there this session), and
// confirmed via trm-gw's own template that, like BFF `/projects`, this one returns a
// **bare JSON array** (no `is_collection`/`mapping` wrapping, unlike the direct-gateway
// `/rest/trm/v1/teams` route, which wraps in `{"teams": [...]}`) — decoded as `[RQTeam]`
// directly, not a wrapper struct, for the same reason as `ProjectDetail`.

struct RQTeam: Identifiable, Hashable {
    let id: String
    let name: String
    let members: [ProjectTeamMember]
}

extension RQTeam: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name
        case members = "membersDetails"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Untitled Team"
        // `UserDetail`'s wire key is lowercase `profileImage` (trm-backend-go's own
        // `UserDetail` struct) — distinct from `projectUser`'s oddly-capitalized
        // `ProfileImage` used by `ProjectTeamMember` above; decoding the same field name
        // twice with different casing per struct is a real, confirmed backend inconsistency,
        // not a typo here.
        members = (try? container.decodeIfPresent([TeamMemberDTO].self, forKey: .members))?
            .map { ProjectTeamMember(id: $0.id, name: $0.name, profileImageURL: $0.profileImage) } ?? []
    }
}

private struct TeamMemberDTO: Decodable {
    let id: String
    let name: String
    let profileImage: String?

    private enum CodingKeys: String, CodingKey { case id, name, profileImage }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Unknown"
        profileImage = (try? container.decodeIfPresent(String.self, forKey: .profileImage)) ?? nil
    }
}

// MARK: - CR-Level File Attachments (minio-backed — distinct from comment attachments)
// GET /rest/trm/v1/listchangeRequestFile + POST /rest/trm/v1/changeRequestAddFile — a
// separate store from the comment-attachment Postgres `files` table (see RQAttachment below).
// `url` is a pre-signed link the web app opens directly with no auth header — same here.

struct CRFile: Identifiable, Hashable {
    var id: String { url }
    let name: String
    let size: Int?
    let uploaderName: String?
    let url: String
}

extension CRFile: Decodable {
    private enum CodingKeys: String, CodingKey { case name, size, uploaderName, url }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "File"
        size = (try? container.decodeIfPresent(Int.self, forKey: .size)) ?? nil
        uploaderName = (try? container.decodeIfPresent(String.self, forKey: .uploaderName)) ?? nil
        url = (try? container.decodeIfPresent(String.self, forKey: .url)) ?? ""
    }
}

struct CRFileListResponse: Decodable, EmptyDecodableResponse {
    let files: [CRFile]
    static var empty: Self { Self(files: []) }
    init(files: [CRFile]) { self.files = files }
    private enum CodingKeys: String, CodingKey { case files }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        files = try container.decodeIfPresent([CRFile].self, forKey: .files) ?? []
    }
}

/// The upload response uses a *different*, singular envelope key (`"file"`) than the list
/// response's plural `"files"` — confirmed against trm's own `viewfiles.js` (`res.data.file[0]`
/// on upload vs. `res.data.files` on list).
struct CRFileUploadResponse: Decodable {
    let file: [CRFile]
}

// MARK: - Unread / Activity Badge
// POST /notifications/{userId}/requests/unread-count — a per-user POST, not the bare GET
// originally assumed. perCRUnreadCounts is an array of {crNumber, count} pairs, not a dict.

struct UnreadCounts: Decodable {
    let totalUnreadMessages: Int
    let perCRUnreadCounts: [PerChangeRequestUnreadCount]

    struct PerChangeRequestUnreadCount: Decodable {
        let crNumber: String
        let count: Int
    }

    func count(forChangeRequestId id: String) -> Int {
        perCRUnreadCounts.first { $0.crNumber == id }?.count ?? 0
    }
}

// MARK: - Releases
//
// Not a standalone entity — a "release" in trm is a change request tagged with a planned
// release date, normally shown as a drag-and-drop Kanban board (releaseHome.js) grouped by
// `plannedOn`. Confirmed fields (from groupReleasesByPlannedOn + the Kanban card renderer):
// plannedOn, changeRequestId, requestId (display code), status, name/description. No live
// sample was available to verify exact field casing/nullability against (unlike
// ChangeRequest) — decoded defensively, same posture as UserProfile: everything but the
// identifying id is optional and simply doesn't render if absent, rather than crashing.
//
// GET /rest/trm/v1/release (query: id, status) — chosen over the alternate BFF-fronted
// `/releases` path for the same reason as /rest/trm/v1/user and /rest/trm/v1/projects:
// consistent with the established "everything roots under our own /requests base, use the
// endpoint's literal un-prefixed path" convention. This is a call, not a confirmed fact —
// flag with trm-gw's owner if releases don't load once a real backend is reachable.

struct RQRelease: Identifiable, Decodable {
    let changeRequestId: String
    let requestId: String?
    let name: String?
    let description: String?
    let status: ReleaseStatus
    let plannedOn: Date?
    /// The request's platforms. Scheduling one that has any also deploys it on the web
    /// (SAP release control, or a Git merge to PRD), which the app doesn't drive yet.
    var platforms: [ChangeRequestPlatform] = []

    var id: String { changeRequestId }

    var needsWebToSchedule: Bool { !platforms.isEmpty }

    /// Falls back to the requestId display code, then a generic label — a release with
    /// neither a name nor a description is plausible (trm's own Kanban card falls back to
    /// the linked change request's own title in that case, which this model doesn't have).
    var title: String {
        name ?? description ?? requestId.map { "Request \($0)" } ?? "Untitled Release"
    }
}

extension RQRelease {
    private enum CodingKeys: String, CodingKey {
        case changeRequestId, requestId, name, description, status, plannedOn, platform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let intId = try? container.decode(Int.self, forKey: .changeRequestId) {
            changeRequestId = String(intId)
        } else {
            changeRequestId = (try? container.decode(String.self, forKey: .changeRequestId)) ?? UUID().uuidString
        }
        requestId = ((try? container.decodeIfPresent(String.self, forKey: .requestId)) ?? nil)
            .flatMap { $0.isEmpty ? nil : $0 }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? nil
        let rawStatus = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil
        status = ReleaseStatus(raw: rawStatus ?? "")
        plannedOn = (try? container.decodeIfPresent(Date.self, forKey: .plannedOn)) ?? nil
        platforms = (try? container.decodeIfPresent([ChangeRequestPlatform].self, forKey: .platform)) ?? []
    }

    // Fixtures/tests construct RQRelease via the compiler-synthesized memberwise init (the
    // custom Decodable init above lives in this extension, so it doesn't suppress it).
}

struct ReleaseListResponse: Decodable, EmptyDecodableResponse {
    let releases: [RQRelease]

    static var empty: Self { Self(releases: []) }

    init(releases: [RQRelease]) {
        self.releases = releases
    }

    private enum CodingKeys: String, CodingKey {
        case releases
    }

    /// Same defensive-null handling as ChangeRequestListResponse — a null array reads as
    /// empty, not a parse failure.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = (try? container.decodeIfPresent([Entry].self, forKey: .releases)) ?? nil
        releases = (entries ?? []).flatMap(\.releases)
    }

    /// GET /release answers `[{"releases": [...]}, {"plannedCount", …}]` (the web reads
    /// `releases[0].releases`), wrapped by the gateway as `{"releases": that}`. A flat
    /// release in the outer list is kept too; the counts entry holds no releases.
    private struct Entry: Decodable {
        let releases: [RQRelease]

        private enum Keys: String, CodingKey { case releases, changeRequestId }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            if c.contains(.releases) {
                releases = (try? c.decode([RQRelease].self, forKey: .releases)) ?? []
            } else if c.contains(.changeRequestId) {
                releases = [try RQRelease(from: decoder)]
            } else {
                releases = []
            }
        }
    }
}

// MARK: - Release Settings
// The web's release settings drawer (releases/releasesSetting.js): the regular release
// cycle (GET/PUT /release-cycle, one row) and one-off custom releases (GET/POST
// /custom-release).

enum ReleaseFrequency: String, CaseIterable, Identifiable {
    case weekly, biweekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Bi weekly"
        case .monthly: return "Monthly"
        }
    }
    /// Weekly and bi weekly releases fall on a weekday; monthly ones on a day of the month.
    var usesWeekday: Bool { self != .monthly }
}

enum ReleaseWeekday: String, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: String { rawValue }
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// A release time as the web writes it: the hour and minute as picked on the device,
/// labelled `+00` (`H:M:00+00`). The web reads it back the same way, ignoring the zone, so
/// the app does too and both show the same time.
struct ReleaseTime: Equatable {
    var hour: Int
    var minute: Int

    var wireValue: String { String(format: "%02d:%02d:00+00", hour, minute) }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init?(wire: String?) {
        let parts = (wire ?? "").split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1].prefix(2)),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    func date(on day: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

/// The release cycle, as GET /release-cycle returns it (`{"releases": [cycle]}` via the
/// gateway).
struct RQReleaseCycle: Decodable, Equatable {
    var frequency: ReleaseFrequency
    var day: ReleaseWeekday
    /// Day of the month, for a monthly cycle.
    var dayOfMonth: Int?
    var time: ReleaseTime?
    var systemRetry: Bool
    var manualRetry: Bool
    var attempts: Int

    static let `default` = RQReleaseCycle(frequency: .weekly, day: .friday, dayOfMonth: nil,
                                          time: ReleaseTime(hour: 18, minute: 0),
                                          systemRetry: false, manualRetry: false, attempts: 1)

    init(frequency: ReleaseFrequency, day: ReleaseWeekday, dayOfMonth: Int?, time: ReleaseTime?,
         systemRetry: Bool, manualRetry: Bool, attempts: Int) {
        self.frequency = frequency
        self.day = day
        self.dayOfMonth = dayOfMonth
        self.time = time
        self.systemRetry = systemRetry
        self.manualRetry = manualRetry
        self.attempts = attempts
    }

    private enum CodingKeys: String, CodingKey { case frequency, day, date, time, systemRetry, manualRetry, attempts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        frequency = string(.frequency).flatMap(ReleaseFrequency.init(rawValue:)) ?? .weekly
        day = string(.day).flatMap(ReleaseWeekday.init(rawValue:)) ?? .friday
        dayOfMonth = string(.date).flatMap(Int.init)
        time = ReleaseTime(wire: string(.time))
        systemRetry = (try? c.decodeIfPresent(Bool.self, forKey: .systemRetry)) ?? nil ?? false
        manualRetry = (try? c.decodeIfPresent(Bool.self, forKey: .manualRetry)) ?? nil ?? false
        attempts = (try? c.decodeIfPresent(Int.self, forKey: .attempts)) ?? nil ?? 0
    }
}

/// PUT /release-cycle. The retry count goes as `attempts`, the field the backend reads (the
/// web sends `attempt`, which is dropped, so its count is never saved); a weekday for weekly
/// and bi weekly cycles (the web only checks for "byweekly", so its bi weekly cycles lost
/// their day), the day of the month for monthly ones.
struct ReleaseCyclePayload: Encodable, Equatable {
    let frequency: String
    let systemRetry: Bool
    let attempts: Int
    let manualRetry: Bool
    let createdBy: String
    let time: String
    let day: String?
    let date: String?

    init(_ cycle: RQReleaseCycle, createdBy: String) {
        frequency = cycle.frequency.rawValue
        systemRetry = cycle.systemRetry
        attempts = cycle.systemRetry ? max(cycle.attempts, 1) : 0
        manualRetry = cycle.manualRetry
        self.createdBy = createdBy
        time = (cycle.time ?? ReleaseTime(hour: 18, minute: 0)).wireValue
        day = cycle.frequency.usesWeekday ? cycle.day.rawValue : nil
        date = cycle.frequency.usesWeekday ? nil : cycle.dayOfMonth.map(String.init)
    }
}

/// A one-off release date (GET /custom-release lists the active ones).
struct RQCustomRelease: Decodable, Identifiable, Equatable {
    let id: Int
    let date: Date?
    let time: ReleaseTime?

    private enum CodingKeys: String, CodingKey { case id, date, time }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        let raw = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? nil
        date = raw.flatMap { Date.fromISO8601($0) ?? Self.dayFormatter.date(from: String($0.prefix(10))) }
        time = ReleaseTime(wire: (try? c.decodeIfPresent(String.self, forKey: .time)) ?? nil)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// POST /custom-release, as the web sends it: the day at 18:30 on the device as an ISO
/// string, and the time the same way as the cycle's.
struct CustomReleasePayload: Encodable, Equatable {
    let date: String
    let time: String
    let createdBy: String

    init(day: Date, time: ReleaseTime, createdBy: String, calendar: Calendar = .current) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let evening = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: day) ?? day
        date = formatter.string(from: evening)
        self.time = time.wireValue
        self.createdBy = createdBy
    }
}

/// POST /release (schedule) and PUT /release (move to another date), as the web's release
/// board sends them on drop: `plannedOn` is the day's local midnight as an ISO string.
struct ReleaseSchedulePayload: Encodable, Equatable {
    let changeRequestId: Int
    let description: String
    let plannedOn: String
    var createdBy: String?
    var updatedBy: String?

    static func plannedOn(_ day: Date, calendar: Calendar = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: calendar.startOfDay(for: day))
    }
}

/// RQRelease's own status vocabulary — confirmed distinct from ChangeRequestStatus
/// (releaseHome.js's `statusimages` dict): released, error, planned, inprogress.
enum ReleaseStatus: Hashable {
    case planned
    case inProgress
    case released
    case error
    case other(String)

    init(raw: String) {
        let normalized = raw.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "planned": self = .planned
        case "inprogress", "progress": self = .inProgress
        case "released": self = .released
        case "error": self = .error
        default: self = .other(raw)
        }
    }

    var displayName: String {
        switch self {
        case .planned: return "Planned"
        case .inProgress: return "In Progress"
        case .released: return "Released"
        case .error: return "Error"
        case .other(let raw): return raw.isBlank ? "Unknown" : raw.capitalized
        }
    }

    var icon: String {
        switch self {
        case .planned: return "calendar"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .released: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .other: return "questionmark.circle"
        }
    }
}

// MARK: - Stage Flow
// The web's stage buttons (changeRequestDetail.js) and push drawer (commonStagingFlow):
// first stage → Start; the stage before the last → Revert / Mark this as completed; any
// other stage before that → Revert / Push to next stage; the last stage has none (Archive
// lives in the menu). None of them show when the tenant enforces the approval workflow —
// steps then move by Approve/Reject instead.

enum StageMoveKind: Equatable {
    case start, next, complete, revert

    var title: String {
        switch self {
        case .start: return "Start"
        case .next: return "Push to next stage"
        case .complete: return "Mark as completed"
        case .revert: return "Push to previous stage"
        }
    }
}

struct StageMove: Equatable {
    let kind: StageMoveKind
    let from: RQStage
    let to: RQStage
    /// The request's status once it's at `to`, as the web sets it after a move: planned at
    /// the first stage, completed at the last, in progress in between.
    let status: ChangeRequestStatus
    /// Deploy to QA on an SAP or Git request runs transport releases or a branch merge,
    /// and marking an SAP request complete releases its transports, before the stage moves.
    /// The app doesn't drive those yet, so such a move is left to the web.
    let needsWeb: Bool
}

struct StageActions: Equatable {
    var forward: StageMove?
    var revert: StageMove?

    static let none = StageActions()
}

extension ChangeRequest {
    var usesSAP: Bool { platforms.contains(where: \.isSAP) }
    var usesGit: Bool { platforms.contains(where: \.usesGit) }

    func stageActions(workflowEnforced: Bool) -> StageActions {
        guard !workflowEnforced, let current = currentStage, let last = stages.last,
              current.order < last.order else { return .none }

        func move(_ kind: StageMoveKind, to order: Int) -> StageMove? {
            guard let target = stages.first(where: { $0.order == order }) else { return nil }
            let status: ChangeRequestStatus = order == 1 ? .planned
                : order == stages.count ? .completed : .inProgress
            let forward = kind != .revert
            let deploysToQA = forward && current.qaDeploy && (usesSAP || usesGit)
            let releasesTransports = kind == .complete && usesSAP
            return StageMove(kind: kind, from: current, to: target, status: status,
                             needsWeb: deploysToQA || releasesTransports)
        }

        var actions = StageActions()
        let nextOrder = current.order + 1
        let kind: StageMoveKind = current.order == 1 ? .start
            : nextOrder == last.order ? .complete : .next
        actions.forward = move(kind, to: nextOrder)
        if current.order > 1 {
            actions.revert = move(.revert, to: current.order - 1)
        }
        return actions
    }
}

extension ChangeRequest {
    /// The stage a board drop into `status`'s column moves the request to, as the web's
    /// Grid view (changeRequestHome.js updatestatus) does: planned is the first stage, in
    /// progress the second, completed the last. Other columns, or a drop that lands on the
    /// stage the request is already at, move no stage.
    func boardStageTarget(for status: ChangeRequestStatus) -> RQStage? {
        let target: RQStage?
        switch status {
        case .planned: target = stages.first
        case .inProgress: target = stages.count > 1 ? stages[1] : nil
        case .completed: target = stages.last
        default: target = nil
        }
        guard let target, target.order != currentStage?.order else { return nil }
        return target
    }
}

/// PUT /rest/trm/v1/stage — the target stage, as the web's stageUpdateFunc sends it. The
/// owner goes with it because the backend writes it onto the stage it moves to.
struct StageUpdatePayload: Encodable, Equatable {
    let order: Int
    let owner: String?
    let updatedBy: String
    let changeRequestId: Int
    let current: Bool
    let statusCode: String
    let description: String

    init(move: StageMove, changeRequestId: Int, updatedBy: String, totalStages: Int) {
        order = move.to.order
        owner = move.to.ownerId
        self.updatedBy = updatedBy
        self.changeRequestId = changeRequestId
        current = move.to.order == totalStages
        statusCode = move.to.statusCode
        description = move.to.description
    }

    /// A board drop's stage move. The web sends `current: true` from the board.
    init(stage: RQStage, changeRequestId: Int, updatedBy: String) {
        order = stage.order
        owner = stage.ownerId
        self.updatedBy = updatedBy
        self.changeRequestId = changeRequestId
        current = true
        statusCode = stage.statusCode
        description = stage.description
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order, forKey: .order)
        try c.encode(owner, forKey: .owner)  // null clears nothing: it's the target's own owner
        try c.encode(updatedBy, forKey: .updatedBy)
        try c.encode(changeRequestId, forKey: .changeRequestId)
        try c.encode(current, forKey: .current)
        try c.encode(statusCode, forKey: .statusCode)
        try c.encode(description, forKey: .description)
    }

    private enum CodingKeys: String, CodingKey {
        case order, owner, updatedBy, changeRequestId, current, statusCode, description
    }
}

/// The stage endpoint answers 200 even when it fails, with `status: "error"`.
struct StageUpdateResponse: Decodable {
    let status: String?
    let message: String?
}

// MARK: - Approval Workflow
// GET /change-requests/{id}/workflow (trm-backend-go internal/workflow View). Only an
// `enforced` view changes anything on screen: steps with Approve/Reject replace the stage
// buttons.

struct RQWorkflow: Decodable, Equatable {
    let enforced: Bool
    let currentOrder: Int?
    let steps: [RQWorkflowStep]

    private enum CodingKeys: String, CodingKey { case enforced, currentOrder, steps }

    init(enforced: Bool, currentOrder: Int? = nil, steps: [RQWorkflowStep]) {
        self.enforced = enforced
        self.currentOrder = currentOrder
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enforced = (try? c.decodeIfPresent(Bool.self, forKey: .enforced)) ?? false
        currentOrder = (try? c.decodeIfPresent(Int.self, forKey: .currentOrder)) ?? nil
        steps = (try? c.decodeIfPresent([RQWorkflowStep].self, forKey: .steps)) ?? []
    }
}

struct RQWorkflowStep: Decodable, Equatable, Identifiable {
    struct Gate: Decodable, Equatable {
        let status: String?
        let prs: Int?
    }

    let order: Int
    let statusCode: String
    let description: String
    let type: String
    let department: String
    let role: String
    let state: String
    let decisions: [RQWorkflowDecision]
    let gate: Gate?

    var id: Int { order }
    var title: String { description.isEmpty ? statusCode : description }
    var isGate: Bool { type == "github_gate" }
    /// Approve/Reject only on the current approval step (the web's canDecideStep). Whether
    /// this user may approve is the server's call; a refusal comes back as not_an_approver.
    var canDecide: Bool { state == "current" && !isGate }

    var stateLabel: String {
        switch state {
        case "pending": return "Pending"
        case "current": return "Current"
        case "approved": return "Approved"
        case "rejected": return "Rejected"
        case "satisfied": return "Satisfied"
        case "blocked": return "Blocked"
        default: return state.capitalized
        }
    }

    /// The web's GATE_STATUS_LABELS.
    var gateLabel: String? {
        guard let status = gate?.status else { return nil }
        switch status {
        case "none": return "No pull requests"
        case "pending": return "Pending review"
        case "changes_requested": return "Changes requested"
        case "approved": return "Approved"
        case "approved_stale": return "Approval is stale"
        case "merged": return "Merged"
        default: return status
        }
    }

    private enum CodingKeys: String, CodingKey {
        case order, statusCode, description, type, department, role, state, decisions, gate
    }

    init(order: Int, description: String, state: String, type: String = "approval",
         statusCode: String = "", department: String = "", role: String = "",
         decisions: [RQWorkflowDecision] = [], gate: Gate? = nil) {
        self.order = order
        self.statusCode = statusCode
        self.description = description
        self.type = type
        self.department = department
        self.role = role
        self.state = state
        self.decisions = decisions
        self.gate = gate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? c.decode(Int.self, forKey: .order)) ?? 0
        statusCode = (try? c.decodeIfPresent(String.self, forKey: .statusCode)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        type = ((try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil).flatMap { $0.isEmpty ? nil : $0 } ?? "approval"
        department = (try? c.decodeIfPresent(String.self, forKey: .department)) ?? ""
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? ""
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? ""
        decisions = (try? c.decodeIfPresent([RQWorkflowDecision].self, forKey: .decisions)) ?? []
        gate = (try? c.decodeIfPresent(Gate.self, forKey: .gate)) ?? nil
    }
}

struct RQWorkflowDecision: Decodable, Equatable, Identifiable {
    struct Actor: Decodable, Equatable {
        let sub: String?
        let name: String?
    }

    let id: String
    let decision: String
    let actor: Actor?
    let comment: String?
    let createdAt: Date?

    var isRejection: Bool { decision == WorkflowDecision.reject.rawValue }
    var actorName: String { actor?.name ?? actor?.sub ?? "Someone" }
}

enum WorkflowDecision: String, Encodable {
    case approve, reject
}

/// POST /change-requests/{id}/steps/{order}/decisions — the actor comes from the token.
struct WorkflowDecisionPayload: Encodable, Equatable {
    let decision: WorkflowDecision
    let comment: String
}

/// The web's DECISION_ERROR_MESSAGES, keyed by the server's error code.
enum WorkflowDecisionError {
    /// Codes after which the step has moved on or the setting changed: reload the workflow.
    static let refreshCodes: Set<String> = ["not_current_step", "step_is_gate", "workflow_not_enforced"]

    static func message(for error: Error) -> String {
        switch error {
        case RequestsAPIError.rejected(_, let code, _):
            switch code {
            case "not_an_approver": return "You are not an approver for this step."
            case "not_current_step": return "This step is no longer the current step. The workflow has been refreshed."
            case "step_is_gate": return "This is a GitHub gate step. It completes automatically and can't be approved by hand."
            case "workflow_not_enforced": return "Workflow enforcement is turned off for your organization."
            default: break
            }
        case RequestsAPIError.requestsUnavailable(statusCode: 403):
            return "You are not an approver for this step."
        default: break
        }
        return "Could not record your decision. Please try again."
    }

    static func needsRefresh(_ error: Error) -> Bool {
        if case RequestsAPIError.rejected(_, let code, _) = error { return refreshCodes.contains(code) }
        return false
    }
}
