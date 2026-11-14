import SwiftUI

/// Detail screen (Settings → Agents) for a one-tap connector — Sales Tracker or
/// Apollo.io — reached only once connected; shows a Disconnect action, mirroring
/// GitHubConnectionView. No OAuth/credentials involved: Sales Tracker's
/// connection is this device's (ChatManager.locallyConnectedServerIDs); Apollo.io's
/// is the user's, kept in cai-bff (ChatManager.connectedOneTapNames).
struct SalesTrackerConnectionView: View {
    let server: MCPServer
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var isDisconnecting = false
    @State private var disconnectError: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Label {
                        Text(server.displayName)
                            #if targetEnvironment(macCatalyst)
                            .font(MacSettingsFont.row)
                            #endif
                    } icon: {
                        Image(systemName: server.connectorIconName)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        disconnect()
                    } label: {
                        Text("Disconnect")
                            #if targetEnvironment(macCatalyst)
                            .font(MacSettingsFont.row)
                            #endif
                    }
                }
            } footer: {
                Text(footer)
                    #if targetEnvironment(macCatalyst)
                    .font(MacSettingsFont.caption)
                    #endif
            }
        }
        .disabled(isDisconnecting)
        .navigationTitle(server.displayName)
        .settingsInlineTitle()
        .alert("Disconnect", isPresented: .constant(disconnectError != nil)) {
            Button("OK") { disconnectError = nil }
        } message: {
            Text(disconnectError ?? "")
        }
    }

    private var footer: String {
        if server.isApollo {
            return "Connecting lets the assistant find and enrich prospects in Apollo.io, " +
                "using BlueFunda's shared Apollo account."
        }
        return "Connecting lets the assistant use your Sales Tracker data in conversations."
    }

    private func disconnect() {
        guard server.isApollo else {
            chatManager.locallyConnectedServerIDs.remove(server.id)
            chatManager.enabledMCPServers.remove(server.id)
            dismiss()
            return
        }
        // Apollo.io's connection is kept per user in cai-bff.
        disconnectError = nil
        isDisconnecting = true
        Task {
            defer { isDisconnecting = false }
            do {
                try await chatManager.setOneTapConnector(server, connected: false)
                dismiss()
            } catch {
                disconnectError = "Failed to disconnect \(server.displayName). Please try again."
            }
        }
    }
}
