import SwiftUI
import AuthenticationServices

// MARK: - Connectors (Agents)
// Split from SettingsView's main body to stay under SwiftLint's file_length/type_body_length
// limits (bluefunda/cai-ios#261 precedent — see ChatManager+Background.swift, ChatView+Scroll.swift).
extension SettingsView {
    /// Every MCP server the backend returns — unfiltered (`availableMCPServers`,
    /// not `visibleMCPServers`, which hides ABAPer/SAP specifically for the
    /// in-chat agent picker). This screen is meant to show every connector
    /// that exists, including the ones without a working Connect flow yet.
    @ViewBuilder
    var connectorsDetail: some View {
        List {
            Section {
                ForEach(chatManager.availableMCPServers) { server in
                    if server.isGitHub {
                        if chatManager.connectedGitHub {
                            // Already connected — push straight to the
                            // Disconnect detail screen, no re-auth prompt.
                            NavigationLink {
                                GitHubConnectionView()
                            } label: {
                                connectorRow(server, connected: true)
                            }
                            .bfPointerHover()
                        } else {
                            // Not connected — go straight to GitHub's OAuth
                            // consent screen. No intermediate "Connect GitHub"
                            // screen in between.
                            Button {
                                Task {
                                    await connectGitHub()
                                    // Connecting should take effect in the
                                    // conversation you're already in, not just
                                    // ones started after this — the lazy
                                    // seed-on-load in loadMCPServers() never
                                    // overwrites an existing per-chat record.
                                    if chatManager.connectedGitHub {
                                        chatManager.enabledMCPServers.insert(server.id)
                                    }
                                }
                            } label: {
                                connectorRow(server, connected: false, isBusy: isConnectingGitHub)
                            }
                            .buttonStyle(.plain)
                            .disabled(isConnectingGitHub)
                            .bfPointerHover()
                        }
                    } else if server.isSalesTracker {
                        if chatManager.locallyConnectedServerIDs.contains(server.id) {
                            // Already connected — push straight to the
                            // Disconnect detail screen, mirroring GitHub.
                            NavigationLink {
                                SalesTrackerConnectionView()
                            } label: {
                                connectorRow(server, connected: true)
                            }
                            .bfPointerHover()
                        } else {
                            // No OAuth or credentials — tapping just adds
                            // this server's id to locallyConnectedServerIDs
                            // (no backend call).
                            Button {
                                chatManager.locallyConnectedServerIDs.insert(server.id)
                                chatManager.enabledMCPServers.insert(server.id)
                            } label: {
                                connectorRow(server, connected: false)
                            }
                            .buttonStyle(.plain)
                            .bfPointerHover()
                        }
                    } else if server.isABAPer {
                        if chatManager.connectedSAP {
                            // Already connected — push straight to the
                            // Disconnect detail screen, mirroring GitHub.
                            NavigationLink {
                                ABAPerConnectionView()
                            } label: {
                                connectorRow(server, connected: true)
                            }
                            .bfPointerHover()
                        } else {
                            // Needs host/client/username/password — push to
                            // the connect form instead of connecting directly
                            // (unlike GitHub's OAuth redirect or Sales
                            // Tracker's no-credential flip). A push, not a
                            // sheet: this List already lives inside a sheet
                            // (Settings itself) — sheet-on-sheet has caused a
                            // full app hang here before (see ChatInputView's
                            // "Manage Agents" fix), so every connect/detail
                            // screen off Agents pushes onto Settings' own
                            // NavigationStack instead.
                            // ZStack + a hidden NavigationLink: a List's NavigationLink
                            // auto-draws its own trailing chevron, which made this row look
                            // different from GitHub/Sales Tracker's plain-Button "Connect"
                            // rows (no chevron) right next to it. This keeps the push
                            // behavior without that visual inconsistency.
                            ZStack {
                                NavigationLink(destination: ABAPerConnectFormView()) { EmptyView() }
                                    .opacity(0)
                                connectorRow(server, connected: false)
                            }
                            .bfPointerHover()
                        }
                    } else {
                        // No connect flow yet for this one (e.g. SAP
                        // Analytics) — shown so every connector is visible,
                        // but not tappable until its own flow exists.
                        connectorRow(server, connected: false)
                    }
                }
            } footer: {
                Text(
                    "Connect your own accounts so the assistant acts as you — reading and " +
                    "writing your own data — instead of a shared account."
                )
                #if targetEnvironment(macCatalyst)
                .font(MacSettingsFont.secondary)
                #endif
            }
        }
        .navigationTitle("Agents")
        .settingsInlineTitle()
        .overlay {
            if chatManager.availableMCPServers.isEmpty {
                ContentUnavailableView(
                    "No Agents",
                    systemImage: "brain.head.profile",
                    description: Text("No agents are configured for your account.")
                )
            }
        }
        .alert("GitHub", isPresented: .constant(githubConnectError != nil)) {
            Button("OK") { githubConnectError = nil }
        } message: {
            Text(githubConnectError ?? "")
        }
    }

