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
    // TEMP: pointed at the local on-prem test server (cai-gw) for local
    // testing — revert to "https://api.bluefunda.com/ai" before merging.
    static let bffBaseURL = "https://192.168.4.171:8081"

    /// Host allowed to bypass TLS certificate validation, DEBUG builds only
    /// (see `AppConfig.session` in APIClient.swift) — the on-prem test
    /// server's cai-gw serves a self-signed cert on this host. nil in a
    /// normal build; only set while testing locally.
    static let devServerTrustedHost: String? = "192.168.4.171"
}
