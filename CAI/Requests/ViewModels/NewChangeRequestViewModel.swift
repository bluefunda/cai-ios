import Foundation

/// The New Request form's optional lists, as the web's createUpdateChangeRequestForm loads
/// them: templates, teams (to narrow stage owners), applications (platforms) and an SAP
/// platform's systems. Closures so tests can supply just these.
struct NewRequestFormSources {
    var templates: () async throws -> [RQRequestTemplate]
    var teams: () async throws -> [RQAdminTeam]
    var applications: () async throws -> [ChangeRequestPlatform]
    var systems: (_ appId: String) async throws -> [RQSAPSystem]
    /// The organization's "Approvals for every request" switch: when on, the backend
    /// refuses a request without a template.
    var workflowSettings: () async throws -> RQWorkflowSettings

    init(
        templates: @escaping () async throws -> [RQRequestTemplate] = { [] },
        teams: @escaping () async throws -> [RQAdminTeam] = { [] },
        applications: @escaping () async throws -> [ChangeRequestPlatform] = { [] },
        systems: @escaping (_ appId: String) async throws -> [RQSAPSystem] = { _ in [] },
        workflowSettings: @escaping () async throws -> RQWorkflowSettings = { RQWorkflowSettings(enforceWorkflow: false) }
    ) {
        self.templates = templates
        self.teams = teams
        self.applications = applications
        self.systems = systems
        self.workflowSettings = workflowSettings
    }

    init(admin: AdminServicing) {
        self.init(
            templates: { try await admin.templates() },
            teams: { try await admin.teams(search: "") },
            applications: { try await admin.applications() },
            systems: { try await admin.systems(appId: $0) },
            workflowSettings: { try await admin.workflowSettings() }
        )
    }
}

/// One of the chosen template's stages, with the owner picked for it.
struct DraftStage: Identifiable, Equatable {
    let order: Int
    let description: String
    let statusCode: String
    let qaDeploy: Bool
    var ownerId: String?

    var id: Int { order }
}

/// Someone who can own a stage: a member of the chosen team, or any user.
struct StageOwnerChoice: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
final class NewChangeRequestViewModel: ObservableObject {
    @Published var requestName = ""
    @Published var description = ""
    @Published var selectedProjectId: String? {
        didSet {
            guard oldValue != selectedProjectId else { return }
            if !repos.contains(selectedRepo) { selectedRepo = "" }
            refreshGitHubRepos()
        }
    }
    @Published var selectedRequestTypeId: String?
    @Published var selectedSeverityId: String?
    @Published var selectedOwnerId: String?
    @Published var ticketUrl = ""
    @Published var requestNumber = ""

    /// Choosing a template lays out its stages; owners picked so far are dropped, as on
    /// the web.
    @Published var selectedTemplateId: String? {
        didSet {
            guard oldValue != selectedTemplateId else { return }
            let workflow = templates.first { $0.id == selectedTemplateId }?.workflow ?? []
            stages = workflow.enumerated().map { index, stage in
                DraftStage(
                    order: stage.order ?? index + 1,
                    description: stage.description,
                    statusCode: stage.statusCode.isEmpty ? stage.description : stage.statusCode,
                    qaDeploy: stage.qaDeploy
                )
            }
            refreshGitHubRepos()
        }
    }
    @Published var stages: [DraftStage] = []
    /// Narrows the stage owner choices to one team's members; nil offers every user.
    @Published var selectedTeamId: String?

    @Published var selectedPlatformIds: Set<String> = [] {
        didSet {
            guard oldValue != selectedPlatformIds else { return }
            if !hasSAPPlatform { selectedSystemId = nil; systems = []; systemsAppId = nil }
            if !hasGitPlatform { selectedRepo = "" }
            if hasSAPPlatform, let appId = firstSAPPlatformId, appId != systemsAppId {
                Task { await loadSystems(appId: appId) }
            }
        }
    }
    @Published var selectedSystemId: String?
    @Published var selectedRepo = ""
    @Published var qaBranch = NewChangeRequestPayload.DeploymentBranch(system: "qa")
    @Published var prdBranch = NewChangeRequestPayload.DeploymentBranch(system: "prd")

    // "Create GitHub issue" (trm's createCrGitHubIssueOption): only for a tech template
    // whose project has bound repos. The repos are read here, so the form is unchanged
    // when there are none or the integration is unavailable.
    @Published private(set) var githubRepos: [ProjectRepo] = []
    @Published private(set) var isLoadingGitHubRepos = false
    @Published var createGitHubIssue = false {
        didSet {
            guard oldValue != createGitHubIssue else { return }
            githubIssueRepoId = createGitHubIssue ? (githubIssueRepoId ?? githubRepos.first?.id) : nil
        }
    }
    @Published var githubIssueRepoId: String?
    /// Why the issue wasn't created, after a submit whose request was: shown on the new
    /// request's detail.
    private(set) var githubIssueNotice: String?
    private var githubReposRequest = 0

