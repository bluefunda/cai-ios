import SwiftUI

/// The create form (NewChangeRequestView), prefilled: Request, Project, Classification and
/// each stage's owner. Project and the stages themselves are fixed once created; only who
/// owns each stage changes (trm-backend-go's update applies a stage's owner and nothing
/// else). Status and Archive are separate, lightweight actions on the detail screen itself
/// (see ChangeRequestDetailView), matching the web.
struct EditChangeRequestView: View {
    let changeRequest: ChangeRequest
    @ObservedObject var model: ChangeRequestDetailViewModel

    /// Passed in rather than read from the environment — this is a sheet, and the shell
    /// re-injects explicitly into sheets (cai-ios#254).
    let services: RequestsServices?
    @Environment(\.dismiss) private var dismiss

    @State private var requestName: String
    @State private var description: String
    @State private var selectedRequestTypeId: String?
    @State private var selectedSeverityId: String?
    @State private var selectedOwnerId: String?
    /// Stage order → owner id; a stage missing here is unassigned.
    @State private var stageOwners: [Int: String]
    @State private var selectedTeamId: String?

    @State private var requestTypes: [RequestTypeOption] = []
    @State private var severities: [SeverityOption] = []
    @State private var users: [UserOption] = []
    @State private var teams: [RQAdminTeam] = []
    @State private var isLoadingOptions = false
    @State private var isSaving = false
    @State private var loadError: String?

    init(changeRequest: ChangeRequest, model: ChangeRequestDetailViewModel, services: RequestsServices?) {
        self.changeRequest = changeRequest
        self.model = model
        self.services = services
        _requestName = State(initialValue: changeRequest.title)
        _description = State(initialValue: changeRequest.description ?? "")
        _selectedOwnerId = State(initialValue: changeRequest.requestedByUserId)
        _stageOwners = State(initialValue: Self.owners(of: changeRequest))
    }

    private static func owners(of changeRequest: ChangeRequest) -> [Int: String] {
        Dictionary(changeRequest.stages.compactMap { stage in stage.ownerId.map { (stage.order, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// The same required set as create.
    private var isValid: Bool {
        !requestName.trimmedValue.isEmpty && !description.trimmedValue.isEmpty
            && selectedRequestTypeId != nil && selectedSeverityId != nil && selectedOwnerId != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(required: "Request name", text: $requestName)
                    TextField(required: "Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                        .formMultilineField()
                } header: {
                    Text("Request")
                }

                Section("Project") {
                    Text(changeRequest.projectName ?? "—")
                        .foregroundStyle(.secondary)
                }

                Section("Classification") {
                    Picker(required: "Type", selection: $selectedRequestTypeId) {
                        Text("Select…").tag(String?.none)
                        ForEach(requestTypes) { option in
                            Text(option.type).tag(String?.some(option.id))
                        }
                    }
                    Picker(required: "Priority", selection: $selectedSeverityId) {
                        Text("Select…").tag(String?.none)
                        ForEach(severities) { option in
                            Text(option.type).tag(String?.some(option.id))
                        }
                    }
                    Picker(required: "Request owner", selection: $selectedOwnerId) {
                        Text("Select…").tag(String?.none)
                        ForEach(users) { user in
                            Text(user.name).tag(String?.some(user.id))
                        }
                    }
                }

                if !changeRequest.stages.isEmpty {
                    Section("Stages") {
                        if !teams.isEmpty {
                            Picker("Team", selection: $selectedTeamId) {
                                Text("All users").tag(String?.none)
                                ForEach(teams) { team in
                                    Text(team.name).tag(String?.some(team.id))
                                }
                            }
                        }
                        ForEach(changeRequest.stages, id: \.order) { stage in
                            stageOwnerRow(stage)
                        }
                    }
                }
            }
            .navigationTitle("Edit request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .bfPointerHover()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSaving = true
                            await model.applyEdit(
                                shortDescription: changed(requestName, from: changeRequest.title),
                                description: changed(description, from: changeRequest.description ?? ""),
                                requestType: selectedRequestTypeId,
                                severity: selectedSeverityId,
                                requestedBy: changed(selectedOwnerId, from: changeRequest.requestedByUserId),
                                // The link isn't on the form any more (as on create); nil leaves it as it is.
                                ticketUrl: nil,
                                // Sent only when an owner changed, so a plain edit logs no stage activity.
                                stageOwners: stageOwners == Self.owners(of: changeRequest) ? nil : stageOwners
                            )
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save changes") }
                    }
                    .disabled(!isValid || isSaving)
                    .bfPointerHover()
                }
            }
            .task { await loadOptions() }
            .overlay {
                if isLoadingOptions { ProgressView() }
            }
            .alert("Couldn't load the form options", isPresented: .constant(loadError != nil)) {
                // A failed load previously left the Type/Priority/Owner pickers silently
                // empty with no explanation at all (`try?` swallowed the error) — most
                // commonly a transient backend blip after retries already ran out, so offer
                // a real retry instead of a dead-end form.
                if requestTypes.isEmpty {
                    Button("Retry") {
                        loadError = nil
                        Task { await loadOptions() }
                    }
                }
                Button("OK") { loadError = nil }
            } message: {
                Text(loadError ?? "")
            }
        }
    }

    // As on create: the stage on the left and a plain menu picker on the right. A team
    // narrows the owners offered, keeping one already picked from elsewhere so it still shows.
    private func stageOwnerRow(_ stage: RQStage) -> some View {
        let ownerId = stageOwners[stage.order]
        var choices = teams.first { $0.id == selectedTeamId }
            .map { $0.members.map { UserChoice(id: $0.id, name: $0.name) } }
            ?? users.map { UserChoice(id: $0.id, name: $0.name) }
        if let ownerId, !choices.contains(where: { $0.id == ownerId }),
           let name = users.first(where: { $0.id == ownerId })?.name {
            choices.insert(UserChoice(id: ownerId, name: name), at: 0)
        }
        return HStack {
            Text("\(stage.order). \(stage.description)")
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Picker("Owner of \(stage.description)", selection: Binding(
                get: { stageOwners[stage.order] },
                set: { stageOwners[stage.order] = $0 }
            )) {
                Text("Unassigned").tag(String?.none)
                ForEach(choices) { choice in
                    Text(choice.name).tag(String?.some(choice.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .accessibilityIdentifier("requests.edit.stageOwner")
    }

    private struct UserChoice: Identifiable {
        let id: String
        let name: String
    }

    private func loadOptions() async {
        guard let services, requestTypes.isEmpty else { return }
        isLoadingOptions = true
        loadError = nil
        do {
            async let rt = services.referenceDataService.requestTypes(forceRefresh: false)
            async let sv = services.referenceDataService.severities(forceRefresh: false)
            async let us = services.referenceDataService.users(forceRefresh: false)
            // Teams only narrow the stage owners; the form works without them.
            async let tm = try? services.adminService.teams(search: "")
            (requestTypes, severities, users) = try await (rt, sv, us)
            teams = (await tm) ?? []
            selectedSeverityId = severities.first { $0.type == changeRequest.severity }?.id
            selectedRequestTypeId = requestTypes.first { $0.type == changeRequest.requestTypeLabel }?.id
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingOptions = false
    }

    private func changed(_ new: String, from original: String) -> String? {
        new == original ? nil : new
    }

    private func changed(_ new: String?, from original: String?) -> String? {
        new == original ? nil : new
    }
}
