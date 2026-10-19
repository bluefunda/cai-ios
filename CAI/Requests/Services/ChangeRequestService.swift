import Foundation

// MARK: - Change Request Service
// Read path only for v1 — see the trm-ios plan's v1 scope table (no create/edit from
// mobile yet).
//
// Ported directly from trm's own web frontend, matching its real Change Requests screen
// (src/components/changeRequests/changeRequestHome.js) rather than the unused, unfiltered
// `getAllChangeRequest()` helper — the home screen calls `getChangeRequestByFilter(desc,
// archive, status, reqOwner, requestType, severity, assignee)`, a single GET with only
// non-empty params appended, and defaults to archive=false + reqOwner/assignee=the
// logged-in user's id on first visit. See ChangeRequestFilter below for the exact param
// mapping.
//
// ⚠️ Deliberately uses `/change-requests`, NOT `/rest/trm/v1/change-request`, despite the
// latter being what changeRequestHome.js actually calls (via GO_URL/BASE_URL_APP_GO) and
// both routing to the exact same trm-backend-go handler (`getChangeRequest` →
// `getChangeRequestsByParams`, changeRequest.go:212). Direct hurl testing against the live
// gateway (services/vars.env creds, both routes, same account) showed `/rest/trm/v1/
// change-request` failing with a flat, consistent HTTP 500 + empty body — not intermittent,
// not cold-cache-related, reproduced on 3/3 attempts — while `/change-requests` (the
// BFF-proxied route: gateway → trm-bff's generic reverse-proxy → trm-backend-go, two hops)
// succeeded cleanly every time for the same account. So despite `/change-requests` being
// the route trm's own UI does *not* use (only the unused `getAllChangeRequest()` picker
// helper does), it's the one that's actually reachable and working right now. Revisit this
// if the direct route's outage gets fixed — the two-hop hurl route did still reproduce the
// truncation issue from bluefunda/trm#139 for a large-enough dataset in earlier testing, so
// this isn't a full fix for that, just the only currently-working option of the two.
//
// Both list and detail hit this same endpoint — it accepts `id` as one of its filter query
// strings, so "detail" is just "list filtered down to one." There's no separate detail
// endpoint, and no separate logs endpoint either: the activity log comes back embedded as
// each item's `userTimeline` (see ChangeRequestTimelineEntry).
//
// trm's list screen (changeRequestHome.js) never shows a project name, so its fetch never
// resolves one — only the single-item detail fetch here does, via a separate
// /rest/trm/v1/projects lookup (same pattern trm's own detail/edit screens use).
//
// Two real backend/gateway bugs were identified while building this the first time
// (unbounded-query truncation risk from this call never sending limit/offset, and a
// check-then-act race in trm-backend-go's per-tenant DB connection cache) — both filed
// upstream (bluefunda/trm#139, bluefunda/trm-backend-go#116) rather than worked around
// here, since trm's own web frontend doesn't work around them either and the request here
// is to match it exactly. #139 has been updated with the two-hop-vs-one-hop finding above,
// since it's a material part of the same underlying truncation risk.

protocol ChangeRequestServicing {
    func listChangeRequests(filter: ChangeRequestFilter) async throws -> [ChangeRequest]
    func changeRequest(id: String) async throws -> ChangeRequest
    func create(_ payload: NewChangeRequestPayload) async throws -> ChangeRequest
    func update(_ payload: ChangeRequestUpdatePayload) async throws
}

/// Mirrors trm's own `getChangeRequestByFilter(desc, archive, status, reqOwner, requestType,
/// severity, assignee)` (changeReqApis.js) — every field defaults empty/nil, and only
/// non-empty values are sent as query params, matching trm's own conditional URL-building.
struct ChangeRequestFilter {
    var description: String = ""
    var archive: Bool? = false
    var status: String?
    var reqOwner: String?
    var requestType: String?
    var severity: String?
    var assignee: String?
    /// Scopes the list to one project's change requests (Project Detail's embedded list).
    /// Confirmed allow-listed on this same `/change-requests` BFF route by trm-gw's own
    /// `bff-change-requests-get.tmpl` — deliberately NOT the direct-gateway singular
    /// `/rest/trm/v1/change-request` route trm's own web app uses for this, since that route
    /// is the one confirmed reproducibly 500ing earlier this session (see this file's header
    /// doc comment).
    var projectId: String?
    /// Caps each response to a size trm-gw's gateway timeout can reliably complete within —
    /// per-row enrichment in trm-backend-go (severity/type/project/timeline, up to 7 extra DB
    /// round trips per change request) made an unbounded fetch a real truncation risk
    /// (bluefunda/trm#139). Requires trm-gw >= v9.3.3 (bluefunda/trm-gw#66), which allow-lists
    /// `limit` on both change-request routes — older deployments silently drop it. No `offset`
    /// yet: there's no "load more" UI to page through further results, so a single capped
    /// fetch is all that's needed for now.
    var limit: Int? = 50

