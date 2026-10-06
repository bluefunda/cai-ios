import SwiftUI

/// GitHub connector detail screen (Settings → Connectors) — reached only once
/// already connected; shows a Disconnect action. Connecting itself happens
/// directly from the Connectors list row (SettingsView.connectGitHub()),
/// skipping any intermediate "Connect GitHub" screen, so this view never
/// shows a Connect button.
struct GitHubConnectionView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var isDisconnecting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Label {
                        Text("GitHub")
                            #if targetEnvironment(macCatalyst)
                            .font(MacSettingsFont.row)
                            #endif
                    } icon: {
                        Image("GitHubMark")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
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
                Text("Connecting lets the GitHub assistant act as you — reading and writing your own repositories, issues and pull requests — instead of a shared account.")
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
        .navigationTitle("GitHub")
        .settingsInlineTitle()
    }

    private func disconnect() async {
        guard let api = chatManager.apiService else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }
        do {
            try await api.disconnectGitHub()
            chatManager.connectedGitHub = false
            chatManager.githubUsername = nil
            // Take effect in the conversation you're already in too — mirrors
            // the insert() done on connect (SettingsView.connectGitHub's
            // caller); a disconnected server shouldn't stay toggled on here.
            if let github = chatManager.availableMCPServers.first(where: { $0.isGitHub }) {
                chatManager.enabledMCPServers.remove(github.id)
            }
            dismiss()
        } catch {
            errorMessage = "Failed to disconnect. Please try again."
        }
    }
}
