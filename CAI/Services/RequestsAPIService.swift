import Foundation

// MARK: - Requests API Service
// REST client for trm-bff (bluerequests: Change Requests / Projects / Releases),
// reached through trm-gw. Reuses the same Keycloak token as chat/code — a user
// signed into the "trm" realm already holds a token valid for this backend —
// and adds X-Realm the same way CodeAPIService does for the abaper gateway.

final class RequestsAPIService {
    private let client: APIClient

    init(
        baseURL: String,
        realm: String,
        tokenProvider: @escaping TokenProvider,
        session: URLSession = .shared
    ) {
        client = APIClient(
            baseURL: baseURL,
            tokenProvider: tokenProvider,
            session: session,
            extraHeaders: ["X-Realm": realm]
        )
    }

    // MARK: - Change Requests

    func fetchChangeRequests(
        status: ChangeRequestStatus? = nil,
        projectId: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [ChangeRequestDTO] {
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let status { items.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let projectId { items.append(URLQueryItem(name: "projectId", value: projectId)) }

        let response: ChangeRequestListResponse = try await client.get(
            "/api/v1/change-requests",
            queryItems: items
        )
        return response.changeRequests
    }

    // MARK: - Projects

    func fetchProjects(limit: Int = 50, offset: Int = 0) async throws -> [ProjectDTO] {
        let items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        let response: ProjectListResponse = try await client.get("/api/v1/projects", queryItems: items)
        return response.projects
    }

    // MARK: - Releases

    func fetchReleases(status: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> [ReleaseDTO] {
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let status { items.append(URLQueryItem(name: "status", value: status)) }

        let response: ReleaseListResponse = try await client.get("/api/v1/releases", queryItems: items)
        return response.releases
    }
}

// MARK: - Convenience factory

extension RequestsAPIService {
    /// Builds a service wired to an AuthManager for token + realm provision.
    /// Call from the main actor (e.g. a View or manager).
    @MainActor
    static func make(authManager: AuthManager) -> RequestsAPIService {
        let realm = authManager.realm
        return RequestsAPIService(baseURL: AppConfig.requestsBaseURL, realm: realm) {
            try await authManager.refreshTokenIfNeeded()
            guard let token = await authManager.accessToken else { throw APIError.unauthorized }
            return token
        }
    }
}
