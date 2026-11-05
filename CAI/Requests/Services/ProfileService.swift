import Foundation

// MARK: - Profile Service
// Self-service profile only (name/email/department/role/team/notifications) — the admin
// "manage other users" feature stays web-only, same call as the rest of admin config.
//
// Confirmed against trm-gw: GET /rest/trm/v1/user (query: id) and PUT /rest/trm/v1/update-user
// (query: userId) — a different path family (/rest/trm/v1/...) than the /change-requests-style
// BFF routes, both routing to trm-backend-go directly rather than through the BFF.

protocol ProfileServicing {
    func fetchProfile(userId: String) async throws -> UserProfile
    func updateNotificationPreference(_ enabled: Bool, userId: String) async throws
}

struct ProfileService: ProfileServicing {
    let client: RequestsAPIClient

    func fetchProfile(userId: String) async throws -> UserProfile {
        let response: UserProfileListResponse = try await client.get(
            "/rest/trm/v1/user",
            queryItems: [URLQueryItem(name: "id", value: userId)]
        )
        guard let profile = response.users.first else {
            throw RequestsAPIError.serverError(404, "Profile not found")
        }
        return profile
    }

    func updateNotificationPreference(_ enabled: Bool, userId: String) async throws {
        let request = UpdateUserRequest(updatedBy: userId, notification: enabled)
        try await client.putDiscardingResponse(
            "/rest/trm/v1/update-user",
            queryItems: [URLQueryItem(name: "userId", value: userId)],
            body: request
        )
    }
}
