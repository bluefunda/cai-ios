import Foundation

// MARK: - Connectors (Agents)
// Split from ChatManager's main body to stay under SwiftLint's type_body_length limit
// (bluefunda/cai-ios#261 precedent — see ChatManager+Background.swift and its siblings).
extension ChatManager {
    /// Every MCP server the backend returns is now shown — nothing is hidden by name
    /// anymore. A connector without a real Connect flow yet (e.g. SAP Analytics) still
    /// shows up; its "Connect" is just inert until that flow lands, same as it already
    /// reads in Settings → Agents.
    var visibleMCPServers: [MCPServer] {
        availableMCPServers
    }

    /// Every *connected* server's tools, enabled by default for a new
    /// conversation (Settings → Connectors' composer-popup toggle can still
    /// turn individual ones off per-chat — see `enabledMCPServersByConversationID`).
    /// GitHub and Figma (OAuth) and ABAPer and OData (credentials) have real connect flows —
    /// every other connector has
    /// no backing mechanism yet (Settings → Connectors shows them but their
    /// "Connect" does nothing), so it can never count as connected until its
    /// own flow exists. Re-evaluate this gate as each connector's real
    /// connect flow lands.
    var defaultConnectedMCPServerIDs: Set<String> {
        Set(connectedMCPServers.map(\.id))
    }

    /// Same connected-gate as `defaultConnectedMCPServerIDs`, as server objects
    /// rather than ids — what the composer's per-chat Connectors toggle lists.
    var connectedMCPServers: [MCPServer] {
        visibleMCPServers.filter { server in
            if server.isGitHub { return connectedGitHub }
            if server.isFigma { return connectedFigma }
            if server.isABAPer { return connectedSAP }
            if server.isOData { return odataConnection?.connected == true }
            if server.isApollo { return connectedOneTapNames.contains(server.name) }
            return locallyConnectedServerIDs.contains(server.id)
        }
    }

    /// GitHub's connect/disconnect status (Settings → Connectors), fetched once at
    /// startup and refreshed by GitHubConnectionView after a connect/disconnect
    /// action — kept here rather than screen-local state so the Connectors list
    /// row and the composer's per-chat Connectors toggle can both read it without
    /// each independently re-fetching.
    func refreshGitHubConnectionStatus() async {
        guard let api = apiService else { return }
        do {
            let status = try await api.fetchGitHubOAuthStatus()
            connectedGitHub = status.connected
            githubUsername = status.username
        } catch {
            print("[ChatManager] refreshGitHubConnectionStatus error: \(error)")
        }
    }

    /// Figma's connect/disconnect status, same pattern as GitHub's
    /// (bluefunda/infra#54). A backend without Figma OAuth answers 404, which
    /// leaves Figma shown as not connected.
    func refreshFigmaConnectionStatus() async {
        guard let api = apiService else { return }
        do {
            let status = try await api.fetchFigmaOAuthStatus()
            connectedFigma = status.connected
            figmaUsername = status.username
        } catch {
            print("[ChatManager] refreshFigmaConnectionStatus error: \(error)")
        }
    }

    /// Clears every connector's connection state on sign-out.
    func resetConnectorConnections() {
        connectedGitHub = false
        githubUsername = nil
        connectedFigma = false
        figmaUsername = nil
        connectedSAP = false
        sapHost = nil
        odataConnection = nil
        connectedOneTapNames = []
        locallyConnectedServerIDs = []
    }

    /// ABAPer's connect/disconnect status (Settings → Agents), same pattern
    /// as refreshGitHubConnectionStatus — fetched once at startup and
    /// refreshed by ABAPerConnectionView after a connect/disconnect action.
    func refreshSAPConnectionStatus() async {
        guard let api = apiService else { return }
        do {
            let status = try await api.fetchSAPCredentialsStatus()
            connectedSAP = status.connected
            sapHost = status.host
        } catch {
            print("[ChatManager] refreshSAPConnectionStatus error: \(error)")
        }
    }

    /// The OData connector's status, same pattern as ABAPer's. A backend
    /// without OData connections answers 404, which leaves it not connected.
    func refreshODataConnectionStatus() async {
        guard let api = apiService else { return }
        do {
            odataConnection = try await api.fetchODataConnectionStatus()
        } catch {
            print("[ChatManager] refreshODataConnectionStatus error: \(error)")
        }
    }

    /// Every connector's status again — connections are per user, so one made on
    /// another device (or the web) since the app was last active shows up on
    /// return, and new chats send that agent (cai web refreshes on tab focus).
    func refreshConnectorConnections() async {
        guard apiService != nil else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshGitHubConnectionStatus() }
            group.addTask { await self.refreshFigmaConnectionStatus() }
            group.addTask { await self.refreshSAPConnectionStatus() }
            group.addTask { await self.refreshODataConnectionStatus() }
            group.addTask { await self.refreshOneTapConnectors() }
        }
    }

    /// One-tap connectors' status (Apollo.io), same pattern as OData's. A backend
    /// without them answers 404, which leaves them not connected.
    func refreshOneTapConnectors() async {
        guard let api = apiService else { return }
        do {
            connectedOneTapNames = Set(try await api.fetchOneTapConnectors().connected)
        } catch {
            print("[ChatManager] refreshOneTapConnectors error: \(error)")
        }
    }

    /// Connects or disconnects a one-tap connector for this user (cai-bff), then
    /// turns its tools on or off for the current chat. Throws so the caller can say so.
    func setOneTapConnector(_ server: MCPServer, connected: Bool) async throws {
        guard let api = apiService else { return }
        let status = connected
            ? try await api.connectOneTapConnector(server.name)
            : try await api.disconnectOneTapConnector(server.name)
        connectedOneTapNames = Set(status.connected)
        if connected {
            enabledMCPServers.insert(server.id)
        } else {
            enabledMCPServers.remove(server.id)
        }
    }

    func loadMCPServers() async {
        guard let api = apiService else { return }

        async let allServers = api.fetchAllMCPServers()
        async let userServers = api.fetchUserMCPServers()

        do {
            let (all, user) = try await (allServers, userServers)
            let subscribedIds = Set(user.map(\.id))
            subscribedMCPServerIds = subscribedIds

            // isAvailable: false (backend kill switch for a specific MCP server) must not
            // show anywhere — Settings → Agents or the composer's Agents toggle both derive
            // from availableMCPServers, so filtering it out here is the single point that
            // covers both. nil (the field genuinely absent) still means available — only an
            // explicit false excludes.
            availableMCPServers = all
                .filter { $0.enabled != false }
                .map { dto in
                    MCPServer(id: dto.id, name: dto.name, url: dto.resolvedURL, description: dto.description, label: dto.label)
                }
            // Seed the active selection from what's connected, but only when
            // nothing has explicitly tracked one yet for this conversation
            // (cold start, or a conversation never visited before) — a user's
            // own per-chat toggle in the composer's Connectors tab must never
            // be silently reset by a later background refresh of the catalog.
            if let id = currentConversation?.id {
                if enabledMCPServersByConversationID[id] == nil {
                    enabledMCPServers = defaultConnectedMCPServerIDs
                }
            } else {
                enabledMCPServers = defaultConnectedMCPServerIDs
            }
        } catch {
            print("[ChatManager] loadMCPServers error: \(error)")
        }
    }
}
