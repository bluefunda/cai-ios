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

/// Unified dropdown for thinking mode, LLM, and agent selection — mirrors the
/// cai web UnifiedModeSelector / AgentMCPSelector.
@MainActor
struct ModeModelPicker: View {
    @EnvironmentObject var chatManager: ChatManager

    private func modeIsActive(_ mode: ThinkingMode) -> Bool {
        chatManager.enabledMCPServers.isEmpty && !chatManager.userPickedModel
            && chatManager.thinkingMode == mode
    }
    private func modelIsActive(_ model: LLMModel) -> Bool {
        chatManager.enabledMCPServers.isEmpty
            && chatManager.userPickedModel && chatManager.selectedModel.id == model.id
    }
    private func agentIsActive(_ server: MCPServer) -> Bool {
        chatManager.enabledMCPServers.contains(server.id)
    }

    private var enabledAgents: [MCPServer] {
        chatManager.visibleMCPServers.filter { chatManager.enabledMCPServers.contains($0.id) }
    }

    private var label: String {
        if enabledAgents.count == 1 { return enabledAgents[0].displayName }
        if enabledAgents.count > 1 { return "\(enabledAgents.count) Assistants" }
        if chatManager.userPickedModel { return chatManager.selectedModel.name }
        return chatManager.thinkingMode.label
    }
    private var icon: String {
        if !enabledAgents.isEmpty { return "cpu.fill" }
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
                            chatManager.enabledMCPServers = []
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
                            chatManager.enabledMCPServers = []
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

            // Assistants (MCP servers) — multi-select: tapping toggles a
            // server's membership without closing this dropdown's overall
            // selection state (SwiftUI Menu still dismisses per-tap; reopen
            // to toggle another). Full checkbox UX lives in Settings ›
            // Assistants (MCPServerSelectionView).
            if !chatManager.visibleMCPServers.isEmpty {
                Section("Assistants") {
                    // "None" option clears all enabled agents
                    Button {
                        performInstantly {
                            chatManager.enabledMCPServers = []
                        }
                    } label: {
                        if chatManager.enabledMCPServers.isEmpty {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }

                    ForEach(chatManager.visibleMCPServers) { server in
                        Button {
                            performInstantly {
                                if chatManager.enabledMCPServers.contains(server.id) {
                                    chatManager.enabledMCPServers.remove(server.id)
                                } else {
                                    chatManager.enabledMCPServers.insert(server.id)
                                    chatManager.userPickedModel = false
                                }
                            }
                        } label: {
                            if agentIsActive(server) {
                                Label(server.displayName, systemImage: "checkmark")
                            } else {
                                Text(server.displayName)
                            }
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
