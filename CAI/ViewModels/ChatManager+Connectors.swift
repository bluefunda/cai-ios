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
    /// Only GitHub has a real connect flow so far — every other connector has
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
            if server.isABAPer { return connectedSAP }
            return locallyConnectedServerIDs.contains(server.id)
        }
    }

    /// Maps the selected MCP server to a backend agent name.
    /// Convention: strip the "-mcp" suffix (e.g. "research-tools-mcp" → "research-tools").
    ///
    /// ABAPer is deliberately excluded: cai-llm-router's agents.yaml already has an
    /// "abaper" agent profile, but for a different, narrower workflow ("implement
    /// this GitHub issue in ABAP") that hardcodes github-mcp as a required co-server.
    /// Sending agentName: "abaper" here for ordinary ABAPer chat hits that same
    /// highest-priority routing rule by name collision, silently pulling in a
    /// github-mcp requirement the user never asked for — confirmed live: with only
    /// ABAPer connected (GitHub disconnected), every message failed with an MCP
    /// connection error, even though ABAPer's own connection was fine. Returning nil
    /// here instead lets it fall through to the general has_mcp/mcp-default routing
    /// rule, which only ever includes the servers actually connected+enabled for
    /// this conversation.
    var agentNameForSelectedServer: String? {
        guard let server = selectedMCPServer, !server.isABAPer else { return nil }
        if server.name.hasSuffix("-mcp") {
            return String(server.name.dropLast(4))
        }
        return server.name
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
