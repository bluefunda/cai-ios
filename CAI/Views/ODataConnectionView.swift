import SwiftUI

/// The OData connector's detail screen (Settings → Agents) — reached only once
/// connected; shows the connected system and a Disconnect action. Connecting
/// happens in ODataConnectFormView. Mirrors ABAPerConnectionView.
struct ODataConnectionView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var isDisconnecting = false
    @State private var errorMessage: String?

    private var connection: ODataConnectionStatusDTO? { chatManager.odataConnection }

    private var servicesText: String {
        guard let services = connection?.services, !services.isEmpty else { return "From the gateway catalog" }
        return services.joined(separator: ", ")
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label {
                        Text("SAP Analytics")
                            #if targetEnvironment(macCatalyst)
                            .font(MacSettingsFont.row)
                            #endif
                    } icon: {
                        Image(systemName: "chart.bar.doc.horizontal")
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
                detailRow("Host", connection?.host)
                detailRow("Client", connection?.client)
                detailRow("Username", connection?.username)
                detailRow("Services", servicesText)
            } footer: {
                Text(
                    "The assistant queries your own OData system with your own credentials, " +
                    "so it only sees data your user is allowed to see."
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
        .navigationTitle("SAP Analytics")
        .settingsInlineTitle()
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title) {
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            #if targetEnvironment(macCatalyst)
            .font(MacSettingsFont.row)
            #endif
        }
    }

    private func disconnect() async {
        guard let api = chatManager.apiService else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }
        do {
            try await api.disconnectOData()
            chatManager.odataConnection = nil
            // A disconnected server shouldn't stay toggled on in this conversation.
            if let odata = chatManager.availableMCPServers.first(where: { $0.isOData }) {
                chatManager.enabledMCPServers.remove(odata.id)
            }
            dismiss()
        } catch {
            errorMessage = "Failed to disconnect. Please try again."
        }
    }
}
