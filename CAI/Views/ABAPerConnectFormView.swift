import SwiftUI

/// The ABAPer "Connect" form (Settings → Agents) — collects the same 4
/// fields Code mode's AddSystemView already does (host/client/username/
/// password), but submits them to cai-bff's per-user SAP credential store
/// (bluefunda/cai-bff#160) instead of only saving locally, so the ABAPer
/// chat tool can actually use them (bluefunda/abaper-mcp#79) — not just Code
/// mode's ADT browser.
///
/// Pushed onto Settings' own NavigationStack (see the NavigationLink at its
/// call site) rather than presented as a sheet — Settings itself is already
/// a sheet, and sheet-on-sheet has caused a full app hang here before (see
/// ChatInputView's "Manage Agents" fix).
struct ABAPerConnectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var chatManager: ChatManager

    @State private var host = ""
    @State private var client = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !host.isBlank && !client.isBlank && !username.isBlank && !password.isBlank
    }

    var body: some View {
        Form {
            Section("SAP System") {
                TextField("Host (https://host:port)", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Client", text: $client)
                    .keyboardType(.numberPad)
            }
            Section("Credentials") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Connect ABAPer")
        .settingsInlineTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isConnecting {
                    ProgressView()
                } else {
                    Button("Connect") { Task { await connect() } }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func connect() async {
        guard let api = chatManager.apiService else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            try await api.connectSAP(
                host: host.trimmingCharacters(in: .whitespaces),
                client: client.trimmingCharacters(in: .whitespaces),
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
            await chatManager.refreshSAPConnectionStatus()
            // Take effect in the conversation you're already in too — mirrors
            // connectGitHub's caller in SettingsView: the lazy seed-on-load in
            // loadMCPServers() never retroactively enables an already-open
            // conversation's existing per-chat selection.
            if let abaper = chatManager.availableMCPServers.first(where: { $0.isABAPer }) {
                chatManager.enabledMCPServers.insert(abaper.id)
            }
            dismiss()
        } catch {
            errorMessage = "Failed to connect. Check your details and try again."
        }
    }
}
