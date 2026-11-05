import Foundation

// MARK: - Notifications Service
// Confirmed against trm-gw: POST /notifications/{userId}/requests/unread-count — a
// per-user POST, not the bare GET originally assumed. v1 polls this rather than
// subscribing to trm-notifications' NATS subject directly (`trm.request.unreadCount.*`) —
// a native NATS client or an APNs bridge is Phase 2 (see trm-ios plan §06/§10).

protocol NotificationsServicing {
    func unreadCounts() async throws -> UnreadCounts
}

struct NotificationsService: NotificationsServicing {
    let client: RequestsAPIClient
    let currentUserProvider: @Sendable () async -> User?

    func unreadCounts() async throws -> UnreadCounts {
        guard let user = await currentUserProvider() else { throw RequestsAPIError.notSignedIn }
        return try await client.post("/notifications/\(user.id)/requests/unread-count", body: EmptyRequestBody())
    }
}

private struct EmptyRequestBody: Encodable {}

// MARK: - Polling

/// Polls `unreadCounts()` on a fixed interval, but only while BlueRequests is an
/// available space AND the app is in the foreground — `CAIApp` drives that through
/// `update(isRequestsAvailable:isAppActive:)`, so a personal-only user (or the flag
/// off) never sends a single request to trm-gw. Swap for a push-driven update once an APNs bridge exists.
@MainActor
final class UnreadCountPoller: ObservableObject {
    @Published private(set) var counts: UnreadCounts?

    private let service: NotificationsServicing
    private let interval: TimeInterval
    private var pollTask: Task<Void, Never>?

    var isPolling: Bool { pollTask != nil }

    init(service: NotificationsServicing, interval: TimeInterval = 30) {
        self.service = service
        self.interval = interval
    }

    /// Starts or stops polling to match the current state. Idempotent — starting
    /// while already polling doesn't restart the timer, so repeated scene-phase or
    /// entitlement updates don't trigger extra fetches. Losing the entitlement also
    /// clears `counts`, so no stale badge is left behind; merely backgrounding keeps
    /// them, so the badge doesn't flicker on return.
    func update(isRequestsAvailable: Bool, isAppActive: Bool) {
        if isRequestsAvailable && isAppActive {
            guard pollTask == nil else { return }
            start()
        } else {
            stop()
            if !isRequestsAvailable { counts = nil }
        }
    }

    func start() {
        stop()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Failures (including requestsUnavailable) are silent here — a missing
                // badge is the right degradation; screens show their own error card.
                if let counts = try? await self.service.unreadCounts(), !Task.isCancelled {
                    self.counts = counts
                }
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }
}
