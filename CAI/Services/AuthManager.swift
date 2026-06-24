import Foundation
import AuthenticationServices

// MARK: - Authentication Manager
// Handles Keycloak OAuth/OIDC authentication

@MainActor
final class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var currentUser: User?
    @Published var accessToken: String?
    @Published var error: AuthError?

    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private var webAuthSession: ASWebAuthenticationSession?
    // MARK: - Configuration
    struct Config {
        static let keycloakBaseURL = "https://auth.bluefunda.com"
        static let clientId = "cai-ios"
        static let redirectScheme = "cai"
        static let redirectURI = "cai://auth/callback"
        static let tokenRefreshThreshold: TimeInterval = 60 // refresh 1 minute before expiry
        static let keychainService = "com.bluefunda.ai"
        static let appleUserIDKey = "apple_user_id"
    }

    /// Public BFF gateway base (gateway.internal is cluster-only).
    static let bffBaseURL = "https://api.bluefunda.com/ai"

    var realm: String = "individual"

    // MARK: - Computed Properties

    private func authorizationURL(idpHint: String? = nil) -> URL? {
        var components = URLComponents(string: "\(Config.keycloakBaseURL)/realms/\(realm)/protocol/openid-connect/auth")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: Config.clientId),
            URLQueryItem(name: "redirect_uri", value: Config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
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

    // MARK: - Public Methods

    func login(realm: String = "individual", idpHint: String? = nil) {
        self.realm = realm
        isLoading = true
        error = nil

        guard let url = authorizationURL(idpHint: idpHint) else {
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

    func handleAppleAuthorization(_ authorization: ASAuthorization, realm: String = "individual") async {
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

        let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }

        await exchangeAppleTokenForSession(identityToken: identityToken, authorizationCode: authCode)
    }

    private func exchangeAppleTokenForSession(identityToken: String, authorizationCode: String?) async {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = [
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "client_id": Config.clientId,
            "subject_token": identityToken,
            "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
            "subject_issuer": "apple",
            "scope": "openid profile email offline_access"
        ]
        if let code = authorizationCode {
            body["authorization_code"] = code
        }
        request.httpBody = body.percentEncoded()

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                // Token exchange not supported — fall back to Keycloak web flow with Apple hint
                login(realm: realm, idpHint: "apple")
                return
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            await processTokenResponse(tokenResponse)
        } catch {
            // Fall back to web-based Apple auth via Keycloak
            login(realm: realm, idpHint: "apple")
        }
    }

    func logout() async {
        if let token = refreshToken {
            await revokeToken(token)
        }

        clearKeychain()
        KeychainStore.delete(Config.appleUserIDKey, service: Config.keychainService)

        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        currentUser = nil
        isAuthenticated = false
    }

    /// Permanently deletes the user's account server-side, then clears the
    /// local session. Mirrors the BFF contract:
    ///   DELETE https://api.bluefunda.com/ai/user
    ///   headers: Authorization: Bearer <jwt>, X-Realm: <realm>
    /// (The host is the public gateway; gateway.internal is cluster-only.)
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.deleteAccountFailed("No response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.deleteAccountFailed("HTTP \(http.statusCode) \(body.prefix(120))")
        }

        // Account is gone — wipe the local session (no token revoke needed).
        clearKeychain()
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        currentUser = nil
        isAuthenticated = false
    }

    func refreshTokenIfNeeded() async throws {
        guard let expiresAt = tokenExpiresAt else { return }

        // Check if token needs refresh
        if Date().addingTimeInterval(Config.tokenRefreshThreshold) > expiresAt {
            try await performTokenRefresh()
        }
    }

    func getCredentials() -> ServiceCredentials? {
        guard let user = currentUser, let token = accessToken else {
            return nil
        }

        return ServiceCredentials(
            userId: user.id,
            realm: realm,
            accessToken: token,
            natsURL: nil,
            natsCredentials: nil,
            bffBaseURL: "https://api.bluefunda.com/ai"
        )
    }

    // MARK: - Private Methods

    private func handleAuthCallback(callbackURL: URL?, error: Error?) {
        isLoading = false

        if let error = error {
            self.error = .authenticationFailed(error.localizedDescription)
            return
        }

        guard let url = callbackURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            self.error = .invalidCallback
            return
        }

        Task {
            await exchangeCodeForToken(code: code)
        }
    }

    private func exchangeCodeForToken(code: String) async {
        isLoading = true

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "client_id": Config.clientId,
            "code": code,
            "redirect_uri": Config.redirectURI
        ]
        request.httpBody = body.percentEncoded()

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
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

    private func performTokenRefresh() async throws {
        guard let refreshToken = refreshToken else {
            throw AuthError.notAuthenticated
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "client_id": Config.clientId,
            "refresh_token": refreshToken
        ]
        request.httpBody = body.percentEncoded()

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        await processTokenResponse(tokenResponse)
    }

    private func processTokenResponse(_ response: TokenResponse) async {
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))

        // Decode user info from JWT
        if let user = decodeJWT(response.accessToken) {
            currentUser = user
        }

        // Persist tokens to Keychain for app restart
        saveTokensToKeychain()

        isAuthenticated = true
        isLoading = false
    }

    // MARK: - Keychain Persistence

    private func saveTokensToKeychain() {
        guard let refreshToken = refreshToken else { return }
        KeychainStore.saveAuthTokens(refreshToken: refreshToken, realm: realm, expiresAt: tokenExpiresAt)
    }

    private func loadTokensFromKeychain() -> (refreshToken: String, realm: String)? {
        KeychainStore.loadAuthTokens()
    }

    private func clearKeychain() {
        KeychainStore.clearAuthTokens()
    }

    /// Call this on app launch to restore session.
    /// Checks Apple credential state first, then restores Keycloak tokens.
    func restoreSession() async {
        // Check if Apple credential is still valid
        if let appleUserID = KeychainStore.loadString(Config.appleUserIDKey, service: Config.keychainService) {
            let state = await checkAppleCredentialState(userID: appleUserID)
            if state == .revoked || state == .notFound {
                clearKeychain()
                KeychainStore.delete(Config.appleUserIDKey, service: Config.keychainService)
                return
            }
        }

        guard let stored = loadTokensFromKeychain() else {
            return
        }

        self.realm = stored.realm
        self.refreshToken = stored.refreshToken

        do {
            try await performTokenRefresh()
        } catch {
            clearKeychain()
        }
    }

    private func checkAppleCredentialState(userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    private func revokeToken(_ token: String) async {
        var request = URLRequest(url: logoutURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": Config.clientId,
            "refresh_token": token
        ]
        request.httpBody = body.percentEncoded()

        _ = try? await URLSession.shared.data(for: request)
    }

    private func decodeJWT(_ token: String) -> User? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }

        let payload = parts[1]
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return User(
            id: json["sub"] as? String ?? "",
            email: json["email"] as? String ?? "",
            name: json["preferred_username"] as? String ?? json["name"] as? String ?? "",
            roles: (json["realm_access"] as? [String: Any])?["roles"] as? [String] ?? []
        )
    }
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

    var isAdmin: Bool {
        roles.contains("admin")
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

enum AuthError: LocalizedError {
    case invalidURL
    case invalidCallback
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
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for token"
        case .tokenRefreshFailed:
            return "Failed to refresh token"
        case .notAuthenticated:
            return "Not authenticated"
        case .deleteAccountFailed(let reason):
            return "Couldn't delete account: \(reason)"
        }
    }
}

// MARK: - Dictionary Extension

extension Dictionary where Key == String, Value == String {
    func percentEncoded() -> Data? {
        map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}