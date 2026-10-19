import SwiftUI

/// Ported from trm-ios. Type and Owner — the two facets available client-side (see `ProjectFilters`'s doc
/// comment on why there's no server round-trip here). Options are the distinct values
/// already present in the loaded project list, not a separate reference-data fetch.
struct ProjectFilterSheet: View {
    @ObservedObject var model: ProjectsListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ProjectFilters()

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $draft.projectType) {
                        Text("Any").tag(String?.none)
                        ForEach(model.availableProjectTypes, id: \.self) { type in
                            Text(type).tag(String?.some(type))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Owner") {
                    Picker("Owner", selection: $draft.owner) {
                        Text("Any").tag(String?.none)
                        ForEach(model.availableOwners, id: \.self) { owner in
                            Text(owner).tag(String?.some(owner))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { draft = ProjectFilters() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        model.filters = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { draft = model.filters }
    }
}
