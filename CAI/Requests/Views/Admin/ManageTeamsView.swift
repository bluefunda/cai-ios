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
            AdminScreenHeader(
                title: "Manage Teams",
                subtitle: adminCount(loader.items.count, "team", loaded: loader.hasLoaded),
                actionTitle: "New team", actionIcon: "person.3", actionIdentifier: "admin.teams.new",
                action: { isCreating = true }, search: $searchText, searchPrompt: "Search teams"
            )
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
        .adminColumn()
        .navigationTitle("Manage Teams")
        .navigationBarTitleDisplayMode(.inline)
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
    /// Filters the members on screen, like the web's member search. Saves always start
    /// from the whole team, so removing someone while searching keeps everyone else.
    @State private var memberSearch = ""
    /// Asked before removing — the change saves to the team straight away.
    @State private var pendingRemoval: RQAdminUser?

    private var shownMembers: [RQAdminUser] {
        let query = memberSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return members }
        return members.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.email.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            membersList
        }
        // One readable column on a wide window: the title, search, Add members and each
        // member's Remove all line up together instead of sitting in the window's corners.
        .adminColumn()
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "this member") from \(team.name)?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let member = pendingRemoval else { return }
                // From the whole team, not the search results.
                Task { await save(members.filter { $0.id != member.id }.map(\.id)) }
            }
        }
        .sheet(isPresented: $isAdding) {
            AddMembersSheet(context: context, teamId: team.id) { added in
                await save(members.map(\.id) + added)
            }
        }
        .task { await load() }
    }

    private var header: some View {
        AdminScreenHeader(
            title: team.name,
            subtitle: members.count == 1 ? "1 member" : "\(members.count) members",
            actionTitle: "Add members", actionIcon: "person.badge.plus", actionIdentifier: "admin.team.addMembers",
            isBusy: isSaving, action: { isAdding = true },
            search: $memberSearch, searchPrompt: "Search members"
        )
    }

    private var membersList: some View {
        List {
            if let error {
                InlineErrorBanner(message: error) { Task { await load() } }
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(shownMembers) { member in
                    memberRow(member)
                        // Swipe on touch; on a Mac (no swipe with a mouse) the row's button
                        // and the right-click menu do the same.
                        .swipeActions {
                            Button("Remove", role: .destructive) { pendingRemoval = member }
                        }
                        .contextMenu {
                            Button("Remove from team", systemImage: "person.badge.minus", role: .destructive) {
                                pendingRemoval = member
                            }
                        }
                }
            }
            if members.isEmpty && error == nil {
                Text("No members yet").foregroundStyle(.secondary)
            } else if shownMembers.isEmpty && !memberSearch.isEmpty {
                Text("No members match \u{201C}\(memberSearch)\u{201D}").foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func memberRow(_ member: RQAdminUser) -> some View {
        HStack(spacing: BFSpacing._3) {
            RQAvatar(urlString: member.profileImage, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(RQFont.rowTitle)
                // Only when there's something to say: an empty line pushed the name above
                // the avatar's centre. The email stands in when there's no department or role.
                let roles = [member.department, member.role].filter { !$0.isEmpty }.joined(separator: " · ")
                let detail = roles.isEmpty ? member.email : roles
                if !detail.isEmpty {
                    Text(detail).font(RQFont.meta).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: BFSpacing._3)
            Button(role: .destructive) {
                pendingRemoval = member
            } label: {
                Text("Remove").font(RQFont.meta)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(BFColor.statusRedText)
            .disabled(isSaving)
            .help("Remove from team")
            .accessibilityLabel("Remove \(member.name) from team")
            .bfPointerHover()
            .accessibilityIdentifier("admin.team.removeMember")
        }
        .padding(.vertical, 6)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
