import Foundation

// MARK: - Admin & Git models
// What trm's web admin screens (src/components/adminConfig/*) and Git screens
// (src/components/git/*) read, decoded leniently like the rest of the Requests models:
// a missing or mistyped field falls back instead of failing the whole list.

extension KeyedDecodingContainer {
    /// The value at `key`, or nil when it's missing, null or a different type.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// A string that may arrive as a number (ids do, depending on the table).
    func lenientString(_ key: Key) -> String? {
        if let string: String = lenient(key) { return string }
        if let int: Int = lenient(key) { return String(int) }
        return nil
    }
}

/// `GET /user` row — User Management's list and detail, and Manage Teams' "Add User" list.
struct RQAdminUser: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let email: String
    let firstName: String
    let lastName: String
    let department: String
    let role: String
    let isActive: Bool
    let teamNames: [String]
    /// Team ids, on the single-user (`?id=`) response.
    let teamIds: [String]
    let lastSeen: String?
    let profileImage: String?
    let workPlace: String

    private enum CodingKeys: String, CodingKey {
        case id, name, email, firstName, lastName, department, role, status, teamName, team, teams
        case lastSeen, profileImage, workPlace
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        name = c.lenient(.name) ?? ""
        email = c.lenient(.email) ?? ""
        firstName = c.lenient(.firstName) ?? ""
        lastName = c.lenient(.lastName) ?? ""
        department = c.lenient(.department) ?? ""
        role = c.lenient(.role) ?? ""
        isActive = c.lenient(.status) ?? true
        let names: [String]? = c.lenient(.teamName)
        let teams: [String]? = c.lenient(.teams)
        teamNames = names ?? teams ?? []
        teamIds = c.lenient(.team) ?? []
        lastSeen = c.lenient(.lastSeen)
        profileImage = (c.lenient(.profileImage) as String?).flatMap { $0.isEmpty ? nil : $0 }
        workPlace = c.lenient(.workPlace) ?? ""
    }
}

/// A `{id, name}` option — departments (`/group`) and roles (`/role`).
struct RQNamedOption: Identifiable, Decodable, Hashable {
    let id: String
    let name: String

    private enum CodingKeys: String, CodingKey { case id, name }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? UUID().uuidString
        name = c.lenient(.name) ?? ""
    }
}

/// A template's kind (utilities/templateWorkflow.js): only a tech template can have
/// GitHub gate steps.
enum RQTemplateKind: String, CaseIterable, Identifiable {
    case standard, tech
    var id: String { rawValue }
    var title: String { self == .tech ? "Tech" : "Standard" }
}

/// A workflow step's type: an approval by the stage's department and role, or (tech
/// templates only) a GitHub gate satisfied by the linked pull requests.
enum RQStepType: String, Codable, CaseIterable, Identifiable {
    case approval
    case githubGate = "github_gate"
    var id: String { rawValue }
    var title: String { self == .githubGate ? "GitHub gate" : "Approval" }
}

/// A GitHub gate's policy, with the web's defaults (DEFAULT_GATE_POLICY) for any field a
/// stored step leaves out.
struct RQGatePolicy: Codable, Hashable {
    var requireMerged = true
    var requireApprovedAtHead = true
    var requireChecksGreen = true
    var minApprovals = 1

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requireMerged = c.lenient(.requireMerged) ?? true
        requireApprovedAtHead = c.lenient(.requireApprovedAtHead) ?? true
        requireChecksGreen = c.lenient(.requireChecksGreen) ?? true
        let approvals: Int? = c.lenient(.minApprovals)
        minApprovals = approvals.map { $0 < 0 ? 1 : $0 } ?? 1
    }

    private enum CodingKeys: String, CodingKey { case requireMerged, requireApprovedAtHead, requireChecksGreen, minApprovals }
}

/// One stage of a request template's workflow. Department and role are stored by name.
struct RQTemplateStage: Codable, Hashable, Identifiable {
    var id = UUID()
    var description: String
    var department: String
    var role: String
    var qaDeploy: Bool
    /// From a saved template's workflow; a stage being edited has neither yet.
    var order: Int?
    var statusCode = ""
    /// Older templates have no `type` or `gate`: they read as approval steps.
    var type: RQStepType = .approval
    var gate = RQGatePolicy()

