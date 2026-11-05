import SwiftUI

// MARK: - Manage Teams (admin)
// trm's web Manage Teams (adminConfig/manageTeams): create teams and add or remove
// members. Updates send the whole member list, as the web does.

struct ManageTeamsView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        AdminDestination(state: state, navigationControl: navigationControl) { context in
            ManageTeamsScreen(context: context)
        }
    }
}

private struct ManageTeamsScreen: View {
    let context: AdminContext
    @StateObject private var loader = AdminLoader<RQAdminTeam>()
    @State private var searchText = ""
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(searchText: $searchText, searchPrompt: "Search teams")
            AdminListContent(loader: loader, subject: "teams", emptyTitle: "No teams",
                             emptyIcon: "person.3", reload: reload) {
                ForEach(loader.items) { team in
                    NavigationLink(value: team) {
                        HStack {
                            Text(team.name).font(RQFont.rowTitle)
                            Spacer()
                            Text("\(team.members.count) members").font(RQFont.meta).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .background(BFColor.surfaceCanvas)
        .navigationTitle("Manage Teams")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isCreating = true } label: { Label("New Team", systemImage: "plus") }
            }
        }
        .navigationDestination(for: RQAdminTeam.self) { team in
            TeamMembersScreen(context: context, team: team, onChange: reload)
        }
        .sheet(isPresented: $isCreating) {
            NewTeamSheet(context: context, onSaved: reload)
        }
        .task(id: searchText) {
            if !searchText.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .refreshable { await reload() }
    }

    private func reload() async {
        let search = searchText.trimmedValue
        await loader.load { try await context.service.teams(search: search) }
    }
}

private struct NewTeamSheet: View {
    let context: AdminContext
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red).font(RQFont.meta) }
                TextField("Team name", text: $name)
            }
            .navigationTitle("New Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AdminFormToolbar(canSave: !name.trimmedValue.isEmpty, isSaving: isSaving,
                                 save: { Task { await save() } }, cancel: { dismiss() })
            }
        }
    }

    private func save() async {
        isSaving = true
        do {
            try await context.service.createTeam(RQTeamPayload(name: name.trimmedValue, createdBy: context.userId,
                                                               updatedBy: context.userId))
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Members

private struct TeamMembersScreen: View {
    let context: AdminContext
    let team: RQAdminTeam
    let onChange: () async -> Void

    @State private var members: [RQAdminUser] = []
    @State private var error: String?
    @State private var isSaving = false
    @State private var isAdding = false

    var body: some View {
        List {
            if let error {
                InlineErrorBanner(message: error) { Task { await load() } }
                    .listRowSeparator(.hidden)
            }
            ForEach(members) { member in
                HStack(spacing: BFSpacing._3) {
                    RQAvatar(urlString: member.profileImage, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name).font(RQFont.rowTitle)
                        Text([member.department, member.role].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(RQFont.meta).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        Task { await save(members.filter { $0.id != member.id }.map(\.id)) }
                    }
                }
            }
            if members.isEmpty && error == nil {
                Text("No members yet").foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button { isAdding = true } label: { Label("Add Members", systemImage: "person.badge.plus") }
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            AddMembersSheet(context: context, teamId: team.id) { added in
                await save(members.map(\.id) + added)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            members = try await context.service.team(id: team.id)?.members ?? team.members
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save(_ memberIds: [String]) async {
        isSaving = true
        do {
            try await context.service.updateTeam(RQTeamPayload(
                id: team.id, name: team.name, createdBy: context.userId, updatedBy: context.userId,
                members: memberIds
            ))
            await load()
            await onChange()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

private struct AddMembersSheet: View {
    let context: AdminContext
    let teamId: String
    let onAdd: ([String]) async -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loader = AdminLoader<RQAdminUser>()
    @State private var searchText = ""
    @State private var selected: Set<String> = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ListScreenHeader(searchText: $searchText, searchPrompt: "Search users")
                AdminListContent(loader: loader, subject: "users", emptyTitle: "No users to add",
                                 emptyIcon: "person.badge.plus", reload: reload) {
                    ForEach(loader.items) { user in
                        Button {
                            if selected.contains(user.id) { selected.remove(user.id) } else { selected.insert(user.id) }
                        } label: {
                            HStack(spacing: BFSpacing._3) {
                                RQAvatar(urlString: user.profileImage, size: 28)
                                Text(user.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selected.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(user.id) ? BFColor.primary : Color.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AdminFormToolbar(canSave: !selected.isEmpty, isSaving: isSaving, save: {
                    Task {
                        isSaving = true
                        await onAdd(Array(selected))
                        dismiss()
                    }
                }, cancel: { dismiss() })
            }
            .task(id: searchText) {
                if !searchText.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
                guard !Task.isCancelled else { return }
                await reload()
            }
        }
    }

    private func reload() async {
        let search = searchText.trimmedValue
        await loader.load { try await context.service.usersNotInTeam(teamId: teamId, search: search) }
    }
}
