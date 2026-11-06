import Foundation

@MainActor
final class ProjectDetailViewModel: ObservableObject {
    @Published private(set) var project: ProjectDetail?
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published private(set) var isDeleting = false
    /// Why the delete didn't happen, for the confirmation's alert.
    @Published var deleteError: String?

    let projectId: String
    /// The embedded change-request section reuses the exact same view model the top-level
    /// Requests screen uses, just scoped to this project — same List/Grid rendering, same
    /// Active/Archive + status filtering, no duplicated logic.
    let changeRequestListModel: ChangeRequestListViewModel

    private let projectService: ProjectServicing

    init(
        projectId: String,
        projectService: ProjectServicing,
        changeRequestService: ChangeRequestServicing,
        workflowService: ChangeRequestWorkflowServicing? = nil,
        currentUserId: String?
    ) {
        self.projectId = projectId
        self.projectService = projectService
        self.changeRequestListModel = ChangeRequestListViewModel(
            service: changeRequestService,
            workflowService: workflowService,
            currentUserId: currentUserId,
            projectId: projectId
        )
    }

    /// Deletes the project; false (with `deleteError`) when the backend refuses, e.g. while
    /// requests still belong to it.
    func delete() async -> Bool {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await projectService.deleteProject(id: projectId)
            return true
        } catch {
            deleteError = error.localizedDescription
            return false
        }
    }

    /// Admins, the owner and the creator may delete a project, as the backend allows.
    func canDelete(userId: String?, roles: [String]) -> Bool {
        if roles.contains(where: { ["admin", "super-admin"].contains($0) }) { return true }
        guard let userId, let project else { return false }
        return project.ownerId == userId || project.createdById == userId
    }

    /// `forceRefresh: false` (the initial load) reuses the Projects list's own very-recent
    /// fetch when this screen was reached by drilling down from it — no second network round
    /// trip for data that already exists. Pull-to-refresh passes `true` to guarantee a real
    /// network hit instead of silently no-op'ing against a still-cached result.
    func load(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        do {
            project = try await projectService.projectDetail(id: projectId, forceRefresh: forceRefresh)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        await changeRequestListModel.load()
    }
}
