import SwiftUI

/// Figma connector detail screen (Settings → Connectors), mirroring
/// GitHubConnectionView: reached only once connected, shows who is connected
/// and a Disconnect action. Connecting happens from the Connectors row
/// (SettingsView.connectFigma()).
struct FigmaConnectionView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var isDisconnecting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Figma")
                                #if targetEnvironment(macCatalyst)
                                .font(MacSettingsFont.row)
                                #endif
                            if let username = chatManager.figmaUsername, !username.isEmpty {
                                Text(username)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "pencil.and.ruler")
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await disconnect() }
                    } label: {
                        if isDisconnecting {
                            ProgressView()
                        } else {
                            Text("Disconnect")
                                #if targetEnvironment(macCatalyst)
                                .font(MacSettingsFont.row)
                                #endif
                        }
                    }
                    .disabled(isDisconnecting)
                }
            } footer: {
                Text(
                    "The assistant reads your Figma designs — frames, layout, colors, text and " +
                    "components — with your own Figma account. It never changes your files."
                )
                    #if targetEnvironment(macCatalyst)
                    .font(MacSettingsFont.caption)
                    #endif
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Figma")
        .settingsInlineTitle()
    }

    private func disconnect() async {
        guard let api = chatManager.apiService else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }
        do {
            try await api.disconnectFigma()
            chatManager.connectedFigma = false
            chatManager.figmaUsername = nil
            // A disconnected server shouldn't stay toggled on in the current chat.
            if let figma = chatManager.availableMCPServers.first(where: { $0.isFigma }) {
                chatManager.enabledMCPServers.remove(figma.id)
            }
            dismiss()
        } catch {
            errorMessage = "Failed to disconnect. Please try again."
        }
    }
}
