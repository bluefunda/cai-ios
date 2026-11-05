import Foundation

// MARK: - Reference Data Service
// Populates the Create/Edit Change Request pickers (Request Type, Severity, Request Owner).
//
// Cached (2026-09-09) — these three lists rarely change but were being re-fetched from
// scratch every single time the New Request or Edit Request sheet opened, same wasteful
// pattern the Projects fetch had before `AsyncCache` was introduced to fix it there.
//
// Route choice per endpoint, verified directly against trm-gw + trm-bff source on
// 2026-09-09 (not assumed) after the direct-gateway `/rest/trm/v1/...` family was found
// broken three separate times this session (change-request, projects, listchangeRequestFile):
// - `users` switched to the BFF-proxied, unprefixed `GET /users` — confirmed registered in
//   trm-bff's production config.yaml (unlike a couple of sibling BFF routes found dead
//   there), and a genuine bare "list all" route (no `{id}` required at the gateway level).
//   Same bare-JSON-array response shape as `/projects`/`/teams` — trm-backend-go's own
//   `getUser` handler (`renderUsers` → `renderJSON(w, users)`) never wraps its response
//   regardless of which gateway route reaches it; the direct route's `{"users": [...]}`
//   wrapping is applied by that route's own gateway template, not the backend.
// - `requestTypes`/`severities` stay on their direct-gateway routes
//   (`/rest/trm/v1/requestType/all`, `/rest/trm/v1/severity/all`) — checked for a safer BFF
//   equivalent and found none reachable: `bff-request-types-get.tmpl` and
//   `bff-severities-get.tmpl` both hardcode a required `{id}` path segment at the gateway
//   level (`/request-types/{id}`, `/severities/{id}`), so there is no "list all" BFF route
//   for either, even though trm-bff's own backend config happens to have a bare
//   `severities` entry with no gateway template exposing it. No live failure has been
//   reported for either direct route (unlike the three confirmed-broken ones above), so this
//   isn't a known-active bug — just the honest state of what alternatives do/don't exist.

protocol ReferenceDataServicing {
    func requestTypes(forceRefresh: Bool) async throws -> [RequestTypeOption]
    func severities(forceRefresh: Bool) async throws -> [SeverityOption]
    func users(forceRefresh: Bool) async throws -> [UserOption]
}

struct ReferenceDataService: ReferenceDataServicing {
    let client: RequestsAPIClient
    private let requestTypeCache = AsyncCache<[RequestTypeOption]>()
    private let severityCache = AsyncCache<[SeverityOption]>()
    private let userCache = AsyncCache<[UserOption]>()

    func requestTypes(forceRefresh: Bool = false) async throws -> [RequestTypeOption] {
        try await requestTypeCache.fetch(forceRefresh: forceRefresh) {
            let response: RequestTypeListResponse = try await client.get("/rest/trm/v1/requestType/all")
            return response.requestTypes
        }
    }

    func severities(forceRefresh: Bool = false) async throws -> [SeverityOption] {
        try await severityCache.fetch(forceRefresh: forceRefresh) {
            let response: SeverityListResponse = try await client.get("/rest/trm/v1/severity/all")
            return response.severities
        }
    }

    func users(forceRefresh: Bool = false) async throws -> [UserOption] {
        try await userCache.fetch(forceRefresh: forceRefresh) {
            try await client.get("/users")
        }
    }
}
