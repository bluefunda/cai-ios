import Foundation

// MARK: - Empty Response Handling
// A filter combination that legitimately matches zero rows can come back from trm-gw as a
// blank/whitespace body (or the literal string "null") instead of a well-formed empty
// envelope like `{"combinedResponse":[]}` — decoding that as JSON throws, which used to
// surface as a "Failed to parse response" alert for what is really just an empty result
// set. List response envelopes opt into this by conforming below; `perform` checks for it
// before ever handing an empty/null body to JSONDecoder.
protocol EmptyDecodableResponse {
    static var empty: Self { get }
}

private func isBlankOrNull(_ data: Data) -> Bool {
    guard let text = String(data: data, encoding: .utf8) else { return false }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed == "null"
}

// MARK: - Requests API Errors
// Deliberately separate from cai's own `APIError`: nothing here ever means "your
// session is over". A 401/403 from trm-gw means BlueRequests can't serve this
// token right now (backend not ready for `individual`-realm tokens, user not
// provisioned in the tenant, gateway misconfig) — it must never sign the user
// out of chat (docs/BLUEREQUESTS_INTEGRATION.md P11). Callers surface every case
// here as an inline, space-scoped error card with Retry.

enum RequestsAPIError: LocalizedError {
    case invalidURL
    /// No access token to send — the user isn't signed in (AuthManager owns
    /// what happens next; this client never touches the session).
    case notSignedIn
    /// trm-gw answered 401 or 403. Non-fatal by design, see above.
    case requestsUnavailable(statusCode: Int)
    case serverError(Int, String)
    case decodingError(Error, bodyPreview: String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .notSignedIn:
            return "Sign in to see your requests."
        case .requestsUnavailable:
            return "BlueRequests is unavailable right now. Try again in a moment."
        case .serverError(let code, let message):
            return "Server error \(code): \(message)"
        case .decodingError(let err, let bodyPreview):
            let detail = RequestsAPIError.decodingErrorDetail(err) ?? err.localizedDescription
            let body = bodyPreview.isEmpty ? "" : " — response starts: \(bodyPreview)"
            return "Failed to parse response: \(detail)\(body)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        }
    }

    /// A raw response-body preview only shows where the response *starts* — useless when
    /// the actual failure is some element deep inside a large array. DecodingError already
    /// carries the exact failing path (e.g. `combinedResponse[7].changeRequest.id`); surface
    /// that instead of guessing from truncated text.
    private static func decodingErrorDetail(_ error: Error) -> String? {
        guard let decodingError = error as? DecodingError else { return nil }

        func path(_ context: DecodingError.Context) -> String {
            let rendered = context.codingPath.map { key -> String in
                if let index = key.intValue { return "[\(index)]" }
                return ".\(key.stringValue)"
            }.joined()
            return rendered.isEmpty ? "<root>" : rendered
        }

        switch decodingError {
        case .typeMismatch(let type, let context):
            return "expected \(type) at \(path(context)) — \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "missing value for \(type) at \(path(context))"
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case .dataCorrupted(let context):
            return "corrupted data at \(path(context)) — \(context.debugDescription)"
        @unknown default:
            return nil
        }
    }
}

