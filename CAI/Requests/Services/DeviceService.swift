import Foundation

// MARK: - Device Service
// Push notification devices (FCM registration tokens), as the backend stores them:
//   POST /notifications/devices         { token, platform, appVersion } → 204 (idempotent)
//   POST /notifications/devices/remove  { token }                       → 204
// A token is registered for the signed-in user and removed on sign-out, so a shared
// device stops getting the previous user's notifications.

protocol DeviceServicing {
    func register(token: String, platform: String, appVersion: String) async throws
    func unregister(token: String) async throws
}

struct DeviceService: DeviceServicing {
    let client: RequestsAPIClient

    func register(token: String, platform: String, appVersion: String) async throws {
        try await client.postDiscardingResponse(
            "/notifications/devices",
            body: RegisterBody(token: token, platform: platform, appVersion: appVersion)
        )
    }

    func unregister(token: String) async throws {
        try await client.postDiscardingResponse("/notifications/devices/remove", body: RemoveBody(token: token))
    }

    private struct RegisterBody: Encodable {
        let token: String
        let platform: String
        let appVersion: String
    }

    private struct RemoveBody: Encodable { let token: String }
}

/// Fixtures mode has no backend: registering a device does nothing.
struct FixtureDeviceService: DeviceServicing {
    func register(token: String, platform: String, appVersion: String) async throws {}
    func unregister(token: String) async throws {}
}
