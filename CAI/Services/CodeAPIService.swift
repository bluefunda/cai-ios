import Foundation

// MARK: - ADT envelope
// The abaper REST API wraps every response as { success, data, error }.

struct ADTEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?
    let message: String?
}

struct ConnectResult: Decodable {
    let status: String?
    let authenticated: Bool?
    let message: String?
}

// MARK: - Code API Service
// REST client for the abaper gateway (SAP ADT operations). Reuses the
// Keycloak token (via tokenProvider) and adds X-Realm + per-system X-SAP-*
// headers, mirroring the abaper-editor web client.

final class CodeAPIService {
    static let defaultBaseURL = "https://abaper.bluefunda.com"

    let baseURL: String
    let realm: String
    let system: SAPSystem
    private let tokenProvider: TokenProvider
    private let session: URLSession

    init(
        baseURL: String = CodeAPIService.defaultBaseURL,
        realm: String,
        system: SAPSystem,
        session: URLSession = .shared,
        tokenProvider: @escaping TokenProvider
    ) {
        self.baseURL = baseURL
        self.realm = realm
        self.system = system
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - System

    func testConnection() async throws -> ConnectResult {
        try await post("/api/v1/system/connect", body: [:])
    }

    // MARK: - Generic POST (envelope-aware)

    func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let token = try await tokenProvider()

        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(realm, forHTTPHeaderField: "X-Realm")
        request.setValue(system.host, forHTTPHeaderField: "X-SAP-Host")
        request.setValue(system.client, forHTTPHeaderField: "X-SAP-Client")
        request.setValue(system.username, forHTTPHeaderField: "X-SAP-User")
        request.setValue(system.password, forHTTPHeaderField: "X-SAP-Password")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.serverError(http.statusCode, String(body.prefix(300)))
            }
        }

        do {
            let envelope = try JSONDecoder().decode(ADTEnvelope<T>.self, from: data)
            if envelope.success, let payload = envelope.data {
                return payload
            }
            throw APIError.serverError(0, envelope.error ?? envelope.message ?? "Request failed")
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - Convenience factory

extension CodeAPIService {
    /// Builds a service for the given system, pulling the Keycloak token and
    /// realm from AuthManager. Call from the main actor (e.g. a View).
    @MainActor
    static func make(authManager: AuthManager, system: SAPSystem) -> CodeAPIService {
        let realm = authManager.realm
        return CodeAPIService(realm: realm, system: system) {
            try await authManager.refreshTokenIfNeeded()
            guard let token = await authManager.accessToken else { throw APIError.unauthorized }
            return token
        }
    }
}
