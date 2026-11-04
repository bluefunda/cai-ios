import Foundation

/// Type/Owner are client-side only — the BFF-proxied `/projects` fetch this view model uses
/// supports no server-side filtering at all (see ProjectService's own doc comment), so every
/// project is always fetched and these two facets just narrow what's already in memory,
/// same posture as the Requests screen's client-side status chips.
struct ProjectFilters: Equatable {
    var projectType: String?
    var owner: String?
}

@MainActor
final class ProjectsListViewModel: ObservableObject {
    @Published private(set) var projects: [ProjectDetail] = []
    @Published private(set) var isLoading = false
    @Published var searchText: String = ""
    @Published var filters = ProjectFilters()
    @Published var error: String?

    private let service: ProjectServicing

    init(service: ProjectServicing) {
        self.service = service
    }

    /// Distinct, sorted values actually present in the loaded projects — populates the
    /// Filter sheet's pickers without a separate reference-data endpoint.
    var availableProjectTypes: [String] {
        Set(projects.compactMap(\.projectTypeLabel)).sorted()
    }

    var availableOwners: [String] {
        Set(projects.compactMap(\.ownerName)).sorted()
    }

    var filteredProjects: [ProjectDetail] {
        var result = projects
        if let projectType = filters.projectType {
            result = result.filter { $0.projectTypeLabel == projectType }
        }
        if let owner = filters.owner {
            result = result.filter { $0.ownerName == owner }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter { $0.name.lowercased().contains(query) }
        }
        return result
    }

    /// True once a load has finished (success or failure) — screens call
    /// `loadIfNeeded()` on appear, so switching back to a destination reconnects to
    /// data already on screen instead of refetching it (see RequestsState).
    @Published private(set) var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load(forceRefresh: false)
    }

    func load(forceRefresh: Bool = true) async {
        isLoading = true
        error = nil
        do {
            projects = try await service.listProjectDetails(forceRefresh: forceRefresh)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true
    }
}

// MARK: - New / Edit Project
// The web's CreateUpdateProjectForm: name, description, project type and owner are
// required; the ticket link is optional. A new project's owner starts as the signed-in
// user; editing starts from the project's own values.

@MainActor
final class ProjectFormViewModel: ObservableObject {
    @Published var name = ""
    @Published var description = ""
    @Published var projectTypeId: String?
    @Published var ownerId: String?
    @Published var ticketUrl = ""

    @Published private(set) var projectTypes: [RQConfigItem] = []
    @Published private(set) var users: [UserOption] = []
    @Published private(set) var isLoadingOptions = false
    @Published private(set) var isSaving = false
    @Published var error: String?

    private let projectService: ProjectServicing
    private let projectTypesSource: () async throws -> [RQConfigItem]
    private let usersSource: () async throws -> [UserOption]
    private let currentUserId: String
    /// The project being edited; nil for a new one.
    let editing: ProjectDetail?

    init(projectService: ProjectServicing,
         projectTypes: @escaping () async throws -> [RQConfigItem],
         users: @escaping () async throws -> [UserOption],
         currentUserId: String,
         editing: ProjectDetail? = nil) {
        self.projectService = projectService
        self.projectTypesSource = projectTypes
        self.usersSource = users
        self.currentUserId = currentUserId
        self.editing = editing
        if let editing {
            name = editing.name
            description = editing.description ?? ""
            projectTypeId = editing.projectTypeId
            ownerId = editing.ownerId
            ticketUrl = editing.jira ?? ""
        }
    }

    var isValid: Bool {
        !name.trimmedValue.isEmpty && !description.trimmedValue.isEmpty
            && projectTypeId != nil && ownerId != nil
    }

    func loadOptions() async {
        isLoadingOptions = true
        defer { isLoadingOptions = false }
        do {
            async let types = projectTypesSource()
            async let people = usersSource()
            (projectTypes, users) = try await (types, people)
            if ownerId == nil, users.contains(where: { $0.id == currentUserId }) { ownerId = currentUserId }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func makePayload() -> NewProjectPayload? {
        guard isValid, let projectTypeId, let ownerId else { return nil }
        return NewProjectPayload(
            name: name.trimmedValue, description: description.trimmedValue, owner: ownerId,
            createdBy: currentUserId, updatedBy: currentUserId, projectType: projectTypeId,
            ticketUrl: ticketUrl.trimmedValue)
    }

    /// The project type choices, keeping the project's own type when the list doesn't
    /// have its id, so the picker never shows "Select…" for a type that's set.
    var projectTypeChoices: [(id: String, label: String)] {
        var choices = projectTypes.map { (id: $0.id, label: $0.label) }
        if let id = projectTypeId, !choices.contains(where: { $0.id == id }) {
            choices.insert((id: id, label: editing?.projectTypeLabel ?? id), at: 0)
        }
        return choices
    }

    /// The owner choices, keeping the project's own owner when the list doesn't have them.
    var ownerChoices: [(id: String, name: String)] {
        var choices = users.map { (id: $0.id, name: $0.name) }
        if let id = ownerId, !choices.contains(where: { $0.id == id }) {
            choices.insert((id: id, name: editing?.ownerName ?? id), at: 0)
        }
        return choices
    }

    func makeUpdatePayload() -> ProjectUpdatePayload? {
        guard let editing, let id = Int(editing.id), let payload = makePayload() else { return nil }
        return ProjectUpdatePayload(
            id: id, name: payload.name, description: payload.description, owner: payload.owner,
            projectType: payload.projectType, jira: payload.ticketUrl, updatedBy: currentUserId)
    }

    /// True once saved.
    func save() async -> Bool {
        guard isValid else { return false }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            if editing != nil {
                guard let update = makeUpdatePayload() else { return false }
                try await projectService.updateProject(update)
            } else {
                guard let payload = makePayload() else { return false }
                try await projectService.createProject(payload)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
