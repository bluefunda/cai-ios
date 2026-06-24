import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.openURL) private var openURL
    @State private var showLogoutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

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

                // Legal
                Section {
                    Button {
                        openURL(privacyPolicyURL)
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .foregroundColor(.primary)
                    }

                    Button {
                        openURL(termsOfServiceURL)
                    } label: {
                        Label("Terms of Service", systemImage: "doc.text")
                            .foregroundColor(.primary)
                    }
                } header: {
                    Text("Legal")
                }

                // Report Suspicious Content
                Section {
                    Button {
                        openURL(reportContentURL)
                    } label: {
                        Label("Report Suspicious Content", systemImage: "flag")
                            .foregroundColor(.primary)
                    }
                } footer: {
                    Text("Report content within the app that you believe is suspicious, abusive, or violates our policies. This opens an email to our support team.")
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

                // Delete Account
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView()
                            } else {
                                Text("Delete Account")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("Permanently deletes your account and all associated data. This can't be undone.")
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
            .confirmationDialog("Delete Account", isPresented: $showDeleteConfirmation) {
                Button("Delete Account", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and data. This action cannot be undone.")
            }
            .alert("Delete Failed", isPresented: .constant(deleteError != nil)) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private let privacyPolicyURL = URL(string: "https://bluefunda.com/privacy/")!
    private let termsOfServiceURL = URL(string: "https://bluefunda.com/terms/")!

    private var reportContentURL: URL {
        let subject = "Report Suspicious Content - CAI iOS App"
        var body = "Please describe the content you'd like to report and where you encountered it (e.g. chat message, conversation title):\n\n\n"
        if let email = authManager.currentUser?.email {
            body += "—\nAccount: \(email)"
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?")

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? body

        return URL(string: "mailto:info@bluefunda.com?subject=\(encodedSubject)&body=\(encodedBody)")
            ?? URL(string: "mailto:info@bluefunda.com")!
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            do {
                await chatManager.disconnect()
                try await authManager.deleteAccount()
                // On success, isAuthenticated flips to false → routes to LoginView.
            } catch {
                deleteError = error.localizedDescription
            }
            isDeleting = false
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
            return BFColor.success
        case .connecting, .reconnecting:
            return BFColor.warning
        case .error:
            return BFColor.error
        case .disconnected:
            return BFColor.neutral400
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
                .fill(BFColor.primary.gradient)
                .frame(width: 50, height: 50)
                .overlay {
                    Text(user.name.prefix(1).uppercased())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(BFColor.textInverse)
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
                        .background(BFColor.primaryTint)
                        .cornerRadius(BFRadius.sm)

                    if user.isAdmin {
                        Text("ADMIN")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BFColor.warningBg)
                            .foregroundColor(BFColor.warning)
                            .cornerRadius(BFRadius.sm)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
                                .foregroundColor(BFColor.primary)
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