// MARK: - Request Gate
// ⚠️ Reinstated: originally removed to locally test bluefunda/trm-backend-go#116 (reported
// fixed and deployed), but with the gate removed, change-request fetches started failing
// consistently (not just intermittently) with URLError.networkConnectionLost — even a
// small, previously-reliable `limit: 5` fetch failed every time, which rules out response
// size/per-row-enrichment (trm#139) as the cause of *this* regression, since that theory
// predicts failures scaling with fetch size, not a small capped fetch failing consistently.
// That points back at concurrent-request contention against trm-backend-go — either #116
// isn't fully fixed, or this gate was incidentally also protecting against a second,
// separate concurrency issue (e.g. the unread-count poller's own concurrent calls). Original
// doc comment, for when it's safe to try removing this again:
//
// Workaround for a confirmed trm-backend-go bug: jwtMiddleware.go caches a per-tenant DB
// connection with a check-then-act race (RLock-check-RUnlock, then a separate
// dbConnect+Lock-write on a cache miss). Any two concurrent requests hitting a cold cache
// for the same realm — e.g. the unread-count poller's first tick landing at the same moment
// as a list screen's initial load, both firing right when the app becomes authenticated —
// can race dbConnect(realm) and fail with a plain-text 500 that upstream gateway layers
// strip the body from. This actor serializes every request through RequestsAPIClient app-wide —
// correctness over throughput until the race is fixed server-side.
private actor RequestGate {
    static let shared = RequestGate()

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Token Provider

/// Closure that returns a valid access token, refreshing if needed — backed by
/// cai's own `AuthManager.validAccessToken()` (see RequestsServices).
/// Must be @Sendable so it can be called safely from background URLSession tasks.
typealias RequestsTokenProvider = @Sendable () async throws -> String

// MARK: - Requests API Client

/// Lightweight URLSession wrapper for trm-gw that injects auth and decodes JSON.
/// Ported from trm-ios's APIClient, keeping its request gate, retry/backoff and
/// empty-body handling — see the comments on each for the backend issues they
/// work around.
struct RequestsAPIClient {
    let baseURL: String
    let tokenProvider: RequestsTokenProvider
    let session: URLSession

    init(baseURL: String, tokenProvider: @escaping RequestsTokenProvider, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - GET

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let request = try await buildRequest(method: "GET", path: path, queryItems: queryItems)
        return try await performWithRetry(request)
    }

    // MARK: - POST

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let bodyData = try JSONEncoder().encode(body)
        let request = try await buildRequest(method: "POST", path: path, body: bodyData)
        return try await perform(request)
    }

    /// For POSTs whose response shape isn't confirmed (no OpenAPI spec) — validates the
    /// status code and discards the body rather than guess-decoding it.
    func postDiscardingResponse(_ path: String, body: some Encodable) async throws {
        let bodyData = try JSONEncoder().encode(body)
        let request = try await buildRequest(method: "POST", path: path, body: bodyData)
        let (data, response) = try await gatedRequest(request)
        try validateStatus(response, data: data)
    }

    // MARK: - PUT

    /// For PUTs whose response shape isn't confirmed (no OpenAPI spec) — validates the
    /// status code and discards the body rather than guess-decoding it.
    func putDiscardingResponse(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        body: some Encodable
    ) async throws {
        let bodyData = try JSONEncoder().encode(body)
        let request = try await buildRequest(method: "PUT", path: path, queryItems: queryItems, body: bodyData)
        let (data, response) = try await gatedRequest(request)
        try validateStatus(response, data: data)
    }

    // MARK: - Multipart Upload
    // trm-s3 (behind /fileupload) checks the Access-Token header directly for the per-user
    // JWT, independent of the standard Authorization header the gateway needs for its own
    // service-to-service auth on this route. The two trm-ios callers (AttachmentService,
    // CRFileService) both pass `includeAccessTokenHeader: false` — kept as trm-ios has it.
    func uploadMultipart(
        _ path: String,
        data fileData: Data,
        filename: String,
        mimeType: String,
        fields: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        includeAccessTokenHeader: Bool = true
    ) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        let token = try await tokenProvider()

        var components = URLComponents(string: baseURL + path)
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw RequestsAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if includeAccessTokenHeader {
            request.setValue(token, forHTTPHeaderField: "Access-Token")
        }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = AppConfig.requestsRequestTimeout

        var body = Data()
        let append: (String) -> Void = { body.append($0.data(using: .utf8)!) }

        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (responseData, response) = try await gatedRequest(request)
        try validateStatus(response, data: responseData)
        return responseData
    }

    // MARK: - Private

    private func gatedRequest(_ request: URLRequest, useFreshConnection: Bool = false) async throws -> (Data, URLResponse) {
        await RequestGate.shared.acquire()
        defer { Task { await RequestGate.shared.release() } }
        let activeSession = useFreshConnection ? Self.freshConnectionSession() : session
        return try await Self.dataTask(activeSession, request)
    }

    /// A throwaway ephemeral session — its own empty connection pool, no shared cache/cookies
    /// — used only for retry attempts after the first. Live-confirmed 2026-09-09: a GET can
    /// fail with `URLError.networkConnectionLost` mid-transfer (a partial read — e.g. 1589 of
    /// 4661 bytes — followed by a POSIX socket reset, not a timeout or empty response), then
    /// fail identically on every retry against the same small, otherwise-healthy endpoint.
    /// That pattern is consistent with a single bad kept-alive connection sitting in the
    /// shared session's pool getting handed back out on each retry, rather than the kind of
    /// one-off transient blip retries are meant to ride out. A fresh ephemeral session can't
    /// reuse that connection since it starts with no pool at all.
    private static func freshConnectionSession() -> URLSession {
        URLSession(configuration: .ephemeral)
    }

    /// Deliberately NOT `session.data(for:)` — confirmed via a direct curl repro (identical
    /// token, identical request) that trm-gw returns the complete, valid ~200KB+ JSON body
    /// for the change-requests list in ~1s with no issue, while the app truncated the exact
    /// same response. That points at a bug in Swift's async `URLSession.data(for:)` bridging
    /// on this platform for larger HTTP/2 bodies, not the server. The older
    /// completion-handler-based `dataTask` doesn't share that bridging path.
    private static func dataTask(_ session: URLSession, _ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: RequestsAPIError.networkError(
                        URLError(.badServerResponse)
                    ))
                }
            }
            task.resume()
        }
    }

    private func buildRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> URLRequest {
        let token = try await tokenProvider()

        var components = URLComponents(string: baseURL + path)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw RequestsAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        // trm-gw (KrakenD) validates the Authorization bearer; trm-backend-go's
        // jwtMiddleware reads Access-Token first and only falls back to
        // Authorization — send both so either hop works. No X-Realm: the tenant
        // comes from the token's `organization` claim server-side.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "Access-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // trm-backend-go's change-request list enriches every row with several separate
        // per-field DB lookups (severity/type/project/timeline) and only paginates if
        // limit/offset are passed — an unfiltered call can be genuinely slow server-side.
        request.timeoutInterval = AppConfig.requestsRequestTimeout
        request.httpBody = body
        return request
    }

    /// Retries idempotent GET requests on transient transport failures — connection lost,
    /// timeout, host unreachable — NOT on decode errors or HTTP error statuses, which are
    /// real responses rather than transport hiccups. Originally needed because of two
    /// backend issues (bluefunda/trm-backend-go#116/#117): trm-backend-go's connection
    /// could be intermittently interrupted mid-response under load, surfacing as
    /// URLError.networkConnectionLost. #116 was reported fixed and deployed, but removing
    /// `gatedRequest`'s `RequestGate` serialization to test that live made failures *worse*
    /// (consistent, not intermittent) — see that gate's doc comment — so it's reinstated and
    /// #116 shouldn't be considered fully resolved client-side yet. #117 is separately still
    /// open. A short retry masks most of these from the user without waiting on the
    /// server-side fix. Scoped to GET only — POST/PUT aren't retried here since the backend
    /// has no idempotency-key support, and a retried mutation whose original request
    /// actually reached the server risks a duplicate side effect.
    private func performWithRetry<T: Decodable>(
        _ request: URLRequest, maxAttempts: Int = AppConfig.requestsMaxAttempts
    ) async throws -> T {
        var lastError: Error = RequestsAPIError.networkError(URLError(.unknown))
        for attempt in 1...maxAttempts {
            do {
                // First attempt reuses the shared session's connection pool as normal (fast
                // path); once something has already failed, subsequent attempts force a fresh
                // connection instead — see `freshConnectionSession`'s doc comment.
                return try await perform(request, useFreshConnection: attempt > 1)
            } catch let error as RequestsAPIError {
                guard Self.isRetryable(error) else { throw error }
                lastError = error
                if attempt < maxAttempts {
                    let backoff = AppConfig.requestsRetryBaseBackoff * Double(attempt)
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
            }
        }
        throw lastError
    }

    private static func isTransientTransportError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    /// Beyond transient transport errors, also retries a 5xx response whose body is
    /// completely empty — `validateStatus` sets `message` to the literal `"HTTP <code>"`
    /// only when the body was empty (a real error response always carries a JSON body here,
    /// per trm-backend-go's own error envelope). An empty-bodied 5xx is the exact signature
    /// this codebase already documented once for a confirmed backend/gateway bug (the
    /// per-tenant DB connection race behind `RequestGate`, bluefunda/trm-backend-go#116) —
    /// live-confirmed on 2026-09-07 to still occur even through `RequestGate`'s
    /// serialization, and on more than just the one route it was first found on
    /// (`/rest/trm/v1/projects` and the unrelated, minio-backed
    /// `/rest/trm/v1/listchangeRequestFile` both hit it, sharing nothing but this same
    /// direct-gateway `/rest/trm/v1/...` family) — so this is scoped to that exact empty-body
    /// signature rather than blindly retrying every 5xx, which could otherwise retry a real,
    /// meaningful server error.
    private static func isRetryable(_ error: RequestsAPIError) -> Bool {
        switch error {
        case .networkError(let underlying):
            return isTransientTransportError(underlying)
        case .serverError(let code, let message):
            return (500...599).contains(code) && message == "HTTP \(code)"
        default:
            return false
        }
    }

    private func perform<T: Decodable>(_ request: URLRequest, useFreshConnection: Bool = false) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await gatedRequest(request, useFreshConnection: useFreshConnection)
        } catch {
            #if DEBUG
            let urlError = error as? URLError
            print("[RequestsAPIClient] Transport failure for \(request.url?.absoluteString ?? "?"): "
                + "\(urlError?.code.rawValue ?? -1) \(urlError?.localizedDescription ?? error.localizedDescription)")
            #endif
            throw RequestsAPIError.networkError(error)
        }

        try validateStatus(response, data: data)

        if let emptyType = T.self as? EmptyDecodableResponse.Type, isBlankOrNull(data) {
            #if DEBUG
            // A blank body is indistinguishable here from "zero matches" vs. e.g. a
            // gateway timeout that stripped the body — this log is the only trace of
            // which one actually happened, since the UI shows both as an empty state.
            print("[RequestsAPIClient] Blank/null body for \(request.url?.absoluteString ?? "?") "
                + "— treating as empty result, not an error.")
            #endif
            return emptyType.empty as! T // swiftlint:disable:this force_cast — guarded by the as? cast just above
        }

        do {
            return try RequestsAPIClient.makeDecoder().decode(T.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8).map { String($0.prefix(600)) }
                ?? "<non-UTF8 body, \(data.count) bytes>"
            #if DEBUG
            // The on-screen alert can only show a short preview — a byte-level JSON
            // validity failure could be anywhere in a large array, so dump the full body
            // to disk for direct inspection (never in Release builds; this can contain
            // user data). Console print()/copy-paste kept losing the exact failure point.
            print("[RequestsAPIClient] Decode failed for \(request.url?.absoluteString ?? "?"): \(error)")
            print("[RequestsAPIClient] Full response body (\(data.count) bytes):")
            print(String(data: data, encoding: .utf8) ?? "<non-UTF8 body>")
            let dumpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("trm_decode_failure.json")
            try? data.write(to: dumpURL)
            print("[RequestsAPIClient] Full body also written to: \(dumpURL.path)")
            #endif
            throw RequestsAPIError.decodingError(error, bodyPreview: preview)
        }
    }

    /// trm-backend-go's exact date format is unconfirmed (see RequestsModels.swift) — ISO8601
    /// with fractional seconds, falling back to without, covers the common cases.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { valueDecoder in
            let container = try valueDecoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Date.fromISO8601(string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(string)"
            )
        }
        return decoder
    }

    private func validateStatus(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { return }

        // Never escalated to AuthManager.expireSession() — see RequestsAPIError.
        if http.statusCode == 401 || http.statusCode == 403 {
            throw RequestsAPIError.requestsUnavailable(statusCode: http.statusCode)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            #if DEBUG
            print("[RequestsAPIClient] HTTP \(http.statusCode) for \(response.url?.absoluteString ?? "?")")
            print("[RequestsAPIClient] Full error body (\(data?.count ?? 0) bytes): \(body)")
            #endif
            let message: String
            if let data, let dto = try? JSONDecoder().decode(RequestsErrorBody.self, from: data),
               let msg = dto.message ?? dto.error, !msg.isEmpty {
                message = msg
            } else {
                message = body.isEmpty ? "HTTP \(http.statusCode)" : String(body.prefix(200))
            }
            throw RequestsAPIError.serverError(http.statusCode, message)
        }
    }
}

/// trm-backend-go's error envelope.
private struct RequestsErrorBody: Decodable {
    let error: String?
    let message: String?
}
