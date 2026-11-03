import SwiftUI

/// Ported from trm-ios, with the web create form's fields (createUpdateChangeRequestForm):
/// the required set, then the optional request number, platforms (with an SAP platform's
/// source system, or a Git platform's repository and branches) and a template whose stages
/// each get an owner.
///
/// Owns its view model (`@StateObject`): the presenting sheet's content closure can run
/// again while the sheet is up, and a re-created model would wipe what was typed.
struct NewChangeRequestView: View {
    @StateObject private var model: NewChangeRequestViewModel
    let onCreated: (ChangeRequest) -> Void

    init(model: NewChangeRequestViewModel, onCreated: @escaping (ChangeRequest) -> Void) {
        _model = StateObject(wrappedValue: model)
        self.onCreated = onCreated
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    TextField("Request name", text: $model.requestName)
                    TextField("Description", text: $model.description, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Request number (optional)", text: $model.requestNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("requests.new.requestNumber")
                }

                Section("Project") {
                    if model.lockedProjectId != nil {
                        Text(model.projects.first { $0.id == model.lockedProjectId }?.name ?? "—")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Project", selection: $model.selectedProjectId) {
                            Text("Select…").tag(String?.none)
                            ForEach(model.projects) { project in
                                Text(project.name).tag(String?.some(project.id))
                            }
                        }
                    }
                }

                Section("Classification") {
                    Picker("Type", selection: $model.selectedRequestTypeId) {
                        Text("Select…").tag(String?.none)
                        ForEach(model.requestTypes) { option in
                            Text(option.type).tag(String?.some(option.id))
                        }
                    }
                    Picker("Priority", selection: $model.selectedSeverityId) {
                        Text("Select…").tag(String?.none)
                        ForEach(model.severities) { option in
                            Text(option.type).tag(String?.some(option.id))
                        }
                    }
                    Picker("Request owner", selection: $model.selectedOwnerId) {
                        Text("Select…").tag(String?.none)
                        ForEach(model.users) { user in
                            Text(user.name).tag(String?.some(user.id))
                        }
                    }
                }

                if !model.applications.isEmpty {
                    PlatformSection(model: model)
                }

                StagesSection(model: model)

                Section("Optional") {
                    TextField("Ticket link", text: $model.ticketUrl)
                        #if !os(macOS)
                        .keyboardType(.URL)
                        #endif
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("New request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .bfPointerHover()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let created = await model.submit() {
                                onCreated(created)
                                dismiss()
                            }
                        }
                    } label: {
                        if model.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Create request")
                        }
                    }
                    .disabled(!model.isValid || model.isSubmitting)
                    .bfPointerHover()
                    .accessibilityIdentifier("requests.new.create")
                }
            }
            .task { await model.loadOptions() }
            .overlay {
                if model.isLoadingOptions && model.projects.isEmpty {
                    ProgressView()
                }
            }
            .alert("Couldn't create the request", isPresented: .constant(model.error != nil)) {
                // Reference-data (project/type/priority/owner) failures are recoverable —
                // most commonly seen as a transient backend blip after several retries
                // already ran out — so a full page reload of the sheet shouldn't be required
                // just to try again.
                if model.projects.isEmpty {
                    Button("Retry") {
                        model.error = nil
                        Task { await model.loadOptions() }
                    }
                }
                Button("OK") { model.error = nil }
            } message: {
                Text(model.error ?? "")
            }
        }
    }
}

/// Platforms, then what an SAP or Git platform adds.
private struct PlatformSection: View {
    @ObservedObject var model: NewChangeRequestViewModel

    var body: some View {
        Section {
            ForEach(model.applications, id: \.self) { platform in
                Button {
                    model.togglePlatform(platform)
                } label: {
                    HStack {
                        Text(platform.description ?? "Untitled")
                            .foregroundStyle(.primary)
                        Spacer()
                        if let id = platform.id, model.selectedPlatformIds.contains(id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("requests.new.platform")
            }
            if model.hasSAPPlatform {
                Picker("SAP source system", selection: $model.selectedSystemId) {
                    Text("Select…").tag(String?.none)
                    ForEach(model.systems) { system in
                        Text(system.name.isEmpty ? system.sid : system.name).tag(String?.some(system.id))
                    }
                }
            }
            if model.hasGitPlatform {
                Picker("Repository", selection: $model.selectedRepo) {
                    Text("Select…").tag("")
                    ForEach(model.repos, id: \.self) { repo in
                        Text(repo).tag(repo)
                    }
                }
                .disabled(model.repos.isEmpty)
                BranchFields(title: "QA", branch: $model.qaBranch)
                BranchFields(title: "PRD", branch: $model.prdBranch)
            }
        } header: {
            Text("Platform")
        } footer: {
            if model.hasGitPlatform && model.repos.isEmpty {
                Text("The selected project has no repositories.")
            }
        }
    }
}

private struct BranchFields: View {
    let title: String
    @Binding var branch: NewChangeRequestPayload.DeploymentBranch

    var body: some View {
        TextField("\(title) source branch", text: $branch.source)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        TextField("\(title) target branch", text: $branch.target)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}

/// The template, then each of its stages with an owner. A team narrows the owners offered.
private struct StagesSection: View {
    @ObservedObject var model: NewChangeRequestViewModel

    var body: some View {
        Section {
            Picker("Template", selection: $model.selectedTemplateId) {
                Text("None").tag(String?.none)
                ForEach(model.activeTemplates) { template in
                    Text(template.name).tag(String?.some(template.id))
                }
            }
            .accessibilityIdentifier("requests.new.template")
            if !model.stages.isEmpty {
                if !model.teams.isEmpty {
                    Picker("Team", selection: $model.selectedTeamId) {
                        Text("All users").tag(String?.none)
                        ForEach(model.teams) { team in
                            Text(team.name).tag(String?.some(team.id))
                        }
                    }
                }
                ForEach(model.stages) { stage in
                    StageOwnerRow(model: model, stage: stage)
                }
            }
        } header: {
            Text("Stages")
        } footer: {
            if model.activeTemplates.isEmpty {
                Text("No request templates yet. A request without a template has no stages.")
            } else if model.selectedTemplate?.requireApproval == true {
                Label("This template requires approvals: each stage moves on once its department and role approve.",
                      systemImage: "checkmark.seal")
            }
        }
    }
}

private struct StageOwnerRow: View {
    @ObservedObject var model: NewChangeRequestViewModel
    let stage: DraftStage

    var body: some View {
        Menu {
            Button("Unassigned") { model.setOwner(nil, for: stage.order) }
            ForEach(model.ownerChoices) { choice in
                Button(choice.name) { model.setOwner(choice.id, for: stage.order) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stage.order). \(stage.description)")
                        .foregroundStyle(.primary)
                    if stage.qaDeploy {
                        Text("Deploy to QA")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(model.ownerName(for: stage) ?? "Unassigned")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("requests.new.stageOwner")
    }
}
