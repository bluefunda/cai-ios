import SwiftUI

// MARK: - Configurations (admin)
// trm's web Configurations (adminConfig/configurations): workflow enforcement, Systems,
// Applications, Request Types, Priority and Project Type. Adding a system isn't offered here — the web
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
    /// nil until loaded, and stays nil when the setting can't be read — the section is then
    /// hidden, as on the web (workflowEnforcementSetting.js).
    @State private var workflowSettings: RQWorkflowSettings?
    @State private var hasLoaded = false
    @State private var isSavingWorkflow = false
    @State private var workflowError: String?

    var body: some View {
        VStack(spacing: 0) {
            AdminScreenHeader(title: "Configurations",
                              subtitle: "Workflow, systems, applications and request options")
            // Until the first load answers, one loading state for the page: empty sections
            // (or spinners a Mac list doesn't draw) read as a blank configuration.
            if hasLoaded {
                configurationList
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .adminColumn()
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

    private var configurationList: some View {
        // Headings are rows, not Section headers: a plain list on a Mac draws headers as
        // floating boxes wider than the content, out of line with the title above.
        List {
            if let error {
                InlineErrorBanner(message: error) { Task { await load() } }
                    .listRowSeparator(.hidden)
            }
            if let workflowSettings {
                ConfigHeading(title: "Workflow enforcement")
                Toggle("Approvals for every request", isOn: Binding(
                    get: { workflowSettings.enforceWorkflow },
                    set: { enabled in Task { await setEnforcement(enabled) } }
                ))
                // A switch, as the web's; a Mac would otherwise draw a checkbox.
                .toggleStyle(.switch)
                .disabled(isSavingWorkflow)
                .accessibilityIdentifier("admin.config.enforceWorkflow")
                if let workflowError {
                    Text(workflowError).font(RQFont.meta).foregroundStyle(.red)
                }
                Text("Off: approvals apply only to requests from templates with \u{201C}Require approvals\u{201D} on (Request Templates). On: every request in the organization needs a template, and every stage moves on only after its approvers approve.")
                    .font(RQFont.meta)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            ConfigHeading(title: "Systems")
            if systems.isEmpty { emptyRow }
            ForEach(systems) { system in
                VStack(alignment: .leading, spacing: 2) {
                    Text(system.sid.isEmpty ? system.name : system.sid).font(RQFont.rowTitle)
                    Text([system.description, system.host].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(RQFont.meta).foregroundStyle(.secondary)
                }
            }
            ForEach([RQConfigKind.applications, .requestTypes, .priorities, .projectTypes]) { kind in
                ConfigHeading(title: kind.title) { adding = kind }
                let items = lists[kind] ?? []
                if items.isEmpty { emptyRow }
                ForEach(items) { Text($0.label) }
            }
        }
        // Plain, as the other admin lists: the inset style's extra margin left the sections
        // indented from the screen's title.
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// Shown switched over at once; put back if the save fails.
    private func setEnforcement(_ enabled: Bool) async {
        guard let previous = workflowSettings else { return }
        workflowSettings = RQWorkflowSettings(enforceWorkflow: enabled)
        workflowError = nil
        isSavingWorkflow = true
        defer { isSavingWorkflow = false }
        do {
            workflowSettings = try await context.service.setWorkflowEnforcement(enabled)
        } catch {
            workflowSettings = previous
            workflowError = error.localizedDescription
        }
    }

    private var emptyRow: some View {
        Text("None yet").foregroundStyle(.tertiary)
    }

    private func load() async {
        error = nil
        defer { hasLoaded = true }
        async let settings = try? context.service.workflowSettings()
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
        workflowSettings = await settings
    }
}

private struct NewConfigItemSheet: View {
    let context: AdminContext
    let kind: RQConfigKind
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red).font(RQFont.meta) }
                TextField("Name", text: $name)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(1...4)
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
        // As the web's Configurations form: the name and description, each with its first
        // letter capitalized. A blank description falls back to the name.
        func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
        let value = capitalized(name.trimmedValue)
        let detail = description.trimmedValue.isEmpty ? value : capitalized(description.trimmedValue)
        do {
            try await context.service.addConfigItem(kind, RQTypePayload(type: value, description: detail))
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
        // sourceSID/targetSID carry system ids. The web always sends one landscape entry,
        // with "" for a system that wasn't picked.
        let landscape = [RQApplicationPayload.Landscape(sourceSID: sourceId ?? "", targetSID: targetId ?? "")]
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

/// A section's heading as a list row, with an optional Add on the right.
private struct ConfigHeading: View {
    let title: String
    var onAdd: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(RQFont.label)
                .foregroundStyle(.secondary)
            Spacer()
            if let onAdd {
                Button("Add", action: onAdd)
                    .font(RQFont.meta)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .bfPointerHover()
            }
        }
        .padding(.top, BFSpacing._4)
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(.isHeader)
    }
}