    private enum CodingKeys: String, CodingKey { case description, department, role, qaDeploy, order, statusCode, type, gate }

    init(description: String = "", department: String = "", role: String = "", qaDeploy: Bool = false) {
        self.description = description
        self.department = department
        self.role = role
        self.qaDeploy = qaDeploy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = c.lenient(.description) ?? ""
        department = c.lenient(.department) ?? ""
        role = c.lenient(.role) ?? ""
        qaDeploy = c.lenient(.qaDeploy) ?? false
        order = c.lenient(.order)
        statusCode = c.lenient(.statusCode) ?? ""
        type = (c.lenient(.type) as String?).flatMap(RQStepType.init(rawValue:)) ?? .approval
        gate = (try? c.decodeIfPresent(RQGatePolicy.self, forKey: .gate)) ?? nil ?? RQGatePolicy()
    }

    var isComplete: Bool {
        ![description, department, role].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

struct RQRequestTemplate: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let isActive: Bool
    let workflow: [RQTemplateStage]
    var kind: RQTemplateKind = .standard
    /// Requests from this template move only through its approval steps (department
    /// and role approve each stage, or a GitHub gate passes).
    var requireApproval = false

    private enum CodingKeys: String, CodingKey { case id, name, status, workflow, kind, requireApproval }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? UUID().uuidString
        name = c.lenient(.name) ?? ""
        isActive = c.lenient(.status) ?? true
        workflow = c.lenient(.workflow) ?? []
        kind = (c.lenient(.kind) as String?).flatMap(RQTemplateKind.init(rawValue:)) ?? .standard
        requireApproval = c.lenient(.requireApproval) ?? false
    }
}

/// A Manage Teams row (`GET /teams`) with full member details.
struct RQAdminTeam: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let members: [RQAdminUser]

    private enum CodingKeys: String, CodingKey { case id, name, membersDetails }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? UUID().uuidString
        name = c.lenient(.name) ?? ""
        members = c.lenient(.membersDetails) ?? []
    }
}

/// Configurations' simple lists: priorities (`/severity`), request types, project types —
/// all `{type, description}`; applications use `description` only.
struct RQConfigItem: Identifiable, Decodable, Hashable {
    let id: String
    let label: String

    private enum CodingKeys: String, CodingKey { case id, type, description, name }

    /// The first non-empty of type, description and name; a row with none still shows.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let candidates: [String?] = [c.lenient(.type), c.lenient(.description), c.lenient(.name)]
        let found = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        // The web shows an application's description (configurations.js); a record saved
        // with none appears blank there, and "Untitled" here.
        label = found ?? "Untitled"
        id = c.lenientString(.id) ?? label
    }
}

struct RQSAPSystem: Identifiable, Decodable, Hashable {
    let id: String
    let sid: String
    let name: String
    let description: String
    let host: String
    let user: String
    let clients: [String]

    private enum CodingKeys: String, CodingKey { case id, sid, name, description, host, user, client }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? UUID().uuidString
        sid = c.lenient(.sid) ?? ""
        name = c.lenient(.name) ?? ""
        description = c.lenient(.description) ?? ""
        host = c.lenient(.host) ?? ""
        user = c.lenient(.user) ?? ""
        clients = c.lenient(.client) ?? []
    }
}

/// A Git repo (`GET /rest/git/sap/v1/repo`).
struct RQGitRepo: Identifiable, Decodable, Hashable {
    let id: String
    let url: String
    let package: String
    let branch: String
    let displayName: String
    let labels: String

    private enum CodingKeys: String, CodingKey { case key, url, package, branchname, localSettings }
    private enum LocalKeys: String, CodingKey { case displayName, labels }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.key) ?? UUID().uuidString
        url = c.lenient(.url) ?? ""
        package = c.lenient(.package) ?? ""
        branch = c.lenient(.branchname) ?? ""
        let local = try? c.nestedContainer(keyedBy: LocalKeys.self, forKey: .localSettings)
        displayName = local?.lenient(.displayName) ?? ""
        labels = local.flatMap { Self.labels(in: $0) } ?? ""
    }

    /// `labels` is a string on some repos and an array on others.
    private static func labels(in container: KeyedDecodingContainer<LocalKeys>) -> String? {
        if let text: String = container.lenient(.labels) { return text }
        let list: [String]? = container.lenient(.labels)
        return list?.joined(separator: ", ")
    }

    var title: String { displayName.isEmpty ? (url.split(separator: "/").last.map(String.init) ?? url) : displayName }
    /// The web's Branch/Tag column: the last segment of `branchname` (refs/heads/main → main).
    var branchShortName: String { branch.split(separator: "/").last.map(String.init) ?? branch }
}

