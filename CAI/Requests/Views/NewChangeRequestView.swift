import SwiftUI

/// Ported from trm-ios. Fields match trm's own web create form's *required* set exactly (see the trm-ios plan's
/// field-scope table) — Platform/SAP/git/template fields are optional there too and are
/// deliberately not exposed here.
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
