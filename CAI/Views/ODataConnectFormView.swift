import SwiftUI

/// The OData connector's "Connect" form (Settings → Agents) — the user's own
/// OData system, separate from ABAPer's SAP system. Submitted to cai-bff's
/// per-user OData store; odata-mcp then reads that system's metadata and data
/// with these credentials. Same layout and push-not-sheet reasoning as
/// ABAPerConnectFormView.
struct ODataConnectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var chatManager: ChatManager

    @State private var host = ""
    @State private var client = ""
    @State private var username = ""
    @State private var password = ""
    @State private var services = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        !host.isBlank && !username.isBlank && !password.isBlank
    }

    /// Service names split on commas, spaces and new lines.
    private var serviceList: [String] {
        services
            .components(separatedBy: CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines))
            .filter { !$0.isEmpty }
    }

    private var form: some View {
        Form {
            Section("OData System") {
                TextField("Host (https://host:port)", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Client (optional)", text: $client)
                    .keyboardType(.numberPad)
            }
            Section("Credentials") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            Section {
                TextField("API_BUSINESS_PARTNER, API_SALES_ORDER_SRV", text: $services, axis: .vertical)
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Services (optional)")
            } footer: {
                Text(
                    "The OData services to use, separated by commas. " +
                    "Leave empty to use the services your system's gateway catalog lists."
                )
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Connect OData")
        .settingsInlineTitle()
    }

    // Bottom-aligned Connect button, same as ABAPerConnectFormView (a toolbar
    // button collides with SettingsView's close "X").
    var body: some View {
        form.safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                if isConnecting {
                    ProgressView()
                } else {
                    Button {
                        Task { await connect() }
                    } label: {
                        Text("Connect")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                isValid ? BFColor.primary : BFColor.secondary,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                    .bfPointerHover()
                }
            }
            .padding()
            .background(.bar)
        }
    }

    private func connect() async {
        guard let api = chatManager.apiService else { return }
        let lowerHost = trimmedHost.lowercased()
        guard lowerHost.hasPrefix("https://") || lowerHost.hasPrefix("http://") else {
            errorMessage = "Enter the host with https://, for example https://sap.example.com:44300."
            return
        }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            try await api.connectOData(ODataConnectRequest(
                host: trimmedHost,
                client: client.trimmingCharacters(in: .whitespaces),
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                services: serviceList
            ))
            await chatManager.refreshODataConnectionStatus()
            // Take effect in the conversation you're already in too, like ABAPer.
            if let odata = chatManager.availableMCPServers.first(where: { $0.isOData }) {
                chatManager.enabledMCPServers.insert(odata.id)
            }
            dismiss()
        } catch {
            errorMessage = "Failed to connect. Check your details and try again."
        }
    }
}
