import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var iapManager: IAPManager
    @Environment(\.openURL) private var openURL
    @State private var showLogoutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    // Internal infra details (Connection, Build) are only shown to the
    // internal/employee realm; end users on `individual` don't see them.
    private var isTrmRealm: Bool { authManager.realm == "trm" }
    private var isIndividualRealm: Bool { authManager.realm == "individual" }

    private var assistantsSummary: String {
        let enabled = chatManager.availableMCPServers.filter { chatManager.enabledMCPServers.contains($0.id) }
        if enabled.isEmpty { return "None" }
        if enabled.count == 1 { return enabled[0].displayName }
        return "\(enabled.count) Selected"
    }

    var body: some View {
        NavigationStack {
            List {
                // User Section
                Section {
                    if let user = authManager.currentUser {
                        UserInfoRow(user: user)
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
                            Text(assistantsSummary)
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
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Usage & Limits", systemImage: "chart.bar")
                            if let info = chatManager.rateLimit, info.dailyLimit > 0 {
                                CompactUsageBar(label: "Daily", percent: info.dailyPercent)
                                CompactUsageBar(label: "Monthly", percent: info.monthlyPercent)
                            }
                        }
                        .padding(.vertical, chatManager.rateLimit != nil ? 4 : 0)
                    }
                } header: {
                    Text("Usage")
                }
                .task { await chatManager.loadRateLimit() }

                // Subscription — individual users only
                if isIndividualRealm {
                    Section {
                        NavigationLink {
                            SubscriptionView()
                                .environmentObject(iapManager)
                        } label: {
                            HStack {
                                Label(
                                    iapManager.hasActiveSubscription ? "BlueFunda AI Pro" : "Upgrade to Pro",
                                    systemImage: iapManager.hasActiveSubscription ? "checkmark.seal.fill" : "sparkles"
                                )
                                Spacer()
                                Text(iapManager.hasActiveSubscription ? "Active" : "Free")
                                    .foregroundColor(iapManager.hasActiveSubscription ? BFColor.success : .secondary)
                            }
                        }
                    } header: {
                        Text("Subscription")
                    }
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
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundColor(.secondary)
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

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
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

// MARK: - Compact Usage Bar

private struct CompactUsageBar: View {
    let label: String
    let percent: Double

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * min(percent, 1.0))
                }
            }
            .frame(height: 4)
            Text("\(Int(percent * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var barColor: Color {
        if percent >= 1.0 { return .red }
        if percent >= 0.8 { return .orange }
        return BFColor.primary
    }
}

// MARK: - User Info Row

struct UserInfoRow: View {
    let user: User

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
        .padding(.vertical, 4)
    }
}

// MARK: - MCP Server Selection View

struct MCPServerSelectionView: View {
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        List {
            Section {
                ForEach(chatManager.availableMCPServers) { server in
                    Button {
                        toggle(server)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.displayName)
                                    .foregroundColor(.primary)
                                    .fontWeight(isSelected(server) ? .semibold : .regular)
                            }

                            Spacer()

                            if isSelected(server) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(BFColor.primary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Enable one or more assistants to make their tools available in chat.")
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

    private func toggle(_ server: MCPServer) {
        if chatManager.enabledMCPServers.contains(server.id) {
            chatManager.enabledMCPServers.remove(server.id)
        } else {
            chatManager.enabledMCPServers.insert(server.id)
        }
    }

    private func isSelected(_ server: MCPServer) -> Bool {
        chatManager.enabledMCPServers.contains(server.id)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
        .environmentObject(ChatManager(service: NATSChatService()))
        .environmentObject(IAPManager())
}
