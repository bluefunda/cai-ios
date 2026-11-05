import Foundation

// MARK: - Release Service
// Read-only, grouped-by-planned-date list — a deliberate reimagining of trm web's
// drag-and-drop Kanban board (releaseHome.js) for a mobile v1, not a port of it. See
// RequestsModels.swift's RQRelease doc comment for the endpoint-choice caveat.

protocol ReleaseServicing {
    func listReleases(limit: Int?) async throws -> [RQRelease]
    /// POST /rest/trm/v1/release — a completed request onto a release date.
    func schedule(_ payload: ReleaseSchedulePayload) async throws
    /// PUT /rest/trm/v1/release — a scheduled release onto another date.
    func reschedule(_ payload: ReleaseSchedulePayload) async throws
    func releaseCycle() async throws -> RQReleaseCycle?
    func saveReleaseCycle(_ payload: ReleaseCyclePayload) async throws
    func customReleases() async throws -> [RQCustomRelease]
    func addCustomRelease(_ payload: CustomReleasePayload) async throws
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

    func schedule(_ payload: ReleaseSchedulePayload) async throws {
        try await client.postDiscardingResponse("/rest/trm/v1/release", body: payload)
    }

    func reschedule(_ payload: ReleaseSchedulePayload) async throws {
        try await client.putDiscardingResponse("/rest/trm/v1/release", body: payload)
    }

    func releaseCycle() async throws -> RQReleaseCycle? {
        let envelope: RQListEnvelope<RQReleaseCycle> = try await client.get("/rest/trm/v1/release-cycle")
        return envelope.items.first
    }

    func saveReleaseCycle(_ payload: ReleaseCyclePayload) async throws {
        try await client.putDiscardingResponse("/rest/trm/v1/release-cycle", body: payload)
    }

    /// The backend answers an error entry when there are none; that reads as an empty list.
    func customReleases() async throws -> [RQCustomRelease] {
        let envelope: RQListEnvelope<RQCustomRelease> = try await client.get("/rest/trm/v1/custom-release")
        return envelope.items.filter { $0.date != nil }
    }

    func addCustomRelease(_ payload: CustomReleasePayload) async throws {
        try await client.postDiscardingResponse("/rest/trm/v1/custom-release", body: payload)
    }
}