// MARK: - Response envelopes

/// `{"<key>": [...]}` — every admin list response. Missing or null decodes as empty.
struct RQListEnvelope<Item: Decodable>: Decodable, EmptyDecodableResponse {
    let items: [Item]

    static var empty: Self { .init(items: []) }

    init(items: [Item]) { self.items = items }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Takes the first array-valued key, so one type serves `users`, `teams`, `roles`…
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        for key in c.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
            if let items = try? c.decode([Item].self, forKey: key) {
                self.items = items
                return
            }
        }
        items = []
    }
}

// MARK: - Request bodies

struct RQUserPayload: Encodable {
    var email: String
    var department: String
    var role: String
    var team: [String]
    var firstName: String
    var lastName: String
    var workPlace: String
    var notification = true
    var createdBy: String?
    var updatedBy: String?
    var roleName: String?
    var departmentName: String?
}

struct RQDeactivateUser: Encodable {
    let updatedBy: String
    let enabled = false
}

/// POST /admin/template and PUT /admin/template/update-template/{id}, as the web's
/// buildTemplatePayload sends it: the kind, and each complete step with its type (a gate
/// only on a tech template) and, for a gate, its policy. `order` is the step's position
/// in the editor, counted before incomplete steps are dropped, as on the web.
/// GET/PUT /settings/workflow (trm-backend-go settingsWorkflow.go) — the tenant's
/// workflow enforcement switch.
struct RQWorkflowSettings: Codable, Equatable {
    var enforceWorkflow: Bool
}

struct RQTemplatePayload: Encodable {
    struct Stage: Encodable, Equatable {
        let statusCode: String
        let description: String
        let department: String
        let role: String
        let qaDeploy: Bool
        let type: String
        let gate: RQGatePolicy?
        let order: Int

        private enum CodingKeys: String, CodingKey {
            case statusCode, description, department, role, qaDeploy, type, gate, order
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(statusCode, forKey: .statusCode)
            try c.encode(description, forKey: .description)
            try c.encode(department, forKey: .department)
            try c.encode(role, forKey: .role)
            try c.encode(qaDeploy, forKey: .qaDeploy)
            try c.encode(type, forKey: .type)
            try c.encodeIfPresent(gate, forKey: .gate)
            try c.encode(order, forKey: .order)
        }
    }

    let name: String
    let kind: String
    /// Sent every time, so an edit can switch approvals off as well as on.
    let requireApproval: Bool
    let workflow: [Stage]
    let status = true
    let createdBy: String

    init(name: String, kind: RQTemplateKind = .standard, requireApproval: Bool = false,
         stages: [RQTemplateStage], createdBy: String) {
        self.name = name
        self.kind = kind.rawValue
        self.requireApproval = requireApproval
        self.createdBy = createdBy
        workflow = stages.enumerated().compactMap { index, stage in
            guard stage.isComplete else { return nil }
            let isGate = stage.type == .githubGate && kind == .tech
            return Stage(statusCode: stage.description, description: stage.description, department: stage.department,
                         role: stage.role, qaDeploy: stage.qaDeploy,
                         type: isGate ? RQStepType.githubGate.rawValue : RQStepType.approval.rawValue,
                         gate: isGate ? stage.gate : nil, order: index + 1)
        }
    }
}

struct RQTeamPayload: Encodable {
    var id: String?
    let name: String
    let createdBy: String
    let updatedBy: String
    var members: [String]?
}

struct RQTypePayload: Encodable {
    let type: String
    let description: String
}

struct RQApplicationPayload: Encodable {
    struct Landscape: Encodable {
        let sourceSID: String
        let targetSID: String
    }

    let description: String
    let createdBy: String
    let git: Bool
    let sap: Bool
    let transports: Bool
    let landscape: [Landscape]
}

struct RQNewGitRepo: Encodable {
    let url: String
    let package: String
    let branchname: String
}
