import Foundation

// MARK: - Project Service
//
// ⚠️ Switched from the direct-gateway `GET /rest/trm/v1/projects` to the BFF-proxied,
// unprefixed `GET /projects` on 2026-09-09 — the direct route was live-confirmed to fail
// consistently (not intermittently) with an empty-body HTTP 500, the exact same signature
// this codebase already diagnosed once before for `/rest/trm/v1/change-request` (see
// ChangeRequestService's doc comment) and worked around the same way: switch to the
// BFF-proxied sibling, which a direct repo check (trm-gw's `bff-projects-get.tmpl` +
// trm-bff's production `config.yaml`) confirmed is live and proxies to the same
// trm-backend-go `/projects` handler, so the response shape is unchanged.
//
// Trade-off: this BFF route declares no `input_query_strings` at all — unlike the direct
// route (which supported `id`/`projectType`/`name`/`owner`/`archive`/`limit`), every filter
// is silently dropped server-side. `projectDetail(id:)` compensates by fetching the full list
// and filtering client-side instead of relying on a server-side `?id=` filter — but each
// `Project` row on the wire embeds a full `changeRequests` array plus several joined tables
// (`ownerUser`, `projectTypeData`, `projectUsers`, `repos`), making this fetch meaningfully
// heavier than the old single-row lookup. Live-confirmed 2026-09-09: visiting Project Detail
// right after the Projects list screen re-ran this same heavy, unbounded fetch a second time
// — slow, and occasionally failing with `URLError.networkConnectionLost` — for data the list
// screen had just fetched moments earlier. `ProjectCache` below makes that second hop free in
// the common case (drill down from a list that's already loaded) by reusing the in-flight or
// most recent result instead of re-fetching, while `forceRefresh` still gets a real network
// call for deliberate pull-to-refresh actions.

protocol ProjectServicing {
    func listProjects(forceRefresh: Bool) async throws -> [RQProject]
    /// The richer per-project shape (type/owner/request count) the Projects list screen
    /// displays — same underlying cached fetch as `listProjects`, just not thinned down to
    /// id+name first.
    func listProjectDetails(forceRefresh: Bool) async throws -> [ProjectDetail]
    func projectDetail(id: String, forceRefresh: Bool) async throws -> ProjectDetail
}

struct ProjectService: ProjectServicing {
    let client: RequestsAPIClient
    /// Shared across every caller — the Projects list, Project Detail's own lookup, a change
    /// request's project-name resolution, and the New Request form's project picker all want
    /// "the current project list" and, in the common case, want it within moments of each
    /// other. See `AsyncCache`'s own doc comment for why this exists.
    private let cache = AsyncCache<[ProjectDetail]>()

    private func fetchAll(forceRefresh: Bool) async throws -> [ProjectDetail] {
        try await cache.fetch(forceRefresh: forceRefresh) {
            try await client.get("/projects")
        }
    }

    func listProjects(forceRefresh: Bool = false) async throws -> [RQProject] {
        try await fetchAll(forceRefresh: forceRefresh).map { RQProject(id: $0.id, name: $0.name) }
    }

    func listProjectDetails(forceRefresh: Bool = false) async throws -> [ProjectDetail] {
        try await fetchAll(forceRefresh: forceRefresh)
    }

    func projectDetail(id: String, forceRefresh: Bool = false) async throws -> ProjectDetail {
        guard let match = try await fetchAll(forceRefresh: forceRefresh).first(where: { $0.id == id }) else {
            throw RequestsAPIError.serverError(404, "Project \(id) not found")
        }
        return match
    }
}
