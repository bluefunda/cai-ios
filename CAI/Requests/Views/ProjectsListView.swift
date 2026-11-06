import SwiftUI

// MARK: - Projects Destination
// Ported from trm-ios. The view model lives in RequestsState (see its doc comment).
// Toolbar: filter, and New project (the web's CreateUpdateProjectForm).

struct ProjectsListView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        NavigationStack {
            Group {
                if let model = state.projects {
                    ProjectsListScreen(model: model, state: state, navigationControl: navigationControl)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .shellNavigationControl(navigationControl)
                }
            }
            // Pushed by value (not the bare id String) — a String destination is the
            // change request, which Project Detail's embedded list also pushes.
            .navigationDestination(for: ProjectDetail.self) { project in
                ProjectDetailView(projectId: project.id, state: state)
            }
            .navigationDestination(for: String.self) { id in
                ChangeRequestDetailView(changeRequestId: id, state: state)
            }
        }
    }
}

private struct ProjectsListScreen: View {
    @ObservedObject var model: ProjectsListViewModel
    @ObservedObject var state: RequestsState
    let navigationControl: ShellNavigationControl
    @State private var showFilterSheet = false
    @State private var showNewProject = false

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(searchText: $model.searchText, searchPrompt: "Search projects")
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BFColor.surfaceCanvas)
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FilterToolbarButton(isActive: model.filters != ProjectFilters()) { showFilterSheet = true }
            }
            if state.services != nil, state.currentUserId != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewProject = true } label: {
                        Label("New project", systemImage: "plus")
                    }
                    .help("New project")
                    .bfPointerHover()
                    .accessibilityIdentifier("projects.new")
                }
            }
        }
        .sheet(isPresented: $showNewProject) {
            if let services = state.services, let userId = state.currentUserId {
                ProjectFormView(model: ProjectFormViewModel(
                    projectService: services.projectService,
                    projectTypes: { try await services.adminService.configList(.projectTypes) },
                    users: { try await services.referenceDataService.users(forceRefresh: false) },
                    currentUserId: userId
                )) {
                    await model.load(forceRefresh: true)
                }
            }
        }
        .shellNavigationControl(navigationControl)
        .task { await model.loadIfNeeded() }
        .refreshable { await model.load(forceRefresh: true) }
        .sheet(isPresented: $showFilterSheet) {
            ProjectFilterSheet(model: model)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.projects.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.projects.isEmpty {
            RequestsErrorCard(message: RequestsErrorCard.message(for: error, subject: "projects")) {
                Task { await model.load(forceRefresh: true) }
            }
        } else if model.filteredProjects.isEmpty {
            if !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else if model.filters != ProjectFilters() {
                ContentUnavailableView {
                    Label("No projects match these filters", systemImage: "folder")
                } actions: {
                    Button("Clear filters") { model.filters = ProjectFilters() }
                        .bfPointerHover()
                }
            } else {
                ContentUnavailableView("No projects yet", systemImage: "folder")
            }
        } else {
            List {
                if let error = model.error {
                    InlineErrorBanner(message: error) { Task { await model.load(forceRefresh: true) } }
                        .listRowSeparator(.hidden)
                }
                ForEach(model.filteredProjects) { project in
                    NavigationLink(value: project) {
                        ProjectRow(project: project)
                    }
                    .listRowBackground(BFColor.surfaceCanvas)
                    .listRowSeparatorTint(BFColor.hairline)
                    .bfPointerHover()
                    .accessibilityIdentifier("requests.projectRow.\(project.id)")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct ProjectRow: View {
    let project: ProjectDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(project.name)
                    .font(RQFont.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let count = project.requestCount {
                    Text("\(count) request\(count == 1 ? "" : "s")")
                        .font(RQFont.meta)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                if let type = project.projectTypeLabel, !type.isBlank {
                    Text(type)
                        .font(RQFont.label)
                        .foregroundStyle(BFColor.secondaryAdaptive)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BFColor.statusBlueFill, in: Capsule())
                }
                if let owner = project.ownerName, !owner.isBlank {
                    Label(owner, systemImage: "person")
                        .font(RQFont.meta)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
                if !project.team.isEmpty {
                    TeamStack(members: project.team, showsLabel: false)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

// MARK: - Team Stack

/// Overlapping member avatars + "Name and N others" — trm's own project/team display.
/// Shared by Projects and Teams.
struct TeamStack: View {
    let members: [ProjectTeamMember]
    var showsLabel = true

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: -7) {
                ForEach(members.prefix(4)) { member in
                    RQAvatar(urlString: member.profileImageURL, size: 22)
                        .overlay(Circle().strokeBorder(BFColor.surfaceCanvas, lineWidth: 1.5))
                }
            }
            if showsLabel, let first = members.first {
                Text(label(first))
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(members.first.map(label) ?? "No members")
    }

    private func label(_ first: ProjectTeamMember) -> String {
        let remaining = members.count - 1
        return remaining > 0 ? "\(first.name) and \(remaining) other\(remaining == 1 ? "" : "s")" : first.name
    }
}

// MARK: - New / Edit Project Sheet

struct ProjectFormView: View {
    @StateObject var model: ProjectFormViewModel
    let onCreated: () async -> Void
    /// Editing only, for someone allowed to: deletes the project and returns why it
    /// couldn't, or nil once it's gone.
    var onDelete: (() async -> String?)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(required: "Project name", text: $model.name)
                        .accessibilityIdentifier("projects.new.name")
                    TextField(required: "Description", text: $model.description, axis: .vertical)
                        .lineLimit(3...8)
                        .formMultilineField()
                } header: {
                    Text("Project")
                } footer: {
                    RequiredFieldsNote()
                }

                Section {
                    Picker(required: "Project type", selection: $model.projectTypeId) {
                        Text("Select…").tag(String?.none)
                        ForEach(model.projectTypeChoices, id: \.id) { type in
                            Text(type.label).tag(String?.some(type.id))
                        }
                    }
                    Picker(required: "Owner", selection: $model.ownerId) {
                        Text("Select…").tag(String?.none)
                        ForEach(model.ownerChoices, id: \.id) { user in
                            Text(user.name).tag(String?.some(user.id))
                        }
                    }
                }

                Section("Optional") {
                    TextField("Ticket link", text: $model.ticketUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if model.editing != nil, onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            HStack {
                                Text("Delete project")
                                if isDeleting {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isDeleting)
                        .accessibilityIdentifier("projects.delete")
                    } footer: {
                        Text("Only a project with no requests can be deleted. Move or delete its requests first.")
                    }
                }
            }
            .disabled(model.isSaving || isDeleting)
            .confirmationDialog("Delete this project?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete project", role: .destructive) {
                    Task {
                        isDeleting = true
                        deleteError = await onDelete?()
                        isDeleting = false
                        if deleteError == nil { dismiss() }
                    }
                }
            } message: {
                Text("It's removed from Projects for everyone.")
            }
            .alert("Couldn't delete the project",
                   isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            // An alert, not a row at the bottom: a failed save was easy to miss there.
            .alert(model.editing == nil ? "Couldn't create the project" : "Couldn't save the project",
                   isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) { model.error = nil }
            } message: {
                Text(model.error ?? "")
            }
            .navigationTitle(model.editing == nil ? "New project" : "Edit project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Button(model.editing == nil ? "Create project" : "Save") {
                            Task {
                                if await model.save() {
                                    await onCreated()
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!model.isValid)
                        .accessibilityIdentifier("projects.new.create")
                    }
                }
            }
            .task { await model.loadOptions() }
        }
    }
}
