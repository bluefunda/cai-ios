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

    /// Cards rather than one long list: the workflow switch, the two lists with detail
    /// (systems, applications), then the short request options as chips side by side.
    private var configurationList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BFSpacing._4) {
                if let error {
                    InlineErrorBanner(message: error) { Task { await load() } }
                }
                if let workflowSettings { workflowCard(workflowSettings) }

                ConfigCard(title: "Systems", icon: "server.rack", count: systems.count) {
                    if systems.isEmpty {
                        ConfigEmpty(text: "No SAP systems yet. They're added on the web.")
                    }
                    ForEach(Array(systems.enumerated()), id: \.element.id) { index, system in
                        if index > 0 { Divider() }
                        ConfigRow(title: system.sid.isEmpty ? system.name : system.sid,
                                  detail: [system.description, system.host].filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                }

                let applications = lists[.applications] ?? []
                ConfigCard(title: RQConfigKind.applications.title, icon: "square.stack.3d.up",
                           count: applications.count, onAdd: { adding = .applications }) {
                    if applications.isEmpty { ConfigEmpty(text: "No applications yet.") }
                    ForEach(Array(applications.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        ConfigRow(title: item.label)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: BFSpacing._4, alignment: .top)],
                          alignment: .leading, spacing: BFSpacing._4) {
                    ForEach([RQConfigKind.requestTypes, .priorities, .projectTypes]) { kind in
                        let items = lists[kind] ?? []
                        ConfigCard(title: kind.title, icon: kind.icon, count: items.count,
                                   compactAdd: true, onAdd: { adding = kind }) {
                            if items.isEmpty {
                                ConfigEmpty(text: "None yet.")
                            } else {
                                ChipFlow(spacing: 6) {
                                    ForEach(items) { item in
                                        ConfigChip(text: item.label, flag: kind == .priorities)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, BFSpacing._4)
            .padding(.vertical, BFSpacing._3)
        }
    }

    private func workflowCard(_ settings: RQWorkflowSettings) -> some View {
        ConfigCard(title: "Workflow enforcement", icon: "checkmark.shield") {
            Toggle(isOn: Binding(
                get: { settings.enforceWorkflow },
                set: { enabled in Task { await setEnforcement(enabled) } }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Approvals for every request").font(RQFont.rowTitle)
                    Text(settings.enforceWorkflow
                         ? "Every request needs a template, and each stage moves on only after its approvers approve."
                         : "Approvals apply only to templates with \u{201C}Require approvals\u{201D} on.")
                        .font(RQFont.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // A switch, as the web's; a Mac would otherwise draw a checkbox.
            .toggleStyle(.switch)
            .disabled(isSavingWorkflow)
            .accessibilityIdentifier("admin.config.enforceWorkflow")
            if let workflowError {
                Text(workflowError).font(RQFont.meta).foregroundStyle(.red)
            }
        }
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
                    .formMultilineField()
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

private extension RQConfigKind {
    var icon: String {
        switch self {
        case .requestTypes: return "tag"
        case .priorities: return "flag"
        case .projectTypes: return "folder"
        case .applications: return "square.stack.3d.up"
        }
    }
}

/// A titled card: icon, title and count, an optional Add, then its content.
private struct ConfigCard<Content: View>: View {
    let title: String
    let icon: String
    var count: Int?
    /// A bare + for the narrow cards, where "Add" would wrap.
    var compactAdd = false
    var onAdd: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BFSpacing._3) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BFColor.primary)
                    .frame(width: 26, height: 26)
                    .background(BFColor.primaryTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(RQFont.rowTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let count {
                    Text("\(count)")
                        .font(RQFont.pill)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(BFColor.statusNeutralFill, in: Capsule())
                        .fixedSize()
                }
                Spacer(minLength: 8)
                if let onAdd {
                    Button(action: onAdd) {
                        Label("Add", systemImage: "plus")
                            .font(RQFont.meta.weight(.semibold))
                            .labelStyle(AnyLabelStyle(compactAdd))
                    }
                    .fixedSize()
                    .help("Add")
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .bfPointerHover()
                    .accessibilityLabel("Add to \(title)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(BFSpacing._4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BFColor.surfaceRaised, in: RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous)
                .strokeBorder(BFColor.hairline, lineWidth: 0.5)
        )
    }
}

/// Icon only when compact, otherwise icon and title.
private struct AnyLabelStyle: LabelStyle {
    let iconOnly: Bool
    init(_ iconOnly: Bool) { self.iconOnly = iconOnly }

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: 4) { configuration.icon; configuration.title }
        }
    }
}

private struct ConfigRow: View {
    let title: String
    var detail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(RQFont.body)
            if !detail.isEmpty {
                Text(detail).font(RQFont.meta).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct ConfigEmpty: View {
    let text: String

    var body: some View {
        Text(text).font(RQFont.meta).foregroundStyle(.tertiary)
    }
}

/// One request option; priorities carry their flag colour, as on the requests.
private struct ConfigChip: View {
    let text: String
    var flag = false

    private var flagColor: Color {
        switch text.lowercased() {
        case "high", "critical": return BFColor.happyRed
        case "medium": return BFColor.happyOrange
        default: return Color.secondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if flag {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(flagColor)
            }
            Text(text).font(RQFont.meta)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(BFColor.surfaceSunken, in: Capsule())
    }
}

/// Lays its children out left to right, wrapping onto new lines.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