    @Published private(set) var projects: [RQProject] = []
    @Published private(set) var requestTypes: [RequestTypeOption] = []
    @Published private(set) var severities: [SeverityOption] = []
    @Published private(set) var users: [UserOption] = []
    @Published private(set) var templates: [RQRequestTemplate] = []
    @Published private(set) var teams: [RQAdminTeam] = []
    @Published private(set) var applications: [ChangeRequestPlatform] = []
    @Published private(set) var systems: [RQSAPSystem] = []
    private var systemsAppId: String?

    /// Approvals for every request are on, so a template must be chosen (the backend
    /// answers 422 template_required otherwise).
    @Published private(set) var templateRequired = false
    @Published private(set) var isLoadingOptions = false
    @Published private(set) var isSubmitting = false
    @Published var error: String?

    /// Set when launched from Project Detail — locks the Project picker to that project,
    /// matching how trm's own web form pre-fills (but still shows) the project field there.
    let lockedProjectId: String?

    private let changeRequestService: ChangeRequestServicing
    private let projectService: ProjectServicing
    private let referenceDataService: ReferenceDataServicing
    private let sources: NewRequestFormSources
    private let currentUserId: String?
    private let githubService: GitHubServicing?
    /// Hands the new request's id and the GitHub notice to whoever shows its detail.
    private let onGitHubIssueNotice: ((_ changeRequestId: String, _ notice: String) -> Void)?

    init(
        changeRequestService: ChangeRequestServicing,
        projectService: ProjectServicing,
        referenceDataService: ReferenceDataServicing,
        sources: NewRequestFormSources = NewRequestFormSources(),
        currentUserId: String?,
        lockedProjectId: String? = nil,
        githubService: GitHubServicing? = nil,
        onGitHubIssueNotice: ((_ changeRequestId: String, _ notice: String) -> Void)? = nil
    ) {
        self.changeRequestService = changeRequestService
        self.projectService = projectService
        self.referenceDataService = referenceDataService
        self.sources = sources
        self.currentUserId = currentUserId
        self.lockedProjectId = lockedProjectId
        self.githubService = githubService
        self.onGitHubIssueNotice = onGitHubIssueNotice
    }

    /// Matches the real web form's own required-field set exactly (see the trm-ios plan's
    /// field-scope table) — Ticket Link is the only optional field.
    var isValid: Bool {
        !requestName.trimmingCharacters(in: .whitespaces).isEmpty
            && !description.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedProjectId != nil
            && selectedRequestTypeId != nil
            && selectedSeverityId != nil
            && selectedOwnerId != nil
            && (!templateRequired || selectedTemplateId != nil)
    }

    var selectedTemplate: RQRequestTemplate? { templates.first { $0.id == selectedTemplateId } }

    var isTechTemplate: Bool { selectedTemplate?.kind == .tech }

    /// The option shows for a tech template whose project has bound repos.
    var showsGitHubIssueOption: Bool { isTechTemplate && !githubRepos.isEmpty && githubService != nil }

    /// Reads the chosen project's bound repos when a tech template is picked; anything
    /// else (or a failed read) hides the option and turns it off.
    func refreshGitHubRepos() {
        githubReposRequest += 1
        let request = githubReposRequest
        githubRepos = []
        createGitHubIssue = false
        guard isTechTemplate, let projectId = selectedProjectId, let githubService else {
            isLoadingGitHubRepos = false
            return
        }
        isLoadingGitHubRepos = true
        Task {
            let repos = (try? await githubService.projectRepos(projectId: projectId)) ?? []
            guard request == githubReposRequest else { return }
            githubRepos = repos
            isLoadingGitHubRepos = false
        }
    }

    /// Only active templates are offered, as the web lists them.
    var activeTemplates: [RQRequestTemplate] { templates.filter(\.isActive) }

    var selectedPlatforms: [ChangeRequestPlatform] {
        applications.filter { $0.id.map(selectedPlatformIds.contains) ?? false }
    }
    var hasSAPPlatform: Bool { selectedPlatforms.contains(where: \.isSAP) }
    var hasGitPlatform: Bool { selectedPlatforms.contains(where: \.usesGit) }
    private var firstSAPPlatformId: String? { selectedPlatforms.first(where: \.isSAP)?.id }

    /// The chosen project's repositories (the web's `projectData.repos`).
    var repos: [String] { projects.first { $0.id == selectedProjectId }?.repos ?? [] }

    var ownerChoices: [StageOwnerChoice] {
        if let team = teams.first(where: { $0.id == selectedTeamId }) {
            return team.members.map { StageOwnerChoice(id: $0.id, name: $0.name) }
        }
        return users.map { StageOwnerChoice(id: $0.id, name: $0.name) }
    }

    func ownerName(for stage: DraftStage) -> String? {
        guard let id = stage.ownerId else { return nil }
        return (ownerChoices + users.map { StageOwnerChoice(id: $0.id, name: $0.name) })
            .first { $0.id == id }?.name
    }

