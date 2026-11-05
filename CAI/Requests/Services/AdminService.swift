import Foundation

// MARK: - Admin Service
// trm's web admin screens (User Management, Request Templates, Manage Teams,
// Configurations) and Git screens, on the same routes the web calls — GO_URL
// (`/rest/trm/v1`) and GIT_URL (`/rest/git/sap/v1`). Routes and bodies are from
// src/apiCalls/{userApis,templateApis,teamsApis,roleApis,groupApis,severityApis,
// requestTypeApis,projectTypeApis,applicationApis,systemApis,gitApis}.js.

protocol AdminServicing {
    // User Management
    func users(search: String, active: Bool) async throws -> [RQAdminUser]
    func user(id: String) async throws -> RQAdminUser?
    func departments() async throws -> [RQNamedOption]
    func roles() async throws -> [RQNamedOption]
    func createUser(_ payload: RQUserPayload) async throws
    func updateUser(id: String, _ payload: RQUserPayload) async throws
    func deactivateUser(id: String, updatedBy: String) async throws

    // Request Templates
    func templates() async throws -> [RQRequestTemplate]
    func template(id: String) async throws -> RQRequestTemplate?
    func createTemplate(_ payload: RQTemplatePayload) async throws
    func updateTemplate(id: String, _ payload: RQTemplatePayload) async throws

    // Manage Teams
    func teams(search: String) async throws -> [RQAdminTeam]
    func team(id: String) async throws -> RQAdminTeam?
    func usersNotInTeam(teamId: String, search: String) async throws -> [RQAdminUser]
    func createTeam(_ payload: RQTeamPayload) async throws
    func updateTeam(_ payload: RQTeamPayload) async throws

    // Configurations
    func configList(_ kind: RQConfigKind) async throws -> [RQConfigItem]
    func systems() async throws -> [RQSAPSystem]
    func addConfigItem(_ kind: RQConfigKind, _ payload: RQTypePayload) async throws
    func addApplication(_ payload: RQApplicationPayload) async throws

    // Git
    func gitRepos() async throws -> [RQGitRepo]
    func createGitRepo(_ payload: RQNewGitRepo) async throws
}

/// Configurations' simple groups and their list/create routes.
enum RQConfigKind: String, CaseIterable, Identifiable {
    case requestTypes, priorities, projectTypes, applications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .requestTypes: return "Request Types"
        case .priorities: return "Priority"
        case .projectTypes: return "Project Type"
        case .applications: return "Applications"
        }
    }

    var listPath: String {
        switch self {
        case .requestTypes: return "/requestType/all"
        case .priorities: return "/severity/all"
        case .projectTypes: return "/projectType/all"
        case .applications: return "/application/all"
        }
    }

    /// Applications are created with their own form (RQApplicationPayload).
    var createPath: String {
        switch self {
        case .requestTypes: return "/requestType"
        case .priorities: return "/severity"
        case .projectTypes: return "/projectType"
        case .applications: return "/application"
        }
    }
}

struct AdminService: AdminServicing {
    let client: RequestsAPIClient

    /// GO_URL for the `trm` organization, as ChangeRequestService uses.
    private static let base = "/rest/trm/v1"
    private static let gitBase = "/rest/git/sap/v1"

    private func list<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> [T] {
        let items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let envelope: RQListEnvelope<T> = try await client.get(Self.base + path, queryItems: items)
        return envelope.items
    }

    // MARK: User Management

    func users(search: String, active: Bool) async throws -> [RQAdminUser] {
        try await list("/user", ["name": search, "status": active ? "active" : "in-active"])
    }

    func user(id: String) async throws -> RQAdminUser? {
        try await list("/user", ["id": id]).first
    }

    func departments() async throws -> [RQNamedOption] { try await list("/group") }
    func roles() async throws -> [RQNamedOption] { try await list("/role") }

    func createUser(_ payload: RQUserPayload) async throws {
        try await client.postDiscardingResponse(Self.base + "/admin/users/create-user", body: payload)
    }

    func updateUser(id: String, _ payload: RQUserPayload) async throws {
        try await client.putDiscardingResponse(Self.base + "/update-user",
                                               queryItems: [URLQueryItem(name: "userId", value: id)], body: payload)
    }

    func deactivateUser(id: String, updatedBy: String) async throws {
        try await client.putDiscardingResponse(Self.base + "/update-user",
                                               queryItems: [URLQueryItem(name: "userId", value: id)],
                                               body: RQDeactivateUser(updatedBy: updatedBy))
    }

