import Foundation

/// Generic single-value async cache — shares one in-flight fetch across concurrent callers
/// and remembers the last successful result, only hitting the network again when
/// `forceRefresh` is passed (a deliberate pull-to-refresh) or nothing has been fetched yet.
///
/// Ported from trm-ios. Built to fix a concrete, live-confirmed problem: several GETs in this app (Projects,
/// Teams, the Create/Edit Change Request reference-data pickers) are fetched far more often
/// than the underlying data actually changes — e.g. visiting Project Detail right after the
/// Projects list re-ran the exact same heavy fetch a second time, which was measurably slow
/// and occasionally failed outright with `URLError.networkConnectionLost` (see
/// `ProjectService`'s own doc comment for the original incident this was extracted from).
actor AsyncCache<Value: Sendable> {
    private var cached: Value?
    private var inFlight: Task<Value, Error>?

    func fetch(forceRefresh: Bool, using fetcher: @Sendable @escaping () async throws -> Value) async throws -> Value {
        if forceRefresh {
            cached = nil
            inFlight = nil
        }
        if let cached { return cached }
        if let inFlight { return try await inFlight.value }

        let task = Task { try await fetcher() }
        inFlight = task
        do {
            let result = try await task.value
            cached = result
            inFlight = nil
            return result
        } catch {
            inFlight = nil
            throw error
        }
    }
}
