import Foundation

// MARK: - Destinations
// The second level of the Space → Destination model (docs/BLUEREQUESTS_INTEGRATION.md
// P2). Replaces the old two-value `AppMode` (chat/code), which hid Code behind a lone
// sidebar row. Raw values are what WorkspaceStore persists per space.

enum AssistantDestination: String, CaseIterable, Identifiable {
    case chats, code, files, agents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats: return "Chats"
        case .code: return "Code"
        case .files: return "Files"
        case .agents: return "Agents"
        }
    }

    var icon: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .files: return "folder"
        case .agents: return "brain.head.profile"
        }
    }

    /// Reads the pre-spaces `app_mode` value ("chat" / "code") once, so a user who
    /// left the app in Code comes back to Code. Removes the old key afterwards.
    static func migratingLegacyAppMode(defaults: UserDefaults) -> AssistantDestination? {
        guard let legacy = defaults.string(forKey: legacyAppModeKey) else { return nil }
        defaults.removeObject(forKey: legacyAppModeKey)
        return legacy == "code" ? .code : .chats
    }

    static let legacyAppModeKey = "app_mode"
}

/// Only reachable for `trm` org members with the feature flag on — see
/// WorkspaceStore.availableSpaces. The screens behind these land with the Requests
/// port; until then each shows a placeholder.
enum RequestsDestination: String, CaseIterable, Identifiable {
    case messages, requests, projects, releases, teams, git
    // Admin only (trm's web nav shows these under its admin section).
    case userManagement, requestTemplates, manageTeams, configurations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .messages: return "Messages"
        case .requests: return "Requests"
        case .projects: return "Projects"
        case .releases: return "Releases"
        case .teams: return "Teams"
        case .git: return "Git"
        case .userManagement: return "User Management"
        case .requestTemplates: return "Request Templates"
        case .manageTeams: return "Manage Teams"
        case .configurations: return "Configurations"
        }
    }

    var icon: String {
        switch self {
        case .messages: return "bubble.left.and.bubble.right"
        case .requests: return "doc.text"
        case .projects: return "folder.badge.gearshape"
        case .releases: return "shippingbox"
        case .teams: return "person.2"
        case .git: return "arrow.triangle.branch"
        case .userManagement: return "person.badge.key"
        case .requestTemplates: return "doc.on.doc"
        case .manageTeams: return "person.3"
        case .configurations: return "gearshape.2"
        }
    }

    /// The `admin-trm` role trm's web nav requires to show this destination
    /// (leftNavbar/index.js); nil means every Requests user sees it.
    var requiredRole: String? {
        switch self {
        case .releases: return "release-manager"
        case .userManagement, .requestTemplates, .manageTeams, .configurations: return "admin"
        case .messages, .requests, .projects, .teams, .git: return nil
        }
    }

    static func available(roles: [String]) -> [RequestsDestination] {
        allCases.filter { $0.requiredRole.map(roles.contains) ?? true }
    }
}

/// One fixed row in the sidebar's destination list, from either space.
enum SidebarDestination: Hashable, Identifiable {
    case assistant(AssistantDestination)
    case requests(RequestsDestination)

    var id: String {
        switch self {
        case .assistant(let destination): return "assistant.\(destination.rawValue)"
        case .requests(let destination): return "requests.\(destination.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .assistant(let destination): return destination.title
        case .requests(let destination): return destination.title
        }
    }

    var icon: String {
        switch self {
        case .assistant(let destination): return destination.icon
        case .requests(let destination): return destination.icon
        }
    }

    /// `sidebar.destination.chats`, `sidebar.destination.requests`, …
    var accessibilityIdentifier: String {
        switch self {
        case .assistant(let destination): return "sidebar.destination.\(destination.rawValue)"
        case .requests(let destination): return "sidebar.destination.\(destination.rawValue)"
        }
    }
}

// MARK: - Sidebar Layout
// What the sidebar shows, worked out from the workspace alone so it can be unit
// tested: a personal-only user must get no space switcher and no Requests rows.

struct SidebarLayout: Equatable {
    let showsSpaceSwitcher: Bool
    let spaces: [AppSpace]
    let activeSpace: AppSpace
    let destinations: [SidebarDestination]

    init(availableSpaces: [AppSpace], activeSpace: AppSpace, requestsRoles: [String] = []) {
        spaces = availableSpaces
        showsSpaceSwitcher = availableSpaces.count > 1
        // Never render a space the user can't use, whatever was persisted.
        self.activeSpace = availableSpaces.contains(activeSpace) ? activeSpace : .assistant
        switch self.activeSpace {
        case .assistant: destinations = AssistantDestination.allCases.map { .assistant($0) }
        case .requests: destinations = RequestsDestination.available(roles: requestsRoles).map { .requests($0) }
        }
    }

    @MainActor
    init(workspace: WorkspaceStore) {
        self.init(availableSpaces: workspace.availableSpaces, activeSpace: workspace.activeSpace,
                  requestsRoles: workspace.requestsRoles)
    }
}

// MARK: - Typed Destination State

extension WorkspaceStore {
    var assistantDestination: AssistantDestination {
        get {
            lastDestination(for: .assistant).flatMap(AssistantDestination.init(rawValue:)) ?? .chats
        }
        set { setLastDestination(newValue.rawValue, for: .assistant) }
    }

    /// Falls back to Requests when the stored destination needs a role the user
    /// doesn't have (or no longer has).
    var requestsDestination: RequestsDestination {
        get {
            let stored = lastDestination(for: .requests).flatMap(RequestsDestination.init(rawValue:))
            return stored.flatMap { availableRequestsDestinations.contains($0) ? $0 : nil } ?? .requests
        }
        set { setLastDestination(newValue.rawValue, for: .requests) }
    }

    /// The destination currently on screen, across both spaces.
    var currentDestination: SidebarDestination {
        switch activeSpace {
        case .assistant: return .assistant(assistantDestination)
        case .requests: return .requests(requestsDestination)
        }
    }

    /// Switches to `destination`'s space (if available) and to the destination itself.
    func navigate(to destination: SidebarDestination) {
        switch destination {
        case .assistant(let assistant):
            activeSpace = .assistant
            assistantDestination = assistant
        case .requests(let requests):
            guard isRequestsAvailable, availableRequestsDestinations.contains(requests) else { return }
            activeSpace = .requests
            requestsDestination = requests
        }
    }

    /// One-time move of the pre-spaces `app_mode` setting into the Assistant space's
    /// last destination. A destination already stored wins over the legacy value.
    func migrateLegacyAppMode() {
        guard let legacy = AssistantDestination.migratingLegacyAppMode(defaults: defaults) else { return }
        guard lastDestination(for: .assistant) == nil else { return }
        assistantDestination = legacy
    }
}
