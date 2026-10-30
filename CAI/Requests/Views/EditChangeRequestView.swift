import SwiftUI

/// Ported from trm-ios. Same field set as create minus Project (not editable) — Description, Type, Priority,
/// Request Owner, Ticket Link. Status and Archive are separate, lightweight actions on the
/// detail screen itself (see ChangeRequestDetailView), matching the real web app's own
/// separation rather than folding everything into one giant form.
struct EditChangeRequestView: View {
    let changeRequest: ChangeRequest
    @ObservedObject var model: ChangeRequestDetailViewModel

    /// Passed in rather than read from the environment — this is a sheet, and the shell
    /// re-injects explicitly into sheets (cai-ios#254).
    let services: RequestsServices?
    @Environment(\.dismiss) private var dismiss

    @State private var requestName: String
    @State private var description: String
    @State private var ticketUrl: String
    @State private var selectedRequestTypeId: String?
    @State private var selectedSeverityId: String?
    @State private var selectedOwnerId: String?

    @State private var requestTypes: [RequestTypeOption] = []
    @State private var severities: [SeverityOption] = []
    @State private var users: [UserOption] = []
    @State private var isLoadingOptions = false
    @State private var isSaving = false
    @State private var loadError: String?

    init(changeRequest: ChangeRequest, model: ChangeRequestDetailViewModel, services: RequestsServices?) {
        self.changeRequest = changeRequest
        self.model = model
        self.services = services
        _requestName = State(initialValue: changeRequest.title)
        _description = State(initialValue: changeRequest.description ?? "")
        _ticketUrl = State(initialValue: "")
        _selectedOwnerId = State(initialValue: changeRequest.requestedByUserId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    TextField("Request name", text: $requestName)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Classification") {
                    Picker("Type", selection: $selectedRequestTypeId) {
                        Text("Unchanged").tag(String?.none)
                        ForEach(requestTypes) { option in
                            Text(option.type).tag(String?.some(option.id))
                        }
                    }
                    Picker("Priority", selection: $selectedSeverityId) {
                        Text("Unchanged").tag(String?.none)
                        ForEach(severities) { option in
                            Text(option.type).tag(String?.some(option.id))
                        }
                    }
                    Picker("Request owner", selection: $selectedOwnerId) {
                        Text("Select…").tag(String?.none)
                        ForEach(users) { user in
                            Text(user.name).tag(String?.some(user.id))
                        }
                    }
                }

                Section("Optional") {
                    TextField("Ticket link", text: $ticketUrl)
                        #if !os(macOS)
                        .keyboardType(.URL)
                        #endif
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                                ticketUrl: ticketUrl.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? nil : ticketUrl.trimmingCharacters(in: .whitespaces)
                            )
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save changes") }
                    }
                    .disabled(isSaving)
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

    private func loadOptions() async {
        guard let services, requestTypes.isEmpty else { return }
        isLoadingOptions = true
        loadError = nil
        do {
            async let rt = services.referenceDataService.requestTypes(forceRefresh: false)
            async let sv = services.referenceDataService.severities(forceRefresh: false)
            async let us = services.referenceDataService.users(forceRefresh: false)
            (requestTypes, severities, users) = try await (rt, sv, us)
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