    @ViewBuilder
    fileprivate func connectorRow(_ server: MCPServer, connected: Bool, isBusy: Bool = false) -> some View {
        HStack(spacing: 14) {
            if server.isGitHub {
                Image("GitHubMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    // .foregroundStyle(.primary) alone doesn't stick on Mac
                    // Catalyst inside these List rows — the row's own tint
                    // wins. The older .foregroundColor API overrides it.
                    .foregroundColor(.primary)
                    .frame(width: 22)
            } else {
                Image(systemName: server.connectorIconName)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .frame(width: 22)
            }
            Text(server.displayName)
                #if targetEnvironment(macCatalyst)
                .font(MacSettingsFont.row)
                #else
                .font(BFFont.body)
                #endif
                .foregroundColor(.primary)
                // A longer-than-expected displayName (e.g. a backend not yet
                // returning the short `label` field) must not wrap to a
                // second line — that made this row taller than every other
                // row in the list, breaking the uniform row height/alignment
                // the whole Agents list otherwise has.
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if isBusy {
                ProgressView()
            } else if connected {
                Text("Connected")
                    #if targetEnvironment(macCatalyst)
                    .font(MacSettingsFont.row)
                    #else
                    .font(BFFont.body)
                    #endif
                    // Explicit weight — Mac Catalyst's native List row styling was
                    // applying its own semibold "value" treatment to this trailing
                    // text regardless of .font() alone, making it look heavier than
                    // the row's own label text.
                    .fontWeight(.regular)
                    .foregroundColor(.secondary)
            } else {
                Text("Connect")
                    #if targetEnvironment(macCatalyst)
                    .font(MacSettingsFont.row)
                    #else
                    .font(BFFont.body)
                    #endif
                    .fontWeight(.regular)
                    .foregroundColor(BFColor.primary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    fileprivate func connectGitHub() async {
        guard let api = chatManager.apiService else { return }
        githubConnectError = nil
        isConnectingGitHub = true
        defer { isConnectingGitHub = false }
        do {
            let authorizeURL = try await api.fetchGitHubAuthorizeURL()
            // cai-bff's callback page shows a static confirmation and does not
            // auto-navigate anywhere — the user dismisses the sheet themselves,
            // which this session sees as a cancellation, not a completed
            // callback (see GitHubConnectionView's earlier equivalent).
            _ = try await webAuthenticationSession.authenticate(
                using: authorizeURL,
                callbackURLScheme: "cai"
            )
            await chatManager.refreshGitHubConnectionStatus()
        } catch is ASWebAuthenticationSessionError {
            await chatManager.refreshGitHubConnectionStatus()
        } catch {
            githubConnectError = "Failed to connect GitHub. Please try again."
        }
    }
}
