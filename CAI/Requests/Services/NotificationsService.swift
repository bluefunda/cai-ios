import Foundation

// MARK: - Notifications Service
// Same source as trm's web (App.js fetchUnreadRequestsNotificationCount): the SSE stream
// GET /notifications/{userId}/requests/stream (trm-gw → trm-bff → NATS
// `{realm}.notifications.{userId}.requests`). Each event is a JSON array of snapshots and
// the web reads the last one. The earlier POST .../requests/unread-count has a trm-gw
// route but no trm-bff handler, so it only ever answered 404.

protocol NotificationsServicing {
    /// Unread-count snapshots as the server pushes them. Ends when the stream closes.
    func unreadCountUpdates() -> AsyncThrowingStream<UnreadCounts, Error>
}

struct NotificationsService: NotificationsServicing {
    let client: RequestsAPIClient
    let currentUserProvider: @Sendable () async -> User?

    func unreadCountUpdates() -> AsyncThrowingStream<UnreadCounts, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let user = await currentUserProvider() else { throw RequestsAPIError.notSignedIn }
                    let decoder = RequestsAPIClient.makeDecoder()
                    for try await payload in client.eventStream("/notifications/\(user.id)/requests/stream") {
                        if let counts = Self.decode(payload, decoder: decoder) {
                            continuation.yield(counts)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// An array of snapshots (use the newest, as the web does) or a single object.
    static func decode(_ payload: Data, decoder: JSONDecoder) -> UnreadCounts? {
        if let snapshots = try? decoder.decode([UnreadCounts].self, from: payload) {
            return snapshots.last
        }
        return try? decoder.decode(UnreadCounts.self, from: payload)
    }
}

// MARK: - Polling

/// Keeps the unread-count stream open, but only while BlueRequests is an available space
/// AND the app is in the foreground — `CAIApp` drives that through
/// `update(isRequestsAvailable:isAppActive:)`, so a personal-only user (or the flag off)
/// never sends a single request to trm-gw. When the stream ends or fails it reconnects
/// after `interval`.
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

    /// Starts or stops the stream to match the current state. Idempotent — starting
    /// while already running doesn't reconnect, so repeated scene-phase or entitlement
    /// updates don't open extra streams. Losing the entitlement also clears `counts`, so
    /// no stale badge is left behind; merely backgrounding keeps them, so the badge
    /// doesn't flicker on return.
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
                do {
                    for try await counts in self.service.unreadCountUpdates() {
                        guard !Task.isCancelled else { return }
                        self.counts = counts
                    }
                } catch {}
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }
}
