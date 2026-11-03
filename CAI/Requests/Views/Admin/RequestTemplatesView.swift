import SwiftUI

// MARK: - Request Templates (admin)
// trm's web Request Templates (adminConfig/requestTemplates): each template's workflow
// stages — name, department, role, and the one stage that deploys to QA.

struct RequestTemplatesView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        AdminDestination(state: state, navigationControl: navigationControl) { context in
            RequestTemplatesScreen(context: context)
        }
    }
}

private struct RequestTemplatesScreen: View {
    let context: AdminContext
    @StateObject private var loader = AdminLoader<RQRequestTemplate>()
    @State private var searchText = ""
    @State private var editing: TemplateTarget?

    /// The web filters templates in the browser too — the API takes no search param.
    private var filtered: [RQRequestTemplate] {
        let query = searchText.trimmedValue.lowercased()
        guard !query.isEmpty else { return loader.items }
        return loader.items.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            AdminScreenHeader(
                title: "Request Templates",
                subtitle: adminCount(loader.items.count, "template", loaded: loader.hasLoaded),
                actionTitle: "New template", actionIdentifier: "admin.templates.new",
                action: { editing = .new }, search: $searchText, searchPrompt: "Search templates"
            )
            AdminListContent(loader: loader, subject: "templates", emptyTitle: "No templates",
                             emptyIcon: "doc.on.doc", reload: reload) {
                ForEach(filtered) { template in
                    Button { editing = .edit(template.id) } label: { TemplateRow(template: template) }
                        .buttonStyle(.plain)
                }
            }
        }
        .adminColumn()
        .navigationTitle("Request Templates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            TemplateFormSheet(context: context, target: target, onSaved: reload)
        }
        .task { if !loader.hasLoaded { await reload() } }
        .refreshable { await reload() }
    }

    private func reload() async {
        await loader.load { try await context.service.templates() }
    }
}

private struct TemplateRow: View {
    let template: RQRequestTemplate

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name).font(RQFont.rowTitle).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text("\(template.workflow.count) steps").font(RQFont.meta).foregroundStyle(.secondary)
                    if template.requireApproval {
                        Label("Approvals", systemImage: "checkmark.seal")
                            .font(RQFont.meta)
                            .foregroundStyle(BFColor.statusBlueText)
                    }
                }
            }
            Spacer()
            Text(template.isActive ? "Active" : "Inactive")
                .font(RQFont.meta)
                .foregroundStyle(template.isActive ? Color.green : Color.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

enum TemplateTarget: Identifiable {
    case new
    case edit(String)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let id): return id
        }
    }
}

private struct TemplateFormSheet: View {
    let context: AdminContext
    let target: TemplateTarget
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: RQTemplateKind = .standard
    @State private var requireApproval = false
    @State private var stages: [RQTemplateStage] = [RQTemplateStage()]
    @State private var departments: [RQNamedOption] = []
    @State private var roles: [RQNamedOption] = []
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool { !name.trimmedValue.isEmpty && stages.contains(where: \.isComplete) }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Text(error).foregroundStyle(.red).font(RQFont.meta)
                }
                Section {
                    TextField("Template name", text: $name)
                    Picker("Kind", selection: $kind) {
                        ForEach(RQTemplateKind.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("admin.template.kind")
                    Toggle("Require approvals", isOn: $requireApproval)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("admin.template.requireApproval")
                } header: {
                    Text("Template")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(requireApproval
                             ? "Requests from this template move on only when each stage's department and role approve it."
                             : "Requests from this template move freely; the stages are a guide.")
                        // As on the web: gate steps exist only on tech templates.
                        if kind == .tech {
                            Text("Tech templates can have GitHub gate steps, satisfied by the request's linked pull requests.")
                        }
                    }
                }
                ForEach($stages) { $stage in
                    Section("Stage \((stages.firstIndex(of: stage) ?? 0) + 1)") {
                        TextField("Stage name", text: $stage.description)
                        Picker("Department", selection: $stage.department) {
                            Text("Select").tag("")
                            ForEach(departments) { Text($0.name).tag($0.name) }
                        }
                        Picker("Role", selection: $stage.role) {
                            Text("Select").tag("")
                            ForEach(roles) { Text($0.name).tag($0.name) }
                        }
                        Toggle("QA deploy", isOn: qaBinding(for: stage.id))
                        if kind == .tech {
                            Picker("Step type", selection: $stage.type) {
                                ForEach(RQStepType.allCases) { Text($0.title).tag($0) }
                            }
                            .accessibilityIdentifier("admin.template.stepType")
                            if stage.type == .githubGate {
                                Toggle("Pull request merged", isOn: $stage.gate.requireMerged)
                                Toggle("Approved at the latest commit", isOn: $stage.gate.requireApprovedAtHead)
                                Toggle("Checks passing", isOn: $stage.gate.requireChecksGreen)
                                Stepper("Approvals needed: \(stage.gate.minApprovals)",
                                        value: $stage.gate.minApprovals, in: 0...10)
                            }
                        }
                        if stages.count > 1 {
                            Button("Remove Stage", role: .destructive) {
                                stages.removeAll { $0.id == stage.id }
                            }
                        }
                    }
                }
                Section {
                    Button { stages.append(RQTemplateStage()) } label: { Label("Add Stage", systemImage: "plus") }
                }
            }
            .navigationTitle(isNew ? "New Template" : "Template Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AdminFormToolbar(canSave: canSave, isSaving: isSaving,
                                 save: { Task { await save() } }, cancel: { dismiss() })
            }
            .task { await load() }
        }
    }

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    /// Only one stage can deploy to QA, as on the web.
    private func qaBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { stages.first { $0.id == id }?.qaDeploy ?? false },
            set: { isOn in
                for index in stages.indices { stages[index].qaDeploy = isOn && stages[index].id == id }
            }
        )
    }

    private func load() async {
        do {
            async let departments = context.service.departments()
            async let roles = context.service.roles()
            (self.departments, self.roles) = try await (departments, roles)
            if case .edit(let id) = target, let template = try await context.service.template(id: id) {
                name = template.name
                kind = template.kind
                requireApproval = template.requireApproval
                stages = template.workflow.isEmpty ? [RQTemplateStage()] : template.workflow
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        let payload = RQTemplatePayload(name: name.trimmedValue, kind: kind, requireApproval: requireApproval,
                                        stages: stages, createdBy: context.userId)
        do {
            switch target {
            case .new: try await context.service.createTemplate(payload)
            case .edit(let id): try await context.service.updateTemplate(id: id, payload)
            }
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
