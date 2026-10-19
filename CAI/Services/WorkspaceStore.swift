import Foundation

// MARK: - App Space
// The top level of the Space → Destination model (docs/BLUEREQUESTS_INTEGRATION.md
// P2). Assistant is everyone's; Requests is an entitlement from the token's
// `organization` claim, never a second sign-in (P1).

enum AppSpace: String, CaseIterable, Identifiable {
    case assistant
    case requests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: return "Assistant"
        case .requests: return "Requests"
        }
    }
}

// MARK: - Workspace Store
// Owns which spaces the signed-in user can see, the active one, and each
// space's last destination (all persisted in UserDefaults, same keys an
// `@AppStorage` reader would use).
//
// Only one workspace exists today. A multi-org picker would hang off
// `organizations` here — the seam is deliberate, the picker is out of scope.

@MainActor
final class WorkspaceStore: ObservableObject {
    /// Every org alias in the current token, fed from `AuthManager.currentUser`
    /// by `CAIApp` whenever the user changes (sign-in, refresh, sign-out).
    @Published private(set) var organizations: [String] = []

    /// The persisted choice — may name a space that isn't currently available
    /// (e.g. before sign-in, or after leaving the `trm` org). Kept as-is so the
    /// choice survives a transient loss of entitlement; read `activeSpace`.
    @Published private var storedSpace: AppSpace {
        didSet { defaults.set(storedSpace.rawValue, forKey: Self.activeSpaceKey) }
    }

    private let defaults: UserDefaults
    private let isRequestsFeatureEnabled: () -> Bool

    static let activeSpaceKey = "workspace_active_space"
    static func lastDestinationKey(for space: AppSpace) -> String {
        "workspace_last_destination_\(space.rawValue)"
    }

    init(
        defaults: UserDefaults = .standard,
        isRequestsFeatureEnabled: @escaping () -> Bool = { BFFeatureFlags.requestsEnabled }
    ) {
        self.defaults = defaults
        self.isRequestsFeatureEnabled = isRequestsFeatureEnabled
        storedSpace = defaults.string(forKey: Self.activeSpaceKey).flatMap(AppSpace.init(rawValue:)) ?? .assistant
    }

    // MARK: - Entitlement

    /// Assistant always; Requests only with the feature flag on AND membership
    /// in `AppConfig.requestsOrgAlias`. A personal-only user gets exactly one
    /// space, which hides the space switcher entirely (P2, P11).
    var availableSpaces: [AppSpace] {
        Self.availableSpaces(
            organizations: organizations,
            requestsFeatureEnabled: isRequestsFeatureEnabled()
        )
    }

    static func availableSpaces(organizations: [String], requestsFeatureEnabled: Bool) -> [AppSpace] {
        var spaces: [AppSpace] = [.assistant]
        if requestsFeatureEnabled, organizations.contains(AppConfig.requestsOrgAlias) {
            spaces.append(.requests)
        }
        return spaces
    }

    var isRequestsAvailable: Bool { availableSpaces.contains(.requests) }

    func update(organizations: [String]) {
        guard organizations != self.organizations else { return }
        self.organizations = organizations
    }

    // MARK: - Active Space

    /// Falls back to Assistant whenever the stored space isn't available, so
    /// callers never render a space the user can't use.
    var activeSpace: AppSpace {
        get { availableSpaces.contains(storedSpace) ? storedSpace : .assistant }
        set {
            guard availableSpaces.contains(newValue) else { return }
            storedSpace = newValue
        }
    }

    // MARK: - Last Destination

    /// Raw value of the destination last shown in `space`, so switching back
    /// lands where the user left off. Typed per space by the shell
    /// (`AssistantDestination` / `RequestsDestination`).
    func lastDestination(for space: AppSpace) -> String? {
        defaults.string(forKey: Self.lastDestinationKey(for: space))
    }

    func setLastDestination(_ rawValue: String, for space: AppSpace) {
        guard lastDestination(for: space) != rawValue else { return }
        objectWillChange.send()
        defaults.set(rawValue, forKey: Self.lastDestinationKey(for: space))
    }
}
