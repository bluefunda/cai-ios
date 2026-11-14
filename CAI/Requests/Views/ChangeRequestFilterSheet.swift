import SwiftUI

/// Ported from trm-ios. Status, Priority (severity), Type, Request Owner, and Assignee — trm's own "filter
/// drawer" facets (see ChangeRequestFilter's doc comments), edited as a local draft and only
/// committed to the view model on Apply so Owner/Assignee/Severity/Type batch into a single
/// refetch instead of one per field. Priority, Type and the people come from the same lists
/// the web's filter uses (severities, request types, users), and are sent as ids.
///
/// A project's list passes `people` (its team, without you): those are offered after Me,
/// as the web's project Filter does, instead of every user.
struct ChangeRequestFilterSheet: View {
    @ObservedObject var model: ChangeRequestListViewModel
    var people: [UserOption]? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestsServices) private var services

    @State private var status: ChangeRequestStatus?
    @State private var draft = ChangeRequestAdvancedFilters()
    @State private var severities: [SeverityOption] = []
    @State private var requestTypes: [RequestTypeOption] = []
    @State private var users: [UserOption] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Status", selection: $status) {
                        Text("Any").tag(ChangeRequestStatus?.none)
                        ForEach(ChangeRequestStatus.allCases, id: \.self) { status in
                            Text(status.style.label).tag(ChangeRequestStatus?.some(status))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Classification") {
                    Picker("Priority", selection: $draft.severity) {
                        Text("Any").tag(String?.none)
                        ForEach(severities) { severity in
                            Text(severity.type).tag(String?.some(severity.id))
                        }
                    }
                    Picker("Type", selection: $draft.requestTypeId) {
                        Text("Any").tag(String?.none)
                        ForEach(requestTypes) { type in
                            Text(type.type).tag(String?.some(type.id))
                        }
                    }
                }

                Section("People") {
                    PersonPicker(title: "Request owner", isMe: $draft.ownerIsMe, userId: $draft.ownerId, users: users)
                    PersonPicker(title: "Assignee", isMe: $draft.assigneeIsMe, userId: $draft.assigneeId, users: users)
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        status = nil
                        draft = model.defaultAdvancedFilters
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        model.setStatusFilter(status)
                        model.advancedFilters = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task { await loadOptions() }
        }
        .onAppear {
            status = model.statusFilter
            draft = model.advancedFilters
        }
    }

    private func loadOptions() async {
        if let people { users = people }
        guard let reference = services?.referenceDataService, severities.isEmpty else { return }
        async let sv = try? reference.severities(forceRefresh: false)
        async let rt = try? reference.requestTypes(forceRefresh: false)
        let (loadedSeverities, loadedTypes) = await (sv, rt)
        severities = loadedSeverities ?? []
        requestTypes = loadedTypes ?? []
        guard people == nil else { return }
        let loadedUsers = try? await reference.users(forceRefresh: false)
        users = (loadedUsers ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Anyone, Me, or one person from the user list — the web lists every user for Request
/// Owner and Assignee.
private struct PersonPicker: View {
    let title: String
    @Binding var isMe: Bool
    @Binding var userId: String?
    let users: [UserOption]

    private enum Choice: Hashable { case anyone, me, user(String) }

    private var choice: Binding<Choice> {
        Binding(
            get: { isMe ? .me : userId.map(Choice.user) ?? .anyone },
            set: { newValue in
                switch newValue {
                case .anyone: isMe = false; userId = nil
                case .me: isMe = true; userId = nil
                case .user(let id): isMe = false; userId = id
                }
            }
        )
    }

    var body: some View {
        Picker(title, selection: choice) {
            Text("Anyone").tag(Choice.anyone)
            Text("Me").tag(Choice.me)
            if !users.isEmpty { Divider() }
            ForEach(users) { user in
                Text(user.name).tag(Choice.user(user.id))
            }
        }
    }
}
