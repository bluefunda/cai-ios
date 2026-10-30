import SwiftUI

/// Ported from trm-ios. Status, Priority (severity), Type, Request Owner, and Assignee — trm's own "filter
/// drawer" facets (see ChangeRequestFilter's doc comments), edited as a local draft and only
/// committed to the view model on Apply so Owner/Assignee/Severity/Type batch into a single
/// refetch instead of one per field. Status has no server round-trip — it's applied
/// immediately to the (client-side only) `statusFilter`.
struct ChangeRequestFilterSheet: View {
    @ObservedObject var model: ChangeRequestListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var status: ChangeRequestStatus?
    @State private var draft = ChangeRequestAdvancedFilters()

    private static let severities = ["Low", "Medium", "High"]

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

                Section("Priority") {
                    Picker("Priority", selection: $draft.severity) {
                        Text("Any").tag(String?.none)
                        ForEach(Self.severities, id: \.self) { severity in
                            Text(severity).tag(String?.some(severity))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Type") {
                    TextField("Any", text: $draft.requestType)
                }

                Section("Request owner") {
                    Picker("Request Owner", selection: $draft.ownerIsMe) {
                        Text("Anyone").tag(false)
                        Text("Me").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Assignee") {
                    Picker("Assignee", selection: $draft.assigneeIsMe) {
                        Text("Anyone").tag(false)
                        Text("Me").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        status = nil
                        draft = ChangeRequestAdvancedFilters()
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
        }
        .onAppear {
            status = model.statusFilter
            draft = model.advancedFilters
        }
    }
}
