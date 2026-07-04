import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - Authentication Manager
// Handles Keycloak OAuth/OIDC with PKCE. All token POSTs go to auth-dev.bluefunda.com.
// Apple Sign In uses the native ASAuthorizationAppleIDButton; the identity token is
// exchanged directly with Keycloak (no BFF intermediary). Google and Microsoft use
// ASWebAuthenticationSession → Keycloak IDP redirect.

@MainActor
final class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    /// True from init until the first restoreSession() completes. Prevents
    /// the login screen flashing before the Keychain check finishes.
    @Published var isRestoringSession = true
    @Published var currentUser: User?
    @Published var accessToken: String?
    @Published var error: AuthError?

    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private var webAuthSession: ASWebAuthenticationSession?

    // PKCE verifier and anti-CSRF state — never persisted, cleared after each flow.
    private var pendingVerifier: String?
    private var pendingState: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        super.init()
    }

    // MARK: - Configuration

    struct Config {
        static let keycloakBaseURL = AppConfig.authBaseURL   // https://auth-dev.bluefunda.com
        static let clientId = "cai-ios"
        static let redirectScheme = "cai"
        static let redirectURI = "cai://auth/callback"
        /// Refresh 5 minutes before expiry for network buffer.
        static let tokenRefreshThreshold: TimeInterval = 300
        static let keychainService = "com.bluefunda.ai"
        static let appleUserIDKey = "apple_user_id"
    }

    static let bffBaseURL = AppConfig.bffBaseURL

    var realm: String = "individual"

    // MARK: - URL Builders

    private func authorizationURL(idpHint: String?, codeChallenge: String, state: String) -> URL? {
        var components = URLComponents(
            string: "\(Config.keycloakBaseURL)/realms/\(realm)/protocol/openid-connect/auth"
        )
        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id",             value: Config.clientId),
            URLQueryItem(name: "redirect_uri",          value: Config.redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: "openid profile email offline_access"),
            URLQueryItem(name: "state",                 value: state),
            URLQueryItem(name: "code_challenge",        value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if let hint = idpHint {
            items.append(URLQueryItem(name: "kc_idp_hint", value: hint))
        }
        components?.queryItems = items
        return components?.url
    }

    private var tokenURL: URL {
        URL(string: "\(Config.keycloakBaseURL)/realms/\(realm)/protocol/openid-connect/token")!
    }

    private var logoutURL: URL {
        URL(string: "\(Config.keycloakBaseURL)/realms/\(realm)/protocol/openid-connect/logout")!
    }

    // MARK: - Web OAuth Login (Google, Microsoft via Keycloak IDP)

    func login(realm: String = "individual", idpHint: String? = nil) {
        self.realm = realm
        isLoading = true
        error = nil

        guard let (verifier, challenge) = generatePKCE() else {
            error = .authenticationFailed("Could not generate PKCE parameters")
            isLoading = false
            return
        }
        let state = generateRandomToken(byteCount: 16)
        pendingVerifier = verifier
        pendingState = state

        guard let url = authorizationURL(idpHint: idpHint, codeChallenge: challenge, state: state) else {
            error = .invalidURL
            isLoading = false
            return
        }

        webAuthSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: Config.redirectScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                self?.handleAuthCallback(callbackURL: callbackURL, error: error)
            }
        }

        webAuthSession?.presentationContextProvider = self
        webAuthSession?.prefersEphemeralWebBrowserSession = false
        webAuthSession?.start()
    }

    // MARK: - Native Apple Sign-In

    /// Call `makeAuthNonce()` before presenting the button, pass the hashed value
    /// as `request.nonce`, and hand the plain value here after completion.
    func handleAppleAuthorization(
        _ authorization: ASAuthorization,
        realm: String = "individual",
        nonce: String? = nil
    ) async {
        self.realm = realm
        isLoading = true
        error = nil

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            error = .authenticationFailed("Invalid Apple credential")
            isLoading = false
            return
        }

        KeychainStore.saveString(credential.user, for: Config.appleUserIDKey, service: Config.keychainService)

        // Apple provides fullName and email only on the FIRST authorization.
        // Persist them locally so they survive subsequent sign-ins.
        if let givenName = credential.fullName?.givenName {
            UserDefaults.standard.set(givenName, forKey: "apple_given_name")
        }
        if let familyName = credential.fullName?.familyName {
            UserDefaults.standard.set(familyName, forKey: "apple_family_name")
        }
        if let email = credential.email {
            UserDefaults.standard.set(email, forKey: "apple_email")
        }

        let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }

        let fullName = [
            UserDefaults.standard.string(forKey: "apple_given_name"),
            UserDefaults.standard.string(forKey: "apple_family_name")
        ].compactMap { $0 }.joined(separator: " ")

        let email = UserDefaults.standard.string(forKey: "apple_email")

        await exchangeAppleTokenWithKeycloak(
            identityToken: identityToken,
            authorizationCode: authCode,
            nonce: nonce,
            fullName: fullName.isEmpty ? nil : fullName,
            email: email
        )
    }

    // MARK: - Keycloak Apple Token Exchange
    // POST https://auth-dev.bluefunda.com/realms/{realm}/protocol/openid-connect/token
    // grant_type=urn:ietf:params:oauth:grant-type:token-exchange
    // Requires: token-exchange feature enabled + IDP permissions granted to cai-ios in Keycloak.

    private func exchangeAppleTokenWithKeycloak(
        identityToken: String,
        authorizationCode: String?,
        nonce: String?,
        fullName: String? = nil,
        email: String? = nil
    ) async {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var body: [String: String] = [
            "grant_type":         "urn:ietf:params:oauth:grant-type:token-exchange",
            "client_id":          Config.clientId,
            "subject_token":      identityToken,
            "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
            "subject_issuer":     "apple-ios",
            "scope":              "openid profile email offline_access"
        ]
        if let code  = authorizationCode { body["authorization_code"] = code }
        if let nonce = nonce             { body["nonce"] = nonce }
        request.httpBody = body.percentEncoded()

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                error = .authenticationFailed("Could not reach authentication server")
                isLoading = false
                return
            }

            if http.statusCode == 200 {
                let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
                await processTokenResponse(tokenResponse, appleFullName: fullName, appleEmail: email)
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[AuthManager] Keycloak exchange failed: HTTP \(http.statusCode)\n\(body)")
                let kcError = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { ($0["error_description"] as? String) ?? ($0["error"] as? String) }
                error = .authenticationFailed("Keycloak \(http.statusCode): \(kcError ?? String(body.prefix(120)))")
                isLoading = false
            }
        } catch {
            self.error = .authenticationFailed("Could not reach authentication server. Please check your connection.")
            isLoading = false
        }
    }

    // MARK: - Logout / Account Deletion

    func logout() async {
        if let token = refreshToken {
            await revokeToken(token)
        }
        clearKeychain()
        KeychainStore.delete(Config.appleUserIDKey, service: Config.keychainService)
        resetSession()
    }

    func deleteAccount() async throws {
        guard let existing = accessToken else { throw AuthError.notAuthenticated }
        try? await refreshTokenIfNeeded()
        let token = accessToken ?? existing

        guard let url = URL(string: "\(Self.bffBaseURL)/user") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(realm, forHTTPHeaderField: "X-Realm")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.deleteAccountFailed("No response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.deleteAccountFailed("HTTP \(http.statusCode) \(body.prefix(120))")
        }

        clearKeychain()
        resetSession()
    }

    func refreshTokenIfNeeded() async throws {
        guard let expiresAt = tokenExpiresAt else { return }
        guard Date().addingTimeInterval(Config.tokenRefreshThreshold) > expiresAt else { return }
        try await performTokenRefresh()
    }

    /// Returns a valid access token, refreshing first if it's near expiry.
    /// If the session can no longer be refreshed (refresh/offline token expired
    /// or revoked), it expires the session — flipping the UI back to sign-in —
    /// and returns nil. Callers should treat nil as "session ended, stop here."
    func validAccessToken() async -> String? {
        do {
            try await refreshTokenIfNeeded()
            return accessToken
        } catch {
            expireSession()
            return nil
        }
    }

    /// Ends the current session and routes the app back to the sign-in screen
    /// with a clear explanation. Idempotent — safe to call from multiple places
    /// (e.g. both a proactive refresh failure and a mid-stream 401).
    func expireSession() {
        guard isAuthenticated else { return }
        clearKeychain()
        resetSession()
        error = .tokenRefreshFailed   // "Session expired. Please sign in again."
    }

    func getCredentials() -> ServiceCredentials? {
        guard let user = currentUser, let token = accessToken else { return nil }
        return ServiceCredentials(
            userId: user.id,
            realm: realm,
            accessToken: token,
            natsURL: nil,
            natsCredentials: nil,
            bffBaseURL: AppConfig.bffBaseURL
        )
    }

    // MARK: - Session Restore

    func restoreSession() async {
        defer { isRestoringSession = false }

        if let appleUserID = KeychainStore.loadString(Config.appleUserIDKey, service: Config.keychainService) {
            let state = await checkAppleCredentialState(userID: appleUserID)
            if state == .revoked || state == .notFound {
                clearKeychain()
                KeychainStore.delete(Config.appleUserIDKey, service: Config.keychainService)
                return
            }
        }

        guard let stored = loadTokensFromKeychain() else { return }

        self.realm = stored.realm
        self.refreshToken = stored.refreshToken
        do {
            try await performTokenRefresh()
        } catch {
            clearKeychain()
        }
    }

    // MARK: - Private: Web OAuth Callback

    private func handleAuthCallback(callbackURL: URL?, error: Error?) {
        defer {
            pendingState = nil
            pendingVerifier = nil
        }
        isLoading = false

        if let error = error {
            let asError = error as? ASWebAuthenticationSessionError
            if asError?.code == .canceledLogin { return }
            self.error = .authenticationFailed(error.localizedDescription)
            return
        }

        guard let url = callbackURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            self.error = .invalidCallback
            return
        }

        let params = components.queryItems ?? []

        let returnedState = params.first(where: { $0.name == "state" })?.value
        guard let returnedState, returnedState == pendingState else {
            self.error = .stateMismatch
            return
        }

        guard let code = params.first(where: { $0.name == "code" })?.value else {
            self.error = .invalidCallback
            return
        }

        let verifier = pendingVerifier
        Task {
            await exchangeCodeForToken(code: code, verifier: verifier)
        }
    }

    // POST https://auth-dev.bluefunda.com/realms/{realm}/protocol/openid-connect/token
    private func exchangeCodeForToken(code: String, verifier: String?) async {
        isLoading = true

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "grant_type":   "authorization_code",
            "client_id":    Config.clientId,
            "code":         code,
            "redirect_uri": Config.redirectURI
        ]
        if let v = verifier { body["code_verifier"] = v }
        request.httpBody = body.percentEncoded()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[AuthManager] Code exchange failed: \(body)")
                error = .tokenExchangeFailed
                isLoading = false
                return
            }
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            await processTokenResponse(tokenResponse)
        } catch {
            self.error = .tokenExchangeFailed
            isLoading = false
        }
    }

    // POST https://auth-dev.bluefunda.com/realms/{realm}/protocol/openid-connect/token
    private func performTokenRefresh() async throws {
        guard let refreshToken = refreshToken else { throw AuthError.notAuthenticated }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type":    "refresh_token",
            "client_id":     Config.clientId,
            "refresh_token": refreshToken
        ]
        request.httpBody = body.percentEncoded()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.tokenRefreshFailed
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        await processTokenResponse(tokenResponse)
    }

    private func processTokenResponse(
        _ response: TokenResponse,
        appleFullName: String? = nil,
        appleEmail: String? = nil
    ) async {
        accessToken = response.accessToken
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))

        if var user = decodeJWT(response.accessToken) {
            if user.name.isEmpty, let name = appleFullName {
                user = User(id: user.id, email: user.email.isEmpty ? (appleEmail ?? "") : user.email, name: name, roles: user.roles)
            }
            if user.email.isEmpty, let email = appleEmail {
                user = User(id: user.id, email: email, name: user.name, roles: user.roles)
            }
            currentUser = user
        } else if let appleFullName, let appleEmail {
            currentUser = User(id: "", email: appleEmail, name: appleFullName, roles: [])
        }

        refreshToken = response.refreshToken
        saveTokensToKeychain()

        isAuthenticated = true
        isLoading = false
    }

    // MARK: - Keychain

    private func saveTokensToKeychain() {
        guard let rt = refreshToken else { return }
        KeychainStore.saveAuthTokens(
            refreshToken: rt,
            realm: realm,
            expiresAt: tokenExpiresAt
        )
    }

    private func loadTokensFromKeychain() -> (refreshToken: String, realm: String, expiresAt: Date?)? {
        KeychainStore.loadAuthTokens()
    }

    private func clearKeychain() {
        KeychainStore.clearAuthTokens()
    }

    private func resetSession() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Apple Credential State

    private func checkAppleCredentialState(userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    // POST https://auth-dev.bluefunda.com/realms/{realm}/protocol/openid-connect/logout
    private func revokeToken(_ token: String) async {
        var request = URLRequest(url: logoutURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["client_id": Config.clientId, "refresh_token": token]
        request.httpBody = body.percentEncoded()
        _ = try? await session.data(for: request)
    }

    private func decodeJWT(_ token: String) -> User? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }

        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return User(
            id:    json["sub"] as? String ?? "",
            email: json["email"] as? String ?? "",
            name:  json["preferred_username"] as? String ?? json["name"] as? String ?? "",
            roles: (json["realm_access"] as? [String: Any])?["roles"] as? [String] ?? []
        )
    }

    // MARK: - Crypto Helpers

    private func generatePKCE() -> (verifier: String, challenge: String)? {
        let verifier = generateRandomToken(byteCount: 32)
        guard let data = verifier.data(using: .utf8) else { return nil }
        let challenge = Data(SHA256.hash(data: data)).base64URLEncoded()
        return (verifier, challenge)
    }

    private func generateRandomToken(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

// MARK: - Apple Nonce (module-level, no actor isolation needed)

/// Generate a one-time nonce for Apple Sign In. Pass `hashed` as `request.nonce`
/// and retain `plain` to forward to `handleAppleAuthorization(_:realm:nonce:)`.
func makeAuthNonce() -> (plain: String, hashed: String)? {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
    let plain = Data(bytes).base64URLEncoded()
    guard let plainData = plain.data(using: .utf8) else { return nil }
    let hashed = SHA256.hash(data: plainData).map { String(format: "%02x", $0) }.joined()
    return (plain, hashed)
}

// MARK: - Presentation Context

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Supporting Types

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let roles: [String]

    var isAdmin: Bool { roles.contains("admin") }
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
        case tokenType    = "token_type"
    }
}

enum AuthError: LocalizedError {
    case invalidURL
    case invalidCallback
    case stateMismatch
    case authenticationFailed(String)
    case tokenExchangeFailed
    case tokenRefreshFailed
    case notAuthenticated
    case deleteAccountFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid authentication URL"
        case .invalidCallback:
            return "Invalid authentication callback"
        case .stateMismatch:
            return "Security check failed. Please try signing in again."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for token"
        case .tokenRefreshFailed:
            return "Session expired. Please sign in again."
        case .notAuthenticated:
            return "Not authenticated"
        case .deleteAccountFailed(let reason):
            return "Couldn't delete account: \(reason)"
        }
    }
}

// MARK: - Dictionary Encoding

extension Dictionary where Key == String, Value == String {
    func percentEncoded() -> Data? {
        map { key, value in
            let ek = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let ev = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(ek)=\(ev)"
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}

// MARK: - Data: base64url encoding

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
