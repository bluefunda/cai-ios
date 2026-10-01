// MARK: - Environment
//
// Single source of truth for all backend host configuration.
// To switch environments, change the values below and rebuild — nothing else needs touching.
//
// Auth IDP
//   Production : "https://auth.bluefunda.com"
//   Development: "https://auth-dev.bluefunda.com"
//
// BFF API (not changing with IDP switch — same for all environments)
//   Production: "https://api.bluefunda.com/ai"

enum AppConfig {

    // ── Auth (Keycloak IDP) ──────────────────────────────────────────────────
    // Change this one string to redirect ALL auth flows (login, token, logout)
    // to a different IDP host. Client ID and realm are unchanged.
    static let authBaseURL = "https://auth-test.bluefunda.com"

    // ── BFF API ─────────────────────────────────────────────────────────────
    static let bffBaseURL = "https://api-test.bluefunda.com/ai"

    // ── Requests (trm-gw → trm-bff: Change Requests / Projects / Releases) ───
    // Host is a placeholder — there's no public DNS name confirmed yet for
    // trm-gw outside its cluster; trm-bff's own docs only show the internal
    // apps.internal:8083 address. Confirm the externally-routable host before
    // relying on this in a build that talks to a real backend.
    static let requestsBaseURL = "https://trm-gw-test.bluefunda.com"
}
