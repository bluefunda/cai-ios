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
    static let authBaseURL = "https://auth.bluefunda.com"

    // ── BFF API ─────────────────────────────────────────────────────────────
    static let bffBaseURL = "https://api.bluefunda.com/ai"
}