    // MARK: Request Templates

    func templates() async throws -> [RQRequestTemplate] { try await list("/template") }

    func template(id: String) async throws -> RQRequestTemplate? {
        try await list("/template", ["id": id]).first
    }

    func createTemplate(_ payload: RQTemplatePayload) async throws {
        try await client.postDiscardingResponse(Self.base + "/admin/template", body: payload)
    }

    func updateTemplate(id: String, _ payload: RQTemplatePayload) async throws {
        try await client.putDiscardingResponse(Self.base + "/admin/template/update-template/\(id)", body: payload)
    }

    // MARK: Manage Teams

    func teams(search: String) async throws -> [RQAdminTeam] { try await list("/teams", ["name": search]) }

    func team(id: String) async throws -> RQAdminTeam? {
        try await list("/teams", ["id": id, "name": "", "memberName": ""]).first
    }

    func usersNotInTeam(teamId: String, search: String) async throws -> [RQAdminUser] {
        try await list("/user", ["name": search, "team": teamId, "role": "", "assign": "false"])
    }

    func createTeam(_ payload: RQTeamPayload) async throws {
        try await client.postDiscardingResponse(Self.base + "/admin/teams/create-teams", body: payload)
    }

    func updateTeam(_ payload: RQTeamPayload) async throws {
        try await client.putDiscardingResponse(Self.base + "/admin/teams/update-teams", body: payload)
    }

    // MARK: Configurations

    func configList(_ kind: RQConfigKind) async throws -> [RQConfigItem] { try await list(kind.listPath) }

    func systems() async throws -> [RQSAPSystem] { try await list("/sap-system", ["appId": ""]) }

    func addConfigItem(_ kind: RQConfigKind, _ payload: RQTypePayload) async throws {
        try await client.postDiscardingResponse(Self.base + kind.createPath, body: payload)
    }

    func addApplication(_ payload: RQApplicationPayload) async throws {
        try await client.postDiscardingResponse(Self.base + RQConfigKind.applications.createPath, body: payload)
    }

    // MARK: Git

    func gitRepos() async throws -> [RQGitRepo] {
        let envelope: RQListEnvelope<RQGitRepo> = try await client.get(Self.gitBase + "/repo")
        return envelope.items
    }

    func createGitRepo(_ payload: RQNewGitRepo) async throws {
        try await client.postDiscardingResponse(Self.gitBase + "/repo", body: payload)
    }
}

// MARK: - Fixtures

/// `-bf_requests_fixtures YES`: empty lists and no-op writes, so the admin screens render
/// their empty states without a network.
struct FixtureAdminService: AdminServicing {
    func users(search: String, active: Bool) async throws -> [RQAdminUser] { [] }
    func user(id: String) async throws -> RQAdminUser? { nil }
    func departments() async throws -> [RQNamedOption] { [] }
    func roles() async throws -> [RQNamedOption] { [] }
    func createUser(_ payload: RQUserPayload) async throws {}
    func updateUser(id: String, _ payload: RQUserPayload) async throws {}
    func deactivateUser(id: String, updatedBy: String) async throws {}
    func templates() async throws -> [RQRequestTemplate] { [] }
    func template(id: String) async throws -> RQRequestTemplate? { nil }
    func createTemplate(_ payload: RQTemplatePayload) async throws {}
    func updateTemplate(id: String, _ payload: RQTemplatePayload) async throws {}
    func teams(search: String) async throws -> [RQAdminTeam] { [] }
    func team(id: String) async throws -> RQAdminTeam? { nil }
    func usersNotInTeam(teamId: String, search: String) async throws -> [RQAdminUser] { [] }
    func createTeam(_ payload: RQTeamPayload) async throws {}
    func updateTeam(_ payload: RQTeamPayload) async throws {}
    func configList(_ kind: RQConfigKind) async throws -> [RQConfigItem] { [] }
    func systems() async throws -> [RQSAPSystem] { [] }
    func addConfigItem(_ kind: RQConfigKind, _ payload: RQTypePayload) async throws {}
    func addApplication(_ payload: RQApplicationPayload) async throws {}
    func gitRepos() async throws -> [RQGitRepo] { [] }
    func createGitRepo(_ payload: RQNewGitRepo) async throws {}
}
