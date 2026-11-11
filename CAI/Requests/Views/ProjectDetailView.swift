import SwiftUI

// MARK: - Project Detail
// Ported from trm-ios: the project's header (type, team, owner, Jira, description), then
// its change requests through the same building blocks as the Requests destination —
// ArchiveTogglePicker and ChangeRequestListBody — so they look and behave the same.
// Between them, the GitHub repositories bound to the project (trm's projectRepos).

struct ProjectDetailView: View {
    let projectId: String
    @ObservedObject var state: RequestsState

    @StateObject private var box = ViewModelBox()
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        Group {
            if let model = box.model {
                ProjectDetailBody(model: model, reposModel: box.reposModel, state: state)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BFColor.surfaceCanvas)
        .task {
            guard let services = state.services, box.model == nil else { return }
            let model = ProjectDetailViewModel(
                projectId: projectId,
                projectService: services.projectService,
                changeRequestService: services.changeRequestService,
                workflowService: services.workflowService,
                currentUserId: state.currentUserId
            )
            box.reposModel = ProjectReposViewModel(
                projectId: projectId, service: services.githubService, roles: workspace.requestsRoles)
            box.model = model
            await model.load()
        }
    }

    private final class ViewModelBox: ObservableObject {
        @Published var model: ProjectDetailViewModel?
        @Published var reposModel: ProjectReposViewModel?
    }
}

private struct ProjectDetailBody: View {
    @ObservedObject var model: ProjectDetailViewModel
    let reposModel: ProjectReposViewModel?
    @ObservedObject var state: RequestsState

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var showFilterSheet = false
    @State private var showCreateSheet = false
    @State private var showEditSheet = false

    private var requests: ChangeRequestListViewModel { model.changeRequestListModel }

    var body: some View {
        VStack(spacing: 0) {
            if let project = model.project {
                header(project)
                if let reposModel {
                    ProjectReposSection(model: reposModel)
                        .padding(.horizontal, BFSpacing._4)
                        .padding(.bottom, BFSpacing._3)
                        .task { if reposModel.state == .loading { await reposModel.load() } }
                }
                BFHairline()
            } else if let error = model.error, !model.isLoading {
                InlineErrorBanner(message: error) {
                    model.error = nil
                    Task { await model.load(forceRefresh: true) }
                }
                .padding(.horizontal, BFSpacing._4)
            }

            ProjectRequestsSection(
                model: requests,
                viewMode: sizeClass == .compact ? .list : state.viewMode
            )
        }
        .navigationTitle(model.project?.name ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                FilterToolbarButton(isActive: requests.statusFilter != nil
                    || requests.advancedFilters != ChangeRequestAdvancedFilters()) {
                    showFilterSheet = true
                }
                if sizeClass != .compact {
                    ViewModeToolbarPicker(viewMode: $state.viewMode)
                }
                if model.project != nil {
                    Button { showEditSheet = true } label: {
                        Label("Edit project", systemImage: "pencil")
                    }
                    .help("Edit project")
                    .bfPointerHover()
                    .accessibilityIdentifier("projects.edit")
                }
                NewRequestToolbarButton { showCreateSheet = true }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let project = model.project, let services = state.services, let userId = state.currentUserId {
                ProjectFormView(model: ProjectFormViewModel(
                    projectService: services.projectService,
                    projectTypes: { try await services.adminService.configList(.projectTypes) },
                    users: { try await services.referenceDataService.users(forceRefresh: false) },
                    currentUserId: userId,
                    editing: project
                ), onCreated: {
                    await model.load(forceRefresh: true)
                    await state.projects?.load(forceRefresh: true)
                }, onDelete: model.canDelete(userId: userId, roles: workspace.requestsRoles) ? {
                    guard await model.delete() else { return model.deleteError ?? "The project wasn't deleted." }
                    // Gone: back to Projects, which no longer lists it.
                    await state.projects?.load(forceRefresh: true)
                    dismiss()
                    return nil
                } : nil)
            }
        }
        .refreshable {
            await model.load(forceRefresh: true)
            await reposModel?.load()
        }
        .sheet(isPresented: $showFilterSheet) {
            ChangeRequestFilterSheet(model: requests)
        }
        .sheet(isPresented: $showCreateSheet) {
            if let newModel = state.makeNewRequestModel(lockedProjectId: model.projectId) {
                NewChangeRequestView(model: newModel) { _ in
                    Task { await requests.load() }
                }
            }
        }
        .overlay {
            if model.isLoading && model.project == nil {
                ProgressView()
            }
        }
    }

    // MARK: Header

    private func header(_ project: ProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: BFSpacing._2) {
            HStack(spacing: BFSpacing._3) {
                if let type = project.projectTypeLabel, !type.isBlank {
                    Text(type)
                        .font(RQFont.label)
                        .foregroundStyle(BFColor.secondaryAdaptive)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BFColor.statusBlueFill, in: Capsule())
                }
                if !project.team.isEmpty {
                    TeamStack(members: project.team)
                }
                Spacer(minLength: 0)
                if let jira = project.jira, !jira.isBlank, let url = URL(string: jira) {
                    Link(destination: url) {
                        Label("Open in Jira", systemImage: "arrow.up.right.square")
                            .font(RQFont.meta)
                    }
                    .bfPointerHover()
                }
            }
            if let owner = project.ownerName, !owner.isBlank {
                Label("Owned by \(owner)", systemImage: "person")
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
            }
            if let description = project.description, !description.isBlank {
                Text(description)
                    .font(RQFont.body)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, BFSpacing._3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Holds the embedded list's model as `@ObservedObject`, so its search field and archive
/// switch stay in sync (see ArchiveTogglePicker's doc comment).
private struct ProjectRequestsSection: View {
    @ObservedObject var model: ChangeRequestListViewModel
    let viewMode: ChangeRequestViewMode

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(
                searchText: $model.searchText,
                searchPrompt: "Search this project's requests",
                secondaryRowLeading: { ArchiveTogglePicker(model: model) },
                secondaryRowTrailing: { EmptyView() }
            )
            ChangeRequestListBody(model: model, viewMode: viewMode, showsProject: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
