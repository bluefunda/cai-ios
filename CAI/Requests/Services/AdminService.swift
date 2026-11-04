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
    /// Every user, unfiltered — what the web's New message drawer loads (getSystemUserApp()).
    func allUsers() async throws -> [RQAdminUser]
    func user(id: String) async throws -> RQAdminUser?
    func departments() async throws -> [RQNamedOption]
    func roles() async throws -> [RQNamedOption]
    func createUser(_ payload: RQUserPayload) async throws
    func updateUser(id: String, _ payload: RQUserPayload) async throws
    /// Turns sign-in on or off (Keycloak `enabled`) and sets the user's status with it.
    func setUserActive(id: String, active: Bool, updatedBy: String) async throws

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
    /// The SAP systems of one application — the New Request form's source system list.
    func systems(appId: String) async throws -> [RQSAPSystem]
    /// Applications with their SAP and Git flags — the New Request form's platforms.
    func applications() async throws -> [ChangeRequestPlatform]
    func addConfigItem(_ kind: RQConfigKind, _ payload: RQTypePayload) async throws
    func addApplication(_ payload: RQApplicationPayload) async throws

    /// Workflow enforcement, as the web's Configurations shows it to admins (GET/PUT
    /// {GW}/settings/workflow). Changing it needs the admin or super-admin role.
    func workflowSettings() async throws -> RQWorkflowSettings
    func setWorkflowEnforcement(_ enabled: Bool) async throws -> RQWorkflowSettings

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

    func allUsers() async throws -> [RQAdminUser] {
        try await list("/user", ["name": "", "status": ""])
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

    func setUserActive(id: String, active: Bool, updatedBy: String) async throws {
        try await client.putDiscardingResponse(Self.base + "/update-user",
                                               queryItems: [URLQueryItem(name: "userId", value: id)],
                                               body: RQSetUserEnabled(updatedBy: updatedBy, enabled: active))
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

    func systems() async throws -> [RQSAPSystem] { try await systems(appId: "") }

    func systems(appId: String) async throws -> [RQSAPSystem] { try await list("/sap-system", ["appId": appId]) }

    func applications() async throws -> [ChangeRequestPlatform] { try await list(RQConfigKind.applications.listPath) }

    func addConfigItem(_ kind: RQConfigKind, _ payload: RQTypePayload) async throws {
        try await client.postDiscardingResponse(Self.base + kind.createPath, body: payload)
    }

    func addApplication(_ payload: RQApplicationPayload) async throws {
        try await client.postDiscardingResponse(Self.base + RQConfigKind.applications.createPath, body: payload)
    }

    func workflowSettings() async throws -> RQWorkflowSettings {
        try await client.get("/settings/workflow")
    }

    func setWorkflowEnforcement(_ enabled: Bool) async throws -> RQWorkflowSettings {
        try await client.put("/settings/workflow", body: RQWorkflowSettings(enforceWorkflow: enabled))
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

/// `-bf_requests_fixtures YES`: canned users and configuration lists, and no-op writes, so
/// the admin screens render (and can be screenshotted) without a network.
struct FixtureAdminService: AdminServicing {
    private static func decode<T: Decodable>(_ json: String) -> T {
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static let fixtureUsers: [RQAdminUser] = decode("""
        [{"id":"u-1","name":"Priya Shah","email":"priya.shah@example.com","department":"Engineering","role":"admin","status":true,"teamName":["Core Platform"],"lastSeen":"2 hours ago"},
         {"id":"u-2","name":"Daniel Okafor","email":"daniel.okafor@example.com","department":"Engineering","role":"developer","status":true,"teamName":["Core Platform","SAP Basis"]},
         {"id":"u-3","name":"Mei Lin","email":"mei.lin@example.com","department":"Quality","role":"release-manager","status":true,"teamName":["Release"]},
         {"id":"u-4","name":"Tomás Rivera","email":"tomas.rivera@example.com","department":"Operations","role":"developer","status":false,"teamName":[]}]
        """)

    private static func configItems(_ labels: [String]) -> [RQConfigItem] {
        decode("[" + labels.enumerated().map { #"{"id":"c-\#($0.offset)","type":"\#($0.element)"}"# }.joined(separator: ",") + "]")
    }

    func users(search: String, active: Bool) async throws -> [RQAdminUser] {
        Self.fixtureUsers.filter { $0.isActive == active && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    func allUsers() async throws -> [RQAdminUser] { Self.fixtureUsers }
    func user(id: String) async throws -> RQAdminUser? { Self.fixtureUsers.first { $0.id == id } }
    func departments() async throws -> [RQNamedOption] { [] }
    func roles() async throws -> [RQNamedOption] { [] }
    func createUser(_ payload: RQUserPayload) async throws {}
    func updateUser(id: String, _ payload: RQUserPayload) async throws {}
    func setUserActive(id: String, active: Bool, updatedBy: String) async throws {}
    func templates() async throws -> [RQRequestTemplate] { [] }
    func template(id: String) async throws -> RQRequestTemplate? { nil }
    func createTemplate(_ payload: RQTemplatePayload) async throws {}
    func updateTemplate(id: String, _ payload: RQTemplatePayload) async throws {}
    func teams(search: String) async throws -> [RQAdminTeam] { [] }
    func team(id: String) async throws -> RQAdminTeam? { nil }
    func usersNotInTeam(teamId: String, search: String) async throws -> [RQAdminUser] { [] }
    func createTeam(_ payload: RQTeamPayload) async throws {}
    func updateTeam(_ payload: RQTeamPayload) async throws {}
    func configList(_ kind: RQConfigKind) async throws -> [RQConfigItem] {
        switch kind {
        case .applications: return Self.configItems(["SAP S/4HANA", "Customer Portal", "Mobile App"])
        case .requestTypes: return Self.configItems(["Break-fix", "Emergency", "Enhancement", "Proposal"])
        case .priorities: return Self.configItems(["High", "Medium", "Low"])
        case .projectTypes: return Self.configItems(["Enhancement", "Optimization"])
        }
    }
    func systems() async throws -> [RQSAPSystem] {
        Self.decode(#"[{"id":"s-1","sid":"DEV","name":"Development","description":"S/4HANA development","host":"sapdev.example.com","user":"","client":["100"]}]"#)
    }
    func systems(appId: String) async throws -> [RQSAPSystem] { [] }
    func applications() async throws -> [ChangeRequestPlatform] { [] }
    func workflowSettings() async throws -> RQWorkflowSettings { RQWorkflowSettings(enforceWorkflow: false) }
    func setWorkflowEnforcement(_ enabled: Bool) async throws -> RQWorkflowSettings { RQWorkflowSettings(enforceWorkflow: enabled) }
    func addConfigItem(_ kind: RQConfigKind, _ payload: RQTypePayload) async throws {}
    func addApplication(_ payload: RQApplicationPayload) async throws {}
    func gitRepos() async throws -> [RQGitRepo] { [] }
    func createGitRepo(_ payload: RQNewGitRepo) async throws {}
}
