import SwiftUI

// MARK: - Configurations (admin)
// trm's web Configurations (adminConfig/configurations): Systems, Applications,
// Request Types, Priority and Project Type. Adding a system isn't offered here — the web
// encrypts its password with a key that lives only in the web app's build config.

struct ConfigurationsView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        AdminDestination(state: state, navigationControl: navigationControl) { context in
            ConfigurationsScreen(context: context)
        }
    }
}

private struct ConfigurationsScreen: View {
    let context: AdminContext
    @State private var systems: [RQSAPSystem] = []
    @State private var lists: [RQConfigKind: [RQConfigItem]] = [:]
    @State private var error: String?
    @State private var adding: RQConfigKind?

    var body: some View {
        List {
            if let error {
                InlineErrorBanner(message: error) { Task { await load() } }
                    .listRowSeparator(.hidden)
            }
            Section("Systems") {
                if systems.isEmpty { emptyRow }
                ForEach(systems) { system in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(system.sid.isEmpty ? system.name : system.sid).font(RQFont.rowTitle)
                        Text([system.description, system.host].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(RQFont.meta).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach([RQConfigKind.applications, .requestTypes, .priorities, .projectTypes]) { kind in
                Section {
                    let items = lists[kind] ?? []
                    if items.isEmpty { emptyRow }
                    ForEach(items) { Text($0.label) }
                } header: {
                    HStack {
                        Text(kind.title)
                        Spacer()
                        Button("Add") { adding = kind }.font(RQFont.meta)
                    }
                }
            }
        }
        .navigationTitle("Configurations")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $adding) { kind in
            if kind == .applications {
                NewApplicationSheet(context: context, systems: systems) { await load() }
            } else {
                NewConfigItemSheet(context: context, kind: kind) { await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var emptyRow: some View {
        Text("None yet").foregroundStyle(.tertiary)
    }

    private func load() async {
        error = nil
        do {
            async let systems = context.service.systems()
            async let applications = context.service.configList(.applications)
            async let requestTypes = context.service.configList(.requestTypes)
            async let priorities = context.service.configList(.priorities)
            async let projectTypes = context.service.configList(.projectTypes)
            self.systems = try await systems
            lists = try await [
                .applications: applications, .requestTypes: requestTypes,
                .priorities: priorities, .projectTypes: projectTypes
            ]
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct NewConfigItemSheet: View {
    let context: AdminContext
    let kind: RQConfigKind
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red).font(RQFont.meta) }
                TextField("Name", text: $name)
            }
            .navigationTitle("Add \(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AdminFormToolbar(canSave: !name.trimmedValue.isEmpty, isSaving: isSaving,
                                 save: { Task { await save() } }, cancel: { dismiss() })
            }
        }
    }

    private func save() async {
        isSaving = true
        // The web capitalizes the first letter and sends the name as both fields.
        let value = name.trimmedValue.prefix(1).uppercased() + name.trimmedValue.dropFirst()
        do {
            try await context.service.addConfigItem(kind, RQTypePayload(type: value, description: value))
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

private struct NewApplicationSheet: View {
    let context: AdminContext
    let systems: [RQSAPSystem]
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var sap = false
    @State private var git = false
    @State private var transports = false
    @State private var sourceId: String?
    @State private var targetId: String?
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red).font(RQFont.meta) }
                TextField("Description", text: $description)
                Section {
                    Toggle("SAP", isOn: $sap)
                    Toggle("Git", isOn: $git)
                    Toggle("Transports", isOn: $transports)
                }
                Section("Landscape") {
                    systemPicker("Source", selection: $sourceId)
                    systemPicker("Target", selection: $targetId)
                }
            }
            .navigationTitle("Add Application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AdminFormToolbar(canSave: !description.trimmedValue.isEmpty, isSaving: isSaving,
                                 save: { Task { await save() } }, cancel: { dismiss() })
            }
        }
    }

    private func systemPicker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(String?.none)
            ForEach(systems) { Text($0.sid.isEmpty ? $0.name : $0.sid).tag(String?.some($0.id)) }
        }
    }

    private func save() async {
        isSaving = true
        // sourceSID/targetSID carry system ids, as the web sends them.
        let landscape = sourceId.flatMap { source in
            targetId.map { [RQApplicationPayload.Landscape(sourceSID: source, targetSID: $0)] }
        } ?? []
        do {
            try await context.service.addApplication(RQApplicationPayload(
                description: description.trimmedValue, createdBy: context.userId,
                git: git, sap: sap, transports: transports, landscape: landscape
            ))
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
