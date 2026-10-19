import Foundation

/// Build-time and runtime feature flags.
///
/// Defaults are set conservatively (off). Override any flag at runtime via
/// UserDefaults — useful for internal testing without a code change:
///
///   UserDefaults.standard.set(true, forKey: BFFeatureFlags.Keys.fileUpload)
///
/// Or via an Xcode scheme launch argument:  -bf_file_upload YES
///
enum BFFeatureFlags {
    enum Keys {
        static let fileUpload = "bf_feature_file_upload"
        static let personaWire = "bf_feature_persona_wire"
        static let requests = "bf_feature_requests"
        static let requestsFixtures = "bf_requests_fixtures"
    }

    /// File attachment (photo library + document picker) in the chat input bar.
    /// Enabled by default now that attachments persist locally via LocalFileStore
    /// and the backend upload + fileUrl contract is confirmed production-ready.
    /// Override to false via UserDefaults/launch argument to kill-switch it.
    static var fileUploadEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.fileUpload) != nil
            ? UserDefaults.standard.bool(forKey: Keys.fileUpload)
            : true
    }

    /// Whether the resolved persona (global default or per-message override)
    /// is actually sent to the backend on `ChatRequest.persona`. On by default
    /// (2026-08-03) — backend-side work (cai-bff#110-112, cai-llm-router#242-244,
    /// cai-mcp-go#180-182) shipped and confirmed working end-to-end in a live
    /// device test (groq and gemini models; IS-U persona verified against real
    /// SAP tcodes). Override to false via UserDefaults/launch argument to
    /// kill-switch it if a regression turns up.
    static var personaWireEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.personaWire) != nil
            ? UserDefaults.standard.bool(forKey: Keys.personaWire)
            : true
    }

    /// The BlueRequests space (change requests, projects, releases, teams) for
    /// members of the `trm` Keycloak organization. Off by default until the
    /// backend accepts `individual`-realm tokens on /requests and maps the org
    /// claim to the tenant (see docs/BLUEREQUESTS_INTEGRATION.md, "Tenancy").
    /// Even when on, the space only appears for `trm` org members — see
    /// WorkspaceStore.availableSpaces.
    static var requestsEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.requests) != nil
            ? UserDefaults.standard.bool(forKey: Keys.requests)
            : false
    }

    /// Backs every BlueRequests service with RequestsFixtures' canned data
    /// instead of the network, so the Requests screens can be exercised (and
    /// screenshotted) without a live trm backend:  -bf_requests_fixtures YES
    static var requestsFixtures: Bool {
        UserDefaults.standard.object(forKey: Keys.requestsFixtures) != nil
            ? UserDefaults.standard.bool(forKey: Keys.requestsFixtures)
            : false
    }
}
