import Foundation

// MARK: - Requests DTOs (bluerequests: Change Requests / Projects / Releases)
//
// Field names are inferred from trm-backend-go's internal/model/model.go —
// there is no OpenAPI spec for trm-bff. Verify against
// trm-bff/docs/postman/trm-bff-collection.json against a real environment
// before trusting these shapes in production; adjust CodingKeys there rather
// than guessing further here.

enum ChangeRequestStatus: String, Codable, CaseIterable {
    case planned
    case inprogress
    case completed
    case blocked

    var title: String {
        switch self {
        case .planned: return "Planned"
        case .inprogress: return "In Progress"
        case .completed: return "Completed"
        case .blocked: return "Blocked"
        }
    }
}

enum QualityCheckStatus: String, Codable {
    case pending
    case inProgress = "in progress"
    case success
    case fail
}

// MARK: - Project

struct ProjectDTO: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let jira: String?
    let owner: String?
    let projectStatus: String?
    let projectType: String?
    let archived: Bool?
    let requestCount: Int?
    let createdAt: String?
    let createdBy: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, jira, owner
        case projectStatus, projectType, archived, requestCount
        case createdAt, createdBy
    }
}

struct ProjectListResponse: Codable {
    let projects: [ProjectDTO]

    // Tolerates { "projects": [...] }, { "data": [...] }, or a bare array —
    // same defensive pattern as ChatListResponse in APIModels.swift, since
    // the exact wrapper key hasn't been confirmed against a live response.
    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let items = try? container.decode([ProjectDTO].self, forKey: .projects) {
                self.projects = items
                return
            }
            if let items = try? container.decode([ProjectDTO].self, forKey: .data) {
                self.projects = items
                return
            }
        }
        let container = try decoder.singleValueContainer()
        self.projects = (try? container.decode([ProjectDTO].self)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projects, forKey: .projects)
    }

    enum CodingKeys: String, CodingKey { case projects, data }
}

// MARK: - Change Request

struct ChangeRequestDTO: Codable, Identifiable {
    let id: String
    let shortDescription: String?
    let description: String?
    let projectId: String?
    let releaseId: String?
    let requestId: String?
    let requestType: String?
    let severity: String?
    let status: ChangeRequestStatus?
    let qualityCheck: QualityCheckStatus?
    let ticketId: String?
    let ticketUrl: String?
    let requestedBy: String?
    let estimatedTime: String?
    let repo: String?
    let createdAt: String?
    let createdBy: String?
    let updatedAt: String?
    let updatedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, shortDescription, description, projectId, releaseId, requestId
        case requestType, severity, status, qualityCheck, ticketId, ticketUrl
        case requestedBy, estimatedTime, repo
        case createdAt, createdBy, updatedAt, updatedBy
    }
}

struct ChangeRequestListResponse: Codable {
    let changeRequests: [ChangeRequestDTO]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let items = try? container.decode([ChangeRequestDTO].self, forKey: .changeRequests) {
                self.changeRequests = items
                return
            }
            if let items = try? container.decode([ChangeRequestDTO].self, forKey: .data) {
                self.changeRequests = items
                return
            }
        }
        let container = try decoder.singleValueContainer()
        self.changeRequests = (try? container.decode([ChangeRequestDTO].self)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(changeRequests, forKey: .changeRequests)
    }

    enum CodingKeys: String, CodingKey { case changeRequests, data }
}

// MARK: - Release
// Keyed 1:1 off its owning Change Request — trm-backend-go's Release table
// has no own id column, changeRequestId is its primary key.

struct ReleaseDTO: Codable, Identifiable {
    var id: String { changeRequestId }
    let changeRequestId: String
    let status: String?
    let description: String?
    let plannedOn: String?
    let createdAt: String?
    let createdBy: String?
    let updatedAt: String?
    let updatedBy: String?

    enum CodingKeys: String, CodingKey {
        case changeRequestId, status, description, plannedOn
        case createdAt, createdBy, updatedAt, updatedBy
    }
}

struct ReleaseListResponse: Codable {
    let releases: [ReleaseDTO]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let items = try? container.decode([ReleaseDTO].self, forKey: .releases) {
                self.releases = items
                return
            }
            if let items = try? container.decode([ReleaseDTO].self, forKey: .data) {
                self.releases = items
                return
            }
        }
        let container = try decoder.singleValueContainer()
        self.releases = (try? container.decode([ReleaseDTO].self)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(releases, forKey: .releases)
    }

    enum CodingKeys: String, CodingKey { case releases, data }
}
