import Foundation

// MARK: - BlueRequests Fixtures
// Canned BlueRequests data plus fixture-backed implementations of every service
// protocol, selected by RequestsServices when `-bf_requests_fixtures YES` is set
// (BFFeatureFlags.requestsFixtures). Lets the Requests screens be exercised in the
// Simulator, in UI tests and in App Store screenshot automation without a live trm
// backend. Ported from trm-ios's ScreenshotFixtures, minus its auth bootstrap — cai's
// own ScreenshotFixtures already seeds the signed-in user.
//
// Unlike cai's ScreenshotFixtures this isn't DEBUG-only: it's static data behind a
// flag that defaults off, and keeping it in Release lets a TestFlight build show the
// Requests space before the backend accepts `individual`-realm tokens
// (docs/BLUEREQUESTS_INTEGRATION.md, "Tenancy").

enum RequestsFixtures {
    static var isEnabled: Bool { BFFeatureFlags.requestsFixtures }

    private static let crTimeline: [ChangeRequestTimelineEntry] = [
        ChangeRequestTimelineEntry(
            userName: "Alex Smith", fieldName: "status", fromStatus: "Submitted", toStatus: "In Review",
            createdAt: Date().addingTimeInterval(-3600)
        ),
        ChangeRequestTimelineEntry(
            userName: "system", fieldName: "Quality Check", fromStatus: nil, toStatus: nil,
            createdAt: Date().addingTimeInterval(-7200)
        ),
        ChangeRequestTimelineEntry(
            userName: "John Doe", fieldName: "status", fromStatus: "created", toStatus: nil,
            createdAt: Date().addingTimeInterval(-86400 * 2)
        )
    ]

    static let projects: [RQProject] = [
        RQProject(id: "28", name: "Finance Core — S/4HANA"),
        RQProject(id: "14", name: "Procurement"),
        RQProject(id: "9", name: "Platform")
    ]

    static let changeRequests: [ChangeRequest] = [
        ChangeRequest(
            id: "32", requestNumber: "CR-1042",
            title: "Add index to orders table for reporting query",
            description: "The nightly reporting job is timing out on the orders table full "
                + "scan. Adding a composite index on (customer_id, created_at) should bring "
                + "it well under the SLA.",
            status: ChangeRequestStatus(raw: "inreview"), severity: "High", requestTypeLabel: "Database",
            requestedByUserId: "u-2", createdByName: "John Doe",
            projectId: "28", projectName: "Finance Core — S/4HANA",
            platforms: [ChangeRequestPlatform(sap: "PRD-EU2", description: "Production EU2")],
            timeline: crTimeline, createdAt: Date().addingTimeInterval(-86400 * 2),
            stage: 2, totalStages: 2, stageStatus: "Review"
        ),
        ChangeRequest(
            id: "31", requestNumber: "CR-1041", title: "Rotate expired TLS cert on gateway",
            description: nil, status: ChangeRequestStatus(raw: "approved"),
            severity: "Critical", requestTypeLabel: "Infra",
            requestedByUserId: "u-3", createdByName: "Alex Smith",
            projectId: "9", projectName: "Platform", platforms: [], timeline: [],
            createdAt: Date().addingTimeInterval(-86400 * 5),
            stage: nil, totalStages: nil, stageStatus: nil
        ),
        ChangeRequest(
            id: "30", requestNumber: "CR-1038", title: "Enable feature flag for new approval workflow",
            description: nil, status: ChangeRequestStatus(raw: "submitted"),
            severity: "Low", requestTypeLabel: "Config",
            requestedByUserId: "u-2", createdByName: "John Doe",
            projectId: "9", projectName: "Platform", platforms: [], timeline: [],
            createdAt: Date().addingTimeInterval(-86400 * 7),
            stage: nil, totalStages: nil, stageStatus: nil
        ),
        ChangeRequest(
            id: "29", requestNumber: "CR-1030", title: "Archive stale project records",
            description: nil, status: ChangeRequestStatus(raw: "completed"),
            severity: "Low", requestTypeLabel: "Cleanup",
            requestedByUserId: "u-4", createdByName: "Maria Rivera",
            projectId: "14", projectName: "Procurement", platforms: [], timeline: [],
            createdAt: Date().addingTimeInterval(-86400 * 20),
            stage: nil, totalStages: nil, stageStatus: nil
        )
    ]

    static let releases: [RQRelease] = [
        RQRelease(
            changeRequestId: "32", requestId: "CR-1042", name: "Reporting query fix",
            description: nil, status: ReleaseStatus(raw: "planned"),
            plannedOn: Date().addingTimeInterval(86400 * 2)
        ),
        RQRelease(
            changeRequestId: "31", requestId: "CR-1041", name: "TLS cert rotation",
            description: nil, status: ReleaseStatus(raw: "inprogress"),
            plannedOn: Date().addingTimeInterval(86400 * 2)
        ),
        RQRelease(
            changeRequestId: "29", requestId: "CR-1030", name: "Archive stale records",
            description: nil, status: ReleaseStatus(raw: "released"),
            plannedOn: Date().addingTimeInterval(-86400 * 3)
        )
    ]

    static let comments: [String: [RQComment]] = [
        "32": [
            RQComment(
                bodyHTML: "Looks good — can you also add the migration rollback script?",
                authorName: "Alex Smith", createdAt: Date().addingTimeInterval(-5400)
            ),
            RQComment(
                bodyHTML: "Added in the latest commit, PTAL.",
                authorName: "Jane Doe", createdAt: Date().addingTimeInterval(-1800),
                attachments: [RQAttachment(id: "a-1", fileName: "migration_plan.pdf")]
            )
        ]
    ]
}

