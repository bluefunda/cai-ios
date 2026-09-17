import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Executes an action with CoreAnimation, UIKit, and SwiftUI animations all completely disabled,
/// preventing any intermediate layout interpolation, sliding, or text clipping when
/// switching modes/models in a menu.
@MainActor
private func performInstantly(_ action: () -> Void) {
    #if canImport(UIKit)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    UIView.performWithoutAnimation {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            action()
        }
    }
    CATransaction.commit()
    #else
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        action()
    }
    #endif
}

// MARK: - Mode + Model Picker

/// Unified dropdown for thinking mode and LLM selection — mirrors the cai
/// web UnifiedModeSelector. Every connected MCP server's tools are always
/// available automatically (see ChatManager.allVisibleMCPServerIDs), so
/// there is no separate agent-selection control to coordinate with here
/// anymore — mode/model choice is independent of which tools are available.
@MainActor
struct ModeModelPicker: View {
    @EnvironmentObject var chatManager: ChatManager

    private func modeIsActive(_ mode: ThinkingMode) -> Bool {
        !chatManager.userPickedModel && chatManager.thinkingMode == mode
    }
    private func modelIsActive(_ model: LLMModel) -> Bool {
        chatManager.userPickedModel && chatManager.selectedModel.id == model.id
    }
    private var label: String {
        if chatManager.userPickedModel { return chatManager.selectedModel.name }
        return chatManager.thinkingMode.label
    }
    private var icon: String {
        if chatManager.userPickedModel { return "cpu" }
        return chatManager.thinkingMode.icon
    }

    var body: some View {
        // Pure SwiftUI chip as the root view so its frame updates atomically
        // without UIKit UIButton layout lag, intermediate frame clipping, or
        // alignment sliding. The native Menu lives in an invisible overlay
        // to handle user taps and menu presentation.
        chipView
            .accessibilityHidden(true)
            .overlay {
                menuOverlay
            }
            .fixedSize()
            .transaction {
                $0.animation = nil
                $0.disablesAnimations = true
            }
            .bfPointerHover()
    }

    private var chipView: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(label)
                .font(BFFont.bodySmall).fontWeight(.medium)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(.identity)
            Image(systemName: "chevron.down").font(.caption)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(BFColor.primaryTint)
        .cornerRadius(10)
        .foregroundStyle(BFColor.primary)
    }

    private var menuOverlay: some View {
        Menu {
            // Thinking modes
            Section {
                ForEach(ThinkingMode.allCases) { mode in
                    Button {
                        performInstantly {
                            chatManager.selectThinkingMode(mode)
                        }
                    } label: {
                        if modeIsActive(mode) {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Label(mode.label, systemImage: mode.icon)
                        }
                    }
                }
            }

            // LLMs
            Section("LLM") {
                ForEach(chatManager.availableModels) { model in
                    Button {
                        performInstantly {
                            chatManager.selectModel(model)
                        }
                    } label: {
                        if modelIsActive(model) {
                            Label(model.name, systemImage: "checkmark")
                        } else {
                            Text(model.name)
                        }
                    }
                }
            }

        } label: {
            Rectangle()
                .fill(Color.primary.opacity(0.0001))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mode and model: \(label)")
        .accessibilityHint("Select thinking mode, model, or assistant")
    }
}

// MARK: - Attach + Connectors Popup (composer "+" button)

