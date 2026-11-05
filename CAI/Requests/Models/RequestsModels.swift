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

    /// Prefers the real `createdAt` field; falls back to the earliest timeline entry only if
    /// that's ever absent (defensive — trm's frontend suggests it might not always be sent).
    var submittedAt: Date? {
        createdAt ?? timeline.compactMap(\.createdAt).min()
    }

    static func == (lhs: ChangeRequest, rhs: ChangeRequest) -> Bool { lhs.id == rhs.id }
}

struct ChangeRequestPlatform: Decodable, Hashable {
    let sap: String?
    let description: String?
}

extension ChangeRequest: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ChangeRequest: Decodable {
    private enum EnvelopeKeys: String, CodingKey {
        case changeRequest, requestId, severityData, requestTypeData, userTimeline
    }
    private enum CoreKeys: String, CodingKey {
        case id, description, shortDescription, status, requestedBy, projectId, platform, createdAt
        case stage, totalStages, stageStatus, archive
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
        stage = (try? core.decodeIfPresent(Int.self, forKey: .stage)) ?? nil
        totalStages = (try? core.decodeIfPresent(Int.self, forKey: .totalStages)) ?? nil
        stageStatus = (try? core.decodeIfPresent(String.self, forKey: .stageStatus)) ?? nil
        isArchived = (try? core.decodeIfPresent(Bool.self, forKey: .archive)) ?? false

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
    init(id: String, name: String) {
        self.id = id
        self.name = name
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
    let comment: String
    let createdBy: String
    let changeRequestId: Int
    let mentions: [String] = []
    var attachments: [CommentAttachmentRef] = []
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
        case id, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        fileName = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Attachment"
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
        case id, name, description, jira, projectTypeData, ownerUser, requestCount, projectUsers
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
struct CreatedChangeRequestResponse: Decodable {
    let id: Int
}

struct NewChangeRequestPayload: Encodable {
    let shortDescription: String
    let description: String
    let projectId: String
    let requestType: String
    let severity: String
    let requestedBy: String
    let createdBy: String
    let ticketUrl: String?
}

/// All-optional so only the fields actually being changed get encoded — `CreatedBy`/
/// `UpdatedBy` (capitalized; matches the exact keys trm's own web frontend sends on every
/// update call, confirmed against changeRequestPut.go) are always included.
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
        try container.encode(id, forKey: .id)
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

    var id: String { changeRequestId }

    /// Falls back to the requestId display code, then a generic label — a release with
    /// neither a name nor a description is plausible (trm's own Kanban card falls back to
    /// the linked change request's own title in that case, which this model doesn't have).
    var title: String {
        name ?? description ?? requestId.map { "Request \($0)" } ?? "Untitled Release"
    }
}

extension RQRelease {
    private enum CodingKeys: String, CodingKey {
        case changeRequestId, requestId, name, description, status, plannedOn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let intId = try? container.decode(Int.self, forKey: .changeRequestId) {
            changeRequestId = String(intId)
        } else {
            changeRequestId = (try? container.decode(String.self, forKey: .changeRequestId)) ?? UUID().uuidString
        }
        requestId = (try? container.decodeIfPresent(String.self, forKey: .requestId)) ?? nil
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? nil
        let rawStatus = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil
        status = ReleaseStatus(raw: rawStatus ?? "")
        plannedOn = (try? container.decodeIfPresent(Date.self, forKey: .plannedOn)) ?? nil
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
        releases = try container.decodeIfPresent([RQRelease].self, forKey: .releases) ?? []
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
