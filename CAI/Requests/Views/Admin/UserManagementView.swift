import SwiftUI

// MARK: - User Management (admin)
// trm's web User Management (adminConfig/userManagement): Active/Inactive users with
// search, a user's details with Deactivate, and an invite/edit form.

struct UserManagementView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        AdminDestination(state: state, navigationControl: navigationControl) { context in
            UserManagementScreen(context: context)
        }
    }
}

private struct UserManagementScreen: View {
    let context: AdminContext
    @StateObject private var loader = AdminLoader<RQAdminUser>()
    @State private var searchText = ""
    @State private var showsActive = true
    @State private var editing: UserFormTarget?

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(searchText: $searchText, searchPrompt: "Search users") {
                Picker("Status", selection: $showsActive) {
                    Text("Active").tag(true)
                    Text("Inactive").tag(false)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            } secondaryRowTrailing: {
                EmptyView()
            }
            AdminListContent(loader: loader, subject: "users", emptyTitle: "No users",
                             emptyIcon: "person.badge.key", reload: reload) {
                ForEach(loader.items) { user in
                    NavigationLink(value: user) { UserRow(user: user) }
                }
            }
        }
        .background(BFColor.surfaceCanvas)
        .navigationTitle("User Management")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Label("Add User", systemImage: "plus") }
            }
        }
        .navigationDestination(for: RQAdminUser.self) { user in
            UserDetailScreen(context: context, userId: user.id, onChange: reload)
        }
        .sheet(item: $editing) { target in
            UserFormSheet(context: context, target: target, onSaved: reload)
        }
        // Debounced like the web's 1s search; a toggle change reloads at once.
        .task(id: "\(showsActive)|\(searchText)") {
            if !searchText.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .refreshable { await reload() }
    }

    private func reload() async {
        let search = searchText.trimmedValue
        let active = showsActive
        await loader.load { try await context.service.users(search: search, active: active) }
    }
}

private struct UserRow: View {
    let user: RQAdminUser

    var body: some View {
        HStack(spacing: BFSpacing._3) {
            RQAvatar(urlString: user.profileImage, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name.isEmpty ? user.email : user.name)
                    .font(RQFont.rowTitle)
                    .lineLimit(1)
                Text([user.department, user.role].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: BFSpacing._2)
            if !user.teamNames.isEmpty {
                Text(user.teamNames.joined(separator: ", "))
                    .font(RQFont.meta)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

private struct UserDetailScreen: View {
    let context: AdminContext
    let userId: String
    let onChange: () async -> Void

    @State private var user: RQAdminUser?
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmsDeactivate = false
    @State private var editing: UserFormTarget?

    var body: some View {
        Form {
            if let error {
                InlineErrorBanner(message: error) { Task { await load() } }
            }
            if let user {
                Section {
                    HStack(spacing: BFSpacing._3) {
                        RQAvatar(urlString: user.profileImage, size: 48)
                        VStack(alignment: .leading) {
                            Text(user.name).font(RQFont.rowTitle)
                            Text(user.isActive ? "Active" : "Inactive")
                                .font(RQFont.meta)
                                .foregroundStyle(user.isActive ? Color.green : Color.secondary)
                        }
                    }
                }
                Section {
                    AdminField(label: "Email", value: user.email)
                    AdminField(label: "Department", value: user.department)
                    AdminField(label: "Role", value: user.role)
                    AdminField(label: "Teams", value: user.teamNames.joined(separator: ", "))
                    AdminField(label: "Last seen", value: user.lastSeen ?? "")
                }
                if user.isActive {
                    Section {
                        Button("Deactivate User", role: .destructive) { confirmsDeactivate = true }
                            .disabled(isWorking)
                    }
                }
            } else if error == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("User Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let user {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editing = .edit(user) }
                }
            }
        }
        .confirmationDialog("Deactivate this user?", isPresented: $confirmsDeactivate, titleVisibility: .visible) {
            Button("Deactivate", role: .destructive) { Task { await deactivate() } }
        }
        .sheet(item: $editing) { target in
            UserFormSheet(context: context, target: target) {
                await load()
                await onChange()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            user = try await context.service.user(id: userId)
            error = user == nil ? "This user wasn't found." : nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deactivate() async {
        isWorking = true
        do {
            try await context.service.deactivateUser(id: userId, updatedBy: context.userId)
            await load()
            await onChange()
        } catch {
            self.error = error.localizedDescription
        }
        isWorking = false
    }
}

// MARK: - Form

enum UserFormTarget: Identifiable {
    case new
    case edit(RQAdminUser)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let user): return user.id
        }
    }
}

private struct UserFormSheet: View {
    let context: AdminContext
    let target: UserFormTarget
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var workPlace = ""
    @State private var departmentId: String?
    @State private var roleId: String?
    @State private var teamIds: Set<String> = []

    @State private var departments: [RQNamedOption] = []
    @State private var roles: [RQNamedOption] = []
    @State private var teams: [RQAdminTeam] = []
    @State private var isSaving = false
    @State private var error: String?

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    private var canSave: Bool {
        !email.trimmedValue.isEmpty && !firstName.trimmedValue.isEmpty && departmentId != nil && roleId != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Text(error).foregroundStyle(.red).font(RQFont.meta)
                }
                Section("User") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disabled(!isNew)
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                }
                Section("Access") {
                    Picker("Department", selection: $departmentId) {
                        Text("Select").tag(String?.none)
                        ForEach(departments) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    Picker("Role", selection: $roleId) {
                        Text("Select").tag(String?.none)
                        ForEach(roles) { Text($0.name).tag(String?.some($0.id)) }
                    }
                }
                Section("Teams") {
                    ForEach(teams) { team in
                        Toggle(team.name, isOn: Binding(
                            get: { teamIds.contains(team.id) },
                            set: { isOn in if isOn { teamIds.insert(team.id) } else { teamIds.remove(team.id) } }
                        ))
                    }
                }
            }
            .navigationTitle(isNew ? "Add User" : "Edit User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AdminFormToolbar(canSave: canSave, isSaving: isSaving,
                                 save: { Task { await save() } }, cancel: { dismiss() })
            }
            .task { await loadOptions() }
        }
    }

    private func loadOptions() async {
        do {
            async let departments = context.service.departments()
            async let roles = context.service.roles()
            async let teams = context.service.teams(search: "")
            (self.departments, self.roles, self.teams) = try await (departments, roles, teams)
        } catch {
            self.error = error.localizedDescription
        }
        guard case .edit(let summary) = target else { return }
        // The single-user response carries the form's fields (names for department/role).
        let user = (try? await context.service.user(id: summary.id)) ?? summary
        email = user.email
        firstName = user.firstName
        lastName = user.lastName
        workPlace = user.workPlace
        departmentId = departments.first { $0.name == user.department }?.id
        roleId = roles.first { $0.name == user.role }?.id
        teamIds = Set(user.teamIds)
    }

    private func save() async {
        guard let departmentId, let roleId else { return }
        isSaving = true
        error = nil
        var payload = RQUserPayload(
            email: email.trimmedValue, department: departmentId, role: roleId, team: Array(teamIds),
            firstName: firstName.trimmedValue, lastName: lastName.trimmedValue, workPlace: workPlace
        )
        do {
            switch target {
            case .new:
                payload.createdBy = context.userId
                payload.roleName = roles.first { $0.id == roleId }?.name
                payload.departmentName = departments.first { $0.id == departmentId }?.name
                try await context.service.createUser(payload)
            case .edit(let user):
                payload.updatedBy = context.userId
                try await context.service.updateUser(id: user.id, payload)
            }
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