/// Sheet presented by the composer's "+" button — the Attach tab keeps the
/// exact options the old plain `Menu` offered; the Connectors tab lets the
/// user toggle which of their connected MCP servers are enabled for THIS
/// conversation (mirrors Claude's own "+" popup). Connector state lives on
/// `ChatManager.enabledMCPServers` already — this sheet only ever toggles it,
/// defaulting per-conversation to every connected connector (see
/// `ChatManager.defaultConnectedMCPServerIDs`).
@MainActor
struct ComposerAttachSheet: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss

    let onPickCamera: (() -> Void)?
    let onPickPhoto: (() -> Void)?
    let onPickFile: (() -> Void)?
    let onPickDumpScreenshot: (() -> Void)?
    /// Called instead of presenting Settings as a *nested* sheet from within
    /// this one — sheet-on-sheet was unreliable (reported: tapping through
    /// it left the whole app stuck in a loading state). The caller dismisses
    /// this sheet and presents Settings itself, as a sibling, once this one
    /// has actually finished dismissing.
    let onManageAgents: () -> Void

    private enum Tab: String, CaseIterable, Identifiable {
        case attach = "Attach"
        case connectors = "Agents"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .attach

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                switch tab {
                case .attach: attachList
                case .connectors: connectorsList
                }
            }
            // One uniform background for the whole sheet (picker area +
            // list), instead of two mismatched backgrounds meeting at a
            // visible seam.
            .background(Color(uiColor: .systemBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        #if targetEnvironment(macCatalyst)
                        .font(MacSettingsFont.row)
                        #endif
                        .bfPointerHover()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var attachList: some View {
        List {
            if let pickCamera = onPickCamera {
                attachRow("Take Photo", icon: "camera", action: pickCamera)
            }
            if let pickPhoto = onPickPhoto {
                attachRow("Photo Library", icon: "photo", action: pickPhoto)
            }
            if let pickFile = onPickFile {
                attachRow("Browse Files", icon: "folder", action: pickFile)
            }
            if let pickDump = onPickDumpScreenshot {
                attachRow("Decode ST22 Dump", icon: "exclamationmark.triangle", action: pickDump)
            }
        }
    }

    private func attachRow(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            Label(label, systemImage: icon)
                #if targetEnvironment(macCatalyst)
                .font(MacSettingsFont.row)
                #endif
        }
        .bfPointerHover()
    }

    @ViewBuilder
    private var connectorsList: some View {
        List {
            Section {
                if chatManager.connectedMCPServers.isEmpty {
                    Text("No connectors are connected yet.")
                        #if targetEnvironment(macCatalyst)
                        .font(MacSettingsFont.secondary)
                        #endif
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chatManager.connectedMCPServers) { server in
                        Toggle(isOn: enabledBinding(for: server)) {
                            HStack(spacing: 14) {
                                if server.isGitHub {
                                    Image("GitHubMark")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                        // .foregroundStyle(.primary) alone
                                        // doesn't stick on Mac Catalyst inside
                                        // these List rows — .foregroundColor
                                        // overrides the row's own tint.
                                        .foregroundColor(.primary)
                                        .frame(width: 22)
                                } else {
                                    Image(systemName: server.connectorIconName)
                                        .font(.system(size: 16))
                                        .foregroundColor(.primary)
                                        .frame(width: 22)
                                }
                                Text(server.displayName)
                                    #if targetEnvironment(macCatalyst)
                                    .font(MacSettingsFont.row)
                                    #else
                                    .font(BFFont.body)
                                    #endif
                            }
                            .padding(.vertical, 6)
                        }
                        .toggleStyle(.switch)
                        .bfPointerHover()
                    }
                }
            } footer: {
                Text("Toggles which connected tools the assistant can use in this conversation.")
                    #if targetEnvironment(macCatalyst)
                    .font(MacSettingsFont.secondary)
                    #endif
            }

            Section {
                Button {
                    dismiss()
                    onManageAgents()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .frame(width: 22)
                        Text("Manage Agents")
                            #if targetEnvironment(macCatalyst)
                            .font(MacSettingsFont.row)
                            #else
                            .font(BFFont.body)
                            #endif
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .bfPointerHover()
            }
        }
    }

    private func enabledBinding(for server: MCPServer) -> Binding<Bool> {
        Binding(
            get: { chatManager.enabledMCPServers.contains(server.id) },
            set: { isOn in
                if isOn {
                    chatManager.enabledMCPServers.insert(server.id)
                } else {
                    chatManager.enabledMCPServers.remove(server.id)
                }
            }
        )
    }
}

// MARK: - Persona Composer Controls

/// Compact toggle + dropdown living inside the composer surface itself
/// (bluefunda/cai-ios#217), replacing the old above-input `PersonaChip`.
/// Off = General (no persona); on = the dropdown appears, showing the
/// chat-local selection (Settings default until the user overrides it for
/// this conversation). Secondary chrome — kept small so the text field stays
/// the dominant element in `ChatInputView.composerRow`.
@MainActor
struct PersonaComposerControl: View {
    @Binding var isOn: Bool
    let currentPersona: Persona
    var options: [Persona] = Persona.fallbackCatalog
    let onSelect: (Persona) -> Void

    private var dropdownOptions: [Persona] { options }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isOn ? "person.text.rectangle.fill" : "person.text.rectangle")
                        .font(.system(size: 14))
                    Text("Persona")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .foregroundStyle(isOn ? BFColor.primary : .secondary)
                .padding(.horizontal, 6)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("SAP Persona")
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityHint("Toggles a SAP-specific persona for this chat")
            .bfPointerHover()

            if isOn {
                personaChipView
                    .accessibilityHidden(true)
                    .overlay {
                        personaMenuOverlay
                    }
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                    .bfPointerHover()
            }
        }
    }

    private var personaChipView: some View {
        HStack(spacing: 3) {
            Text(currentPersona.shortLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: 70, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(BFColor.primaryTint, in: Capsule())
        .foregroundStyle(BFColor.primary)
    }

    private var personaMenuOverlay: some View {
        Menu {
            ForEach(dropdownOptions) { option in
                Button {
                    performInstantly {
                        onSelect(option)
                    }
                } label: {
                    if option == currentPersona {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Rectangle()
                .fill(Color.primary.opacity(0.0001))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("SAP Persona: \(currentPersona.label)")
        .accessibilityHint("Choose a different SAP persona for this chat")
    }
}
