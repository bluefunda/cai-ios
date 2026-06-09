import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager
    @State private var showLogoutConfirmation = false

    // Internal infra details (Connection, Build) are only shown to the
    // internal/employee realm; end users on `individual` don't see them.
    private var isTrmRealm: Bool { authManager.realm == "trm" }

    var body: some View {
        NavigationStack {
            List {
                // User Section
                Section {
                    if let user = authManager.currentUser {
                        UserInfoRow(user: user, realm: authManager.realm)
                    }
                } header: {
                    Text("Account")
                }

                // Model Settings
                Section {
                    NavigationLink {
                        ModelSelectionView()
                    } label: {
                        HStack {
                            Label("Default Model", systemImage: "brain")
                            Spacer()
                            Text(chatManager.selectedModel.name)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    NavigationLink {
                        MCPServerSelectionView()
                    } label: {
                        HStack {
                            Label("Assistant", systemImage: "sparkles")
                            Spacer()
                            Text(chatManager.selectedMCPServer?.name ?? "None")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("AI Settings")
                }

                // Usage
                Section {
                    NavigationLink {
                        RateLimitView()
                    } label: {
                        HStack {
                            Label("Usage & Limits", systemImage: "chart.bar")
                            if let rl = chatManager.rateLimit {
                                Spacer()
                                Text(rl.planName.uppercased())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Subscription")
                }

                // Connection Status — internal infra detail, trm realm only
                if isTrmRealm {
                    Section {
                        HStack {
                            Label("Status", systemImage: statusIcon)
                            Spacer()
                            Text(chatManager.connectionStatus.description)
                                .foregroundColor(statusColor)
                        }

                        HStack {
                            Label("Service", systemImage: "network")
                            Spacer()
                            Text("BFF (api.bluefunda.com/ai)")
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Connection")
                    } footer: {
                        Text("Using cai-gw/cai-bff HTTP SSE endpoints.")
                    }
                }

                // App Info
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    // Build detail — trm realm only
                    if isTrmRealm {
                        HStack {
                            Label("Build", systemImage: "hammer")
                            Spacer()
                            Text("MVP")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }

                // Logout
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign Out", isPresented: $showLogoutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await chatManager.disconnect()
                        await authManager.logout()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    private var statusIcon: String {
        switch chatManager.connectionStatus {
        case .connected:
            return "wifi"
        case .connecting, .reconnecting:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "wifi.exclamationmark"
        case .disconnected:
            return "wifi.slash"
        }
    }

    private var statusColor: Color {
        switch chatManager.connectionStatus {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .gray
        }
    }
}

// MARK: - User Info Row

struct UserInfoRow: View {
    let user: User
    let realm: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 50, height: 50)
                .overlay {
                    Text(user.name.prefix(1).uppercased())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.headline)

                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Text(realm.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)

                    if user.isAdmin {
                        Text("ADMIN")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Model Selection View

struct ModelSelectionView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(chatManager.availableModels) { model in
                Button {
                    chatManager.selectedModel = model
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name)
                                .foregroundColor(.primary)

                            Text(model.provider)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if model.id == chatManager.selectedModel.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Select Model")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - MCP Server Selection View

struct MCPServerSelectionView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss

    private let noneServer = MCPServer(id: "none", name: "None", url: "", description: "No assistant")

    private var displayServers: [MCPServer] {
        [noneServer] + chatManager.availableMCPServers
    }

    var body: some View {
        List {
            ForEach(displayServers) { server in
                Button {
                    chatManager.selectedMCPServer = server.id == "none" ? nil : server
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name)
                                .foregroundColor(.primary)
                                .fontWeight(isSelected(server) ? .semibold : .regular)

                            if let desc = server.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if server.id != "none", !server.url.isEmpty {
                                Text(server.url)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if isSelected(server) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Assistants")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if chatManager.availableMCPServers.isEmpty {
                ContentUnavailableView(
                    "No Assistants",
                    systemImage: "sparkles",
                    description: Text("No assistants are configured for your account.")
                )
            }
        }
    }

    private func isSelected(_ server: MCPServer) -> Bool {
        if server.id == "none" { return chatManager.selectedMCPServer == nil }
        return chatManager.selectedMCPServer?.id == server.id
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
        .environmentObject(ChatManager(service: NATSChatService()))
}
