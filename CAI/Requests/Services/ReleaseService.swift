import Foundation

// MARK: - Release Service
// Read-only, grouped-by-planned-date list — a deliberate reimagining of trm web's
// drag-and-drop Kanban board (releaseHome.js) for a mobile v1, not a port of it. See
// RequestsModels.swift's RQRelease doc comment for the endpoint-choice caveat.

protocol ReleaseServicing {
    func listReleases(limit: Int?) async throws -> [RQRelease]
}

struct ReleaseService: ReleaseServicing {
    let client: RequestsAPIClient

    /// `limit` is unverified against trm-gw for this route (unlike change-requests, where
    /// trm-gw >= v9.3.3 is confirmed to allow-list it — see ChangeRequestFilter.limit's doc
    /// comment) — if the gateway doesn't allow-list it here it'll just be silently dropped
    /// and this won't bound the response.
    func listReleases(limit: Int? = nil) async throws -> [RQRelease] {
        var queryItems: [URLQueryItem] = []
        if let limit, limit > 0 { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
        let response: ReleaseListResponse = try await client.get("/rest/trm/v1/release", queryItems: queryItems)
        return response.releases
    }
}
