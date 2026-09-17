import SwiftUI

/// ABAPer connector detail screen (Settings → Agents) — reached only once
/// already connected; shows the connected SAP host and a Disconnect action.
/// Connecting itself happens via ABAPerConnectFormView (host/client/username/
/// password), presented as a sheet from the Agents list row — mirrors
/// GitHubConnectionView/SalesTrackerConnectionView's split between "list row
/// starts the connect flow" and "this screen only ever disconnects."
struct ABAPerConnectionView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var isDisconnecting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Label {
                        Text("ABAPer")
                            #if targetEnvironment(macCatalyst)
                            .font(MacSettingsFont.row)
                            #endif
                    } icon: {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 16))
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
                if let host = chatManager.sapHost, !host.isEmpty {
                    LabeledContent("Host") {
                        Text(host)
                            .foregroundStyle(.secondary)
                    }
                    #if targetEnvironment(macCatalyst)
                    .font(MacSettingsFont.row)
                    #endif
                }
            } footer: {
                Text("Connecting lets the ABAPer assistant act against your own SAP system — reading and writing your own ABAP objects — instead of a shared backend.")
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
        .navigationTitle("ABAPer")
        .settingsInlineTitle()
    }

    private func disconnect() async {
        guard let api = chatManager.apiService else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }
        do {
            try await api.disconnectSAP()
            chatManager.connectedSAP = false
            chatManager.sapHost = nil
            // Take effect in the conversation you're already in too — mirrors
            // GitHubConnectionView's disconnect: a disconnected server
            // shouldn't stay toggled on here.
            if let abaper = chatManager.availableMCPServers.first(where: { $0.isABAPer }) {
                chatManager.enabledMCPServers.remove(abaper.id)
            }
            dismiss()
        } catch {
            errorMessage = "Failed to disconnect. Please try again."
        }
    }
}
