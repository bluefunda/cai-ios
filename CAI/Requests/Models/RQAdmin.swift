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

/// One stage of a request template's workflow. Department and role are stored by name.
struct RQTemplateStage: Codable, Hashable, Identifiable {
    var id = UUID()
    var description: String
    var department: String
    var role: String
    var qaDeploy: Bool

    private enum CodingKeys: String, CodingKey { case description, department, role, qaDeploy }

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

    private enum CodingKeys: String, CodingKey { case id, name, status, workflow }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? UUID().uuidString
        name = c.lenient(.name) ?? ""
        isActive = c.lenient(.status) ?? true
        workflow = c.lenient(.workflow) ?? []
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

    private enum CodingKeys: String, CodingKey { case id, type, description }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type: String? = c.lenient(.type)
        let description: String? = c.lenient(.description)
        label = (type?.isEmpty == false ? type : description) ?? ""
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

struct RQTemplatePayload: Encodable {
    struct Stage: Encodable {
        let statusCode: String
        let description: String
        let department: String
        let role: String
        let qaDeploy: Bool
        let order: Int
    }

    let name: String
    let workflow: [Stage]
    let status = true
    let createdBy: String

    init(name: String, stages: [RQTemplateStage], createdBy: String) {
        self.name = name
        self.createdBy = createdBy
        workflow = stages.filter(\.isComplete).enumerated().map { index, stage in
            Stage(statusCode: stage.description, description: stage.description, department: stage.department,
                  role: stage.role, qaDeploy: stage.qaDeploy, order: index + 1)
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