    fileprivate var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !description.isEmpty { items.append(URLQueryItem(name: "description", value: description)) }
        if let archive { items.append(URLQueryItem(name: "archive", value: archive ? "true" : "false")) }
        if let status, !status.isEmpty { items.append(URLQueryItem(name: "status", value: status)) }
        if let reqOwner, !reqOwner.isEmpty { items.append(URLQueryItem(name: "reqOwner", value: reqOwner)) }
        if let requestType, !requestType.isEmpty { items.append(URLQueryItem(name: "requestType", value: requestType)) }
        if let severity, !severity.isEmpty { items.append(URLQueryItem(name: "severity", value: severity)) }
        if let assignee, !assignee.isEmpty { items.append(URLQueryItem(name: "user", value: assignee)) }
        if let projectId, !projectId.isEmpty { items.append(URLQueryItem(name: "projectId", value: projectId)) }
        if let limit, limit > 0 { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        return items
    }
}

struct ChangeRequestService: ChangeRequestServicing {
    let client: RequestsAPIClient
    let projectService: ProjectServicing

    func listChangeRequests(filter: ChangeRequestFilter) async throws -> [ChangeRequest] {
        let response: ChangeRequestListResponse = try await client.get(
            "/change-requests",
            queryItems: filter.queryItems
        )
        return Self.resolveNames(in: response, projects: [])
    }

    func changeRequest(id: String) async throws -> ChangeRequest {
        let response: ChangeRequestListResponse = try await client.get(
            "/change-requests",
            queryItems: [URLQueryItem(name: "id", value: id)]
        )
        let projects = (try? await projectService.listProjects(forceRefresh: false)) ?? []
        guard let match = Self.resolveNames(in: response, projects: projects).first else {
            throw RequestsAPIError.serverError(404, "Change request \(id) not found")
        }
        return match
    }

    /// POST /rest/trm/v1/change-request/create — confirmed against trm's own
    /// createUpdateChangeRequestForm.js / changeReqApis.js. The response is the flat created
    /// object (see CreatedChangeRequestResponse's doc comment); re-fetching by id gets the
    /// fully name-resolved version the rest of the app expects.
    func create(_ payload: NewChangeRequestPayload) async throws -> ChangeRequest {
        let response: CreatedChangeRequestResponse = try await client.post(
            "/rest/trm/v1/change-request/create",
            body: payload
        )
        return try await changeRequest(id: String(response.id))
    }

    /// PUT /rest/trm/v1/change-request — confirmed against trm's own updateChangeReq /
    /// changeRequestPut.go. Response shape isn't confirmed (no OpenAPI spec, matches the
    /// existing posture for comments' create call), so this discards the body and relies on
    /// the caller re-fetching afterward to pick up the new server-computed timeline entry.
    func update(_ payload: ChangeRequestUpdatePayload) async throws {
        try await client.putDiscardingResponse("/rest/trm/v1/change-request", body: payload)
    }

    /// `requestedBy` is a user id and `projectId` is a project id; display data for both
    /// live in sibling data — a top-level `userProfile` dict on this same response (name +
    /// avatar), and, for `projectId`, a wholly separate `/rest/trm/v1/projects` fetch — not on
    /// the item itself. Resolved here after decoding rather than inside ChangeRequest's own
    /// Decodable init, which has no visibility into either.
    private static func resolveNames(in response: ChangeRequestListResponse, projects: [RQProject]) -> [ChangeRequest] {
        let projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        return response.combinedResponse.map { cr in
            var cr = cr
            if let userId = cr.requestedByUserId, let profile = response.userProfile?[userId] {
                cr.createdByName = profile.name
                cr.createdByAvatarURL = profile.profileImage
            }
            if let projectId = cr.projectId, let name = projectNames[projectId] {
                cr.projectName = name
            }
            return cr
        }
    }
}
