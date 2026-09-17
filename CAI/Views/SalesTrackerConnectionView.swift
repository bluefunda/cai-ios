import SwiftUI

/// Sales Tracker connector detail screen (Settings → Agents) — reached only
/// once connected; shows a Disconnect action, mirroring GitHubConnectionView.
/// No OAuth/credentials involved (see ChatManager.locallyConnectedServerIDs)
/// — Disconnect just removes this server's id, no backend call.
struct SalesTrackerConnectionView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack {
                    Label {
                        Text("Sales Tracker")
                            #if targetEnvironment(macCatalyst)
                            .font(MacSettingsFont.row)
                            #endif
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
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
                Text("Connecting lets the assistant use your Sales Tracker data in conversations.")
                    #if targetEnvironment(macCatalyst)
                    .font(MacSettingsFont.caption)
                    #endif
            }
        }
        .navigationTitle("Sales Tracker")
        .settingsInlineTitle()
    }

    private func disconnect() {
        if let server = chatManager.availableMCPServers.first(where: { $0.isSalesTracker }) {
            chatManager.locallyConnectedServerIDs.remove(server.id)
            chatManager.enabledMCPServers.remove(server.id)
        }
        dismiss()
    }
}
