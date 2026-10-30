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
//
// BlueRequests API (trm-gw → trm-backend-go), same identity as the BFF
//   Production: "https://api.bluefunda.com/requests"

import Foundation

enum AppConfig {

    // ── Auth (Keycloak IDP) ──────────────────────────────────────────────────
    // Change this one string to redirect ALL auth flows (login, token, logout)
    // to a different IDP host. Client ID and realm are unchanged.
    static let authBaseURL = "https://auth.bluefunda.com"

    // ── BFF API ─────────────────────────────────────────────────────────────
    static let bffBaseURL = "https://api.bluefunda.com/ai"

    // ── BlueRequests (trm-gw / KrakenD) ──────────────────────────────────────
    // Same api.bluefunda.com host as the BFF, under /requests. Called with the
    // same `individual`-realm token as chat — the tenant comes from the token's
    // `organization` claim server-side, never from a client header (see
    // docs/BLUEREQUESTS_INTEGRATION.md P1).
    static let requestsBaseURL = "https://api.bluefunda.com/requests"

    /// Keycloak Organization alias whose members get the BlueRequests space.
    /// Matches the old `trm` realm name, so trm-backend-go's tenant DB map keeps
    /// working once it substitutes org for realm.
    static let requestsOrgAlias = "trm"

    /// Keycloak client whose client roles (`admin`, `release-manager`, …) are the
    /// BlueRequests roles in the shared `individual` realm — trm's web app reads
    /// the same ones (src/utilities/organization.js getRoles), never realm roles.
    static let requestsRolesClient = "admin-trm"

    // How long a single BlueRequests call (GET/POST/PUT, including multipart
    // uploads) waits before giving up — trm-gw's own gateway timeout is in a
    // similar range, and per-row enrichment on the change-requests endpoint (up
    // to 7 extra DB round trips per row) is what makes a large/unbounded fetch a
    // real risk of hitting it (see ChangeRequestFilter.limit's doc comment).
    static let requestsRequestTimeout: TimeInterval = 90

    // GET retry on transient transport errors (connection lost, timeout, host
    // unreachable — see RequestsAPIClient.performWithRetry). Carried over from
    // trm-ios, which bumped it from 3/400ms to 5/600ms after an unbounded
    // change-requests fetch needed more than 3 short retries under real
    // per-row-enrichment load (bluefunda/trm#139).
    static let requestsMaxAttempts = 5
    static let requestsRetryBaseBackoff: TimeInterval = 0.6
}
