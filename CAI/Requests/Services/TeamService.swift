import Foundation

// MARK: - Team Service
// GET /teams — BFF-proxied, confirmed registered in trm-bff's production config.yaml
// (backend_path "/teams" → trm-backend-go's getTeams handler). See Team's own doc comment
// in RequestsModels.swift for the bare-array response-shape confirmation.

protocol TeamServicing {
    func listTeams(forceRefresh: Bool) async throws -> [RQTeam]
    /// A team's members with email and role — the web's team members table
    /// (teamsHomePage.js getTeamUsers: GET /rest/trm/v1/user?name=&team=&role=&assign=true).
    func members(teamId: String, search: String) async throws -> [RQAdminUser]
}

struct TeamService: TeamServicing {
    let client: RequestsAPIClient
    private let cache = AsyncCache<[RQTeam]>()

    func listTeams(forceRefresh: Bool = false) async throws -> [RQTeam] {
        try await cache.fetch(forceRefresh: forceRefresh) {
            try await client.get("/teams")
        }
    }

    func members(teamId: String, search: String) async throws -> [RQAdminUser] {
        let envelope: RQListEnvelope<RQAdminUser> = try await client.get("/rest/trm/v1/user", queryItems: [
            URLQueryItem(name: "name", value: search), URLQueryItem(name: "team", value: teamId),
            URLQueryItem(name: "role", value: ""), URLQueryItem(name: "assign", value: "true")
        ])
        return envelope.items
    }
}
