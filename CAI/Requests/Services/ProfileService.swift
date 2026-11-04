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
    /// Stores `jpeg` as the user's picture and returns its URL.
    func uploadProfileImage(_ jpeg: Data, userId: String) async throws -> String
    /// Saves the picture's URL on the profile; "" removes it.
    func setProfileImage(_ url: String, userId: String) async throws
}

/// POST /profileImageUpload's answer, as the gateway wraps it: {"file": [{"url": …}]}.
struct ProfileImageUploadResponse: Decodable {
    struct File: Decodable { let url: String }
    let file: [File]
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
        try await update(UpdateUserRequest(updatedBy: userId, notification: enabled), userId: userId)
    }

    /// As the web's profile page (profile.js): the image goes to the file store as the
    /// form field `image` with the user's `id`.
    func uploadProfileImage(_ jpeg: Data, userId: String) async throws -> String {
        let data = try await client.uploadMultipart(
            "/rest/trm/v1/profileImageUpload",
            data: jpeg, filename: "profile.jpg", mimeType: "image/jpeg",
            fileField: "image", fields: ["id": userId]
        )
        guard let url = try JSONDecoder().decode(ProfileImageUploadResponse.self, from: data).file.first?.url else {
            throw RequestsAPIError.serverError(500, "The upload returned no picture")
        }
        return Self.withoutPort(url)
    }

    func setProfileImage(_ url: String, userId: String) async throws {
        try await update(UpdateUserRequest(updatedBy: userId, profileImage: url), userId: userId)
    }

    /// The file store answers with its internal port (https://host:9000/…); the web
    /// drops it before saving, and so does this.
    static func withoutPort(_ url: String) -> String {
        url.replacingOccurrences(of: #":\d+/"#, with: "/", options: .regularExpression)
    }

    private func update(_ request: UpdateUserRequest, userId: String) async throws {
        try await client.putDiscardingResponse(
            "/rest/trm/v1/update-user",
            queryItems: [URLQueryItem(name: "userId", value: userId)],
            body: request
        )
    }
}
