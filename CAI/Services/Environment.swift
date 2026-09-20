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
    // TEMP: pointed at the local on-prem test Keycloak (terraform-test,
    // config/keycloak-realm-test.json in gitops) — NOT the shared PRD
    // instance. Revert to "https://auth.bluefunda.com" before merging.
    // Port only, same host as bffBaseURL below — see devServerTrustedHost.
    static let authBaseURL = "https://192.168.4.171:8543"

    // ── BFF API ─────────────────────────────────────────────────────────────
    // TEMP: pointed at the local on-prem test server (cai-gw) for local
    // testing — revert to "https://api.bluefunda.com/ai" before merging.
    static let bffBaseURL = "https://192.168.4.171:8081"

    /// Host allowed to bypass TLS certificate validation, DEBUG builds only
    /// (see `AppConfig.session` in APIClient.swift) — the on-prem test
    /// server's cai-gw AND its local Keycloak both serve self-signed certs
    /// on this same host (different ports; the trust check matches by host
    /// only). nil in a normal build; only set while testing locally.
    ///
    /// Does NOT cover Keycloak's own login page: that renders inside
    /// ASWebAuthenticationSession, a system browser process outside this
    /// app's network stack, so this delegate-based bypass can't reach it —
    /// the cert needs OS-level trust on the device instead. See
    /// gitops stacks/test/config/README.md.
    static let devServerTrustedHost: String? = "192.168.4.171"
}
