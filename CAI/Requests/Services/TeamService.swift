import Foundation

// MARK: - Team Service
// GET /teams — BFF-proxied, confirmed registered in trm-bff's production config.yaml
// (backend_path "/teams" → trm-backend-go's getTeams handler). See Team's own doc comment
// in RequestsModels.swift for the bare-array response-shape confirmation.

protocol TeamServicing {
    func listTeams(forceRefresh: Bool) async throws -> [RQTeam]
}

struct TeamService: TeamServicing {
    let client: RequestsAPIClient
    private let cache = AsyncCache<[RQTeam]>()

    func listTeams(forceRefresh: Bool = false) async throws -> [RQTeam] {
        try await cache.fetch(forceRefresh: forceRefresh) {
            try await client.get("/teams")
        }
    }
}