    func setOwner(_ ownerId: String?, for order: Int) {
        guard let index = stages.firstIndex(where: { $0.order == order }) else { return }
        stages[index].ownerId = ownerId
    }

    func togglePlatform(_ platform: ChangeRequestPlatform) {
        guard let id = platform.id else { return }
        if selectedPlatformIds.contains(id) {
            selectedPlatformIds.remove(id)
        } else {
            selectedPlatformIds.insert(id)
        }
    }

    /// Fills the title and description from an assistant answer, keeping anything typed.
    func applying(_ prefill: NewRequestPrefill) -> Self {
        if requestName.isEmpty { requestName = prefill.title }
        if description.isEmpty { description = prefill.description }
        return self
    }

    func loadOptions() async {
        isLoadingOptions = true
        error = nil
        do {
            async let p = projectService.listProjects(forceRefresh: false)
            async let rt = referenceDataService.requestTypes(forceRefresh: false)
            async let sv = referenceDataService.severities(forceRefresh: false)
            async let us = referenceDataService.users(forceRefresh: false)
            (projects, requestTypes, severities, users) = try await (p, rt, sv, us)
            if let lockedProjectId { selectedProjectId = lockedProjectId }
            // Only someone the picker lists: an id it lacks shows as a blank picker.
            if selectedOwnerId == nil, let currentUserId, users.contains(where: { $0.id == currentUserId }) {
                selectedOwnerId = currentUserId
            }
        } catch {
            self.error = error.localizedDescription
        }
        // The optional sections: a list that fails to load leaves its section empty rather
        // than blocking the required fields.
        async let t = try? sources.templates()
        async let tm = try? sources.teams()
        async let a = try? sources.applications()
        async let w = try? sources.workflowSettings()
        let (loadedTemplates, loadedTeams, loadedApplications, settings) = await (t, tm, a, w)
        // Unknown (the read failed) counts as off: the backend still has the final say.
        templateRequired = settings?.enforceWorkflow ?? false
        templates = loadedTemplates ?? []
        teams = loadedTeams ?? []
        applications = loadedApplications ?? []
        isLoadingOptions = false
    }

    private func loadSystems(appId: String) async {
        systemsAppId = appId
        let loaded = (try? await sources.systems(appId)) ?? []
        guard systemsAppId == appId else { return }
        systems = loaded
        if !systems.contains(where: { $0.id == selectedSystemId }) { selectedSystemId = nil }
    }

    func makePayload() -> NewChangeRequestPayload? {
        guard isValid,
              let projectId = selectedProjectId.flatMap(Int.init),
              let requestType = selectedRequestTypeId,
              let severity = selectedSeverityId,
              let owner = selectedOwnerId,
              let currentUserId
        else { return nil }

        var payload = NewChangeRequestPayload(
            shortDescription: requestName.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            projectId: projectId,
            requestType: requestType,
            severity: severity,
            requestedBy: owner,
            createdBy: currentUserId,
            ticketUrl: ticketUrl.trimmingCharacters(in: .whitespaces)
        )
        payload.platform = selectedPlatforms
        payload.template = selectedTemplateId
        payload.stage = stages.enumerated().map { index, stage in
            NewChangeRequestPayload.Stage(
                order: stage.order, description: stage.description, statusCode: stage.statusCode,
                qaDeploy: stage.qaDeploy, owner: stage.ownerId, current: index == 0,
                updatedBy: currentUserId)
        }
        payload.requestId = requestNumber.trimmingCharacters(in: .whitespaces)
        if hasGitPlatform {
            payload.repo = selectedRepo
            payload.deploymentBranches = [qaBranch, prdBranch].map {
                var branch = $0
                branch.source = branch.source.trimmingCharacters(in: .whitespaces)
                branch.target = branch.target.trimmingCharacters(in: .whitespaces)
                return branch
            }
        }
        if hasSAPPlatform { payload.sapSourceSystemId = selectedSystemId }
        return payload
    }

    func submit() async -> ChangeRequest? {
        guard let payload = makePayload() else { return nil }

        isSubmitting = true
        error = nil
        defer { isSubmitting = false }

        let created: ChangeRequest
        do {
            created = try await changeRequestService.create(payload)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
        // The request exists now: a failed issue never undoes or blocks it. Its detail
        // shows why, and its GitHub tab is where to try again.
        githubIssueNotice = nil
        if createGitHubIssue, showsGitHubIssueOption, let githubService {
            if let repoId = githubIssueRepoId {
                do {
                    _ = try await githubService.addIssue(changeRequestId: created.id, .create(projectRepoId: repoId))
                } catch {
                    githubIssueNotice = GitHubIntegration.issueFailureNotice(
                        GitHubIntegration.issueErrorMessage(error, mode: .create))
                }
            }
            if let githubIssueNotice { onGitHubIssueNotice?(created.id, githubIssueNotice) }
        }
        return created
    }
}
