import SwiftUI

// MARK: - Projects Destination
// Ported from trm-ios. The view model lives in RequestsState (see its doc comment).
// Toolbar: filter only — there's no create endpoint for projects.

struct ProjectsListView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        NavigationStack {
            Group {
                if let model = state.projects {
                    ProjectsListScreen(model: model, navigationControl: navigationControl)
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
    let navigationControl: ShellNavigationControl
    @State private var showFilterSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(searchText: $model.searchText, searchPrompt: "Search projects")
            content
        }
        .background(BFColor.surfaceCanvas)
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FilterToolbarButton(isActive: model.filters != ProjectFilters()) { showFilterSheet = true }
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