// MARK: - Fixture-Backed Services

struct FixtureChangeRequestService: ChangeRequestServicing {
    func listChangeRequests(filter: ChangeRequestFilter) async throws -> [ChangeRequest] {
        RequestsFixtures.changeRequests
    }

    func changeRequest(id: String) async throws -> ChangeRequest {
        guard let match = RequestsFixtures.changeRequests.first(where: { $0.id == id }) else {
            throw RequestsAPIError.serverError(404, "Not found")
        }
        return match
    }

    func create(_ payload: NewChangeRequestPayload) async throws -> ChangeRequest {
        RequestsFixtures.changeRequests.first!
    }

    func update(_ payload: ChangeRequestUpdatePayload) async throws {}
}

struct FixtureCommentService: CommentServicing {
    func comments(forChangeRequestId id: String) async throws -> [RQComment] {
        RequestsFixtures.comments[id] ?? []
    }

    func postComment(_ body: String, attachments: [RQAttachment], forChangeRequestId id: String) async throws -> RQComment {
        RQComment(bodyHTML: body, authorName: "Jane Doe", createdAt: Date(), attachments: attachments)
    }
}

struct FixtureReferenceDataService: ReferenceDataServicing {
    func requestTypes(forceRefresh: Bool = false) async throws -> [RequestTypeOption] {
        [RequestTypeOption(id: "1", type: "Database"), RequestTypeOption(id: "2", type: "Infra")]
    }

    func severities(forceRefresh: Bool = false) async throws -> [SeverityOption] {
        [SeverityOption(id: "1", type: "Low"), SeverityOption(id: "2", type: "Medium"), SeverityOption(id: "3", type: "High")]
    }

    func users(forceRefresh: Bool = false) async throws -> [UserOption] {
        [UserOption(id: "u-1", name: "Jane Doe"), UserOption(id: "u-2", name: "John Doe")]
    }
}

struct FixtureAttachmentService: AttachmentServicing {
    func upload(fileURL: URL) async throws -> RQAttachment {
        RQAttachment(id: UUID().uuidString, fileName: fileURL.lastPathComponent)
    }

    func download(id: String) async throws -> (data: Data, mimeType: String?, fileName: String) {
        (Data(), "text/plain", "fixture.txt")
    }
}

struct FixtureCRFileService: CRFileServicing {
    func list(projectId: String, changeRequestId: String) async throws -> [CRFile] { [] }

    func upload(projectId: String, changeRequestId: String, fileURL: URL) async throws -> CRFile {
        CRFile(name: fileURL.lastPathComponent, size: 0, uploaderName: "Jane Doe", url: "https://example.com")
    }
}

struct FixtureTeamService: TeamServicing {
    func listTeams(forceRefresh: Bool = false) async throws -> [RQTeam] {
        [
            RQTeam(id: "t-1", name: "Platform", members: [
                ProjectTeamMember(id: "u-1", name: "Jane Doe", profileImageURL: nil),
                ProjectTeamMember(id: "u-2", name: "John Doe", profileImageURL: nil)
            ]),
            RQTeam(id: "t-2", name: "Finance Core", members: [
                ProjectTeamMember(id: "u-3", name: "Maria Rivera", profileImageURL: nil)
            ])
        ]
    }
}

struct FixtureNotificationsService: NotificationsServicing {
    func unreadCounts() async throws -> UnreadCounts {
        UnreadCounts(totalUnreadMessages: 2, perCRUnreadCounts: [.init(crNumber: "32", count: 2)])
    }
}

struct FixtureProfileService: ProfileServicing {
    func fetchProfile(userId: String) async throws -> UserProfile {
        UserProfile(
            id: userId, name: "Jane Doe", email: "jane.doe@bluefunda.com",
            department: "Engineering", role: "Reviewer", teamName: "Platform",
            notification: true
        )
    }

    func updateNotificationPreference(_ enabled: Bool, userId: String) async throws {}
}

struct FixtureProjectService: ProjectServicing {
    func listProjects(forceRefresh: Bool = false) async throws -> [RQProject] {
        RequestsFixtures.projects
    }

    private static let fixtureTeam = [
        ProjectTeamMember(id: "u-1", name: "Jane Doe", profileImageURL: nil),
        ProjectTeamMember(id: "u-2", name: "John Doe", profileImageURL: nil)
    ]

    func listProjectDetails(forceRefresh: Bool = false) async throws -> [ProjectDetail] {
        RequestsFixtures.projects.map { project in
            ProjectDetail(
                id: project.id, name: project.name, description: "Fixture project description.",
                jira: nil, projectTypeLabel: "SAP", ownerName: "Jane Doe", requestCount: 3,
                team: Self.fixtureTeam
            )
        }
    }

    func projectDetail(id: String, forceRefresh: Bool = false) async throws -> ProjectDetail {
        let name = RequestsFixtures.projects.first { $0.id == id }?.name ?? "Untitled Project"
        return ProjectDetail(
            id: id, name: name, description: "Fixture project description.",
            jira: nil, projectTypeLabel: "SAP", ownerName: "Jane Doe", requestCount: 3,
            team: Self.fixtureTeam
        )
    }
}

struct FixtureReleaseService: ReleaseServicing {
    func listReleases(limit: Int? = nil) async throws -> [RQRelease] {
        RequestsFixtures.releases
    }
}
