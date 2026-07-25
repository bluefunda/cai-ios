import Foundation

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .serverError(let code, let message):
            return "Server error \(code): \(message)"
        case .decodingError(let err):
            return "Failed to parse response: \(err.localizedDescription)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        }
    }
}

// MARK: - Token Provider

/// Closure that returns a valid access token, refreshing if needed.
/// Must be @Sendable so it can be called safely from background URLSession tasks.
typealias TokenProvider = @Sendable () async throws -> String

// MARK: - API Client

/// Lightweight URLSession wrapper that injects auth and decodes JSON.
struct APIClient {
    let baseURL: String
    let tokenProvider: TokenProvider
    let session: URLSession

    init(baseURL: String, tokenProvider: @escaping TokenProvider, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - GET

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let request = try await buildRequest(method: "GET", path: path, queryItems: queryItems)
        return try await perform(request)
    }

    // MARK: - POST

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let bodyData = try JSONEncoder().encode(body)
        let request = try await buildRequest(method: "POST", path: path, body: bodyData)
        return try await perform(request)
    }

    func postIgnoringResponse(_ path: String, body: [String: Any] = [:]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let request = try await buildRequest(method: "POST", path: path, body: bodyData)
        let (data, response) = try await session.data(for: request)
        try validateStatus(response, data: data)
    }

    func putIgnoringResponse(_ path: String, body: [String: Any] = [:]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let request = try await buildRequest(method: "PUT", path: path, body: bodyData)
        let (data, response) = try await session.data(for: request)
        try validateStatus(response, data: data)
    }

    func deleteIgnoringResponse(_ path: String, queryItems: [URLQueryItem] = []) async throws {
        let request = try await buildRequest(method: "DELETE", path: path, queryItems: queryItems)
        let (data, response) = try await session.data(for: request)
        try validateStatus(response, data: data)
    }

    // MARK: - Multipart Upload

    func uploadMultipart(
        _ path: String,
        data fileData: Data,
        filename: String,
        mimeType: String,
        fields: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        includeAccessTokenHeader: Bool = false
    ) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        let token = try await tokenProvider()

        var components = URLComponents(string: baseURL + path)
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // trm-s3 (behind /fileupload) checks this header directly for the
        // per-user JWT, independent of the standard Authorization header the
        // gateway needs for its own service-to-service auth on this route.
        if includeAccessTokenHeader {
            request.setValue(token, forHTTPHeaderField: "Access-Token")
        }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

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

        let (responseData, response) = try await session.data(for: request)
        try validateStatus(response, data: responseData)
        return responseData
    }

    // MARK: - Private

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
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = body
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        try validateStatus(response, data: data)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func validateStatus(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { return }

        if http.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let message: String
            // Try to parse structured error message
            if let data, let dto = try? JSONDecoder().decode(APIErrorDTOLocal.self, from: data),
               let msg = dto.message ?? dto.error, !msg.isEmpty {
                message = msg
            } else {
                message = body.isEmpty ? "HTTP \(http.statusCode)" : String(body.prefix(200))
            }
            throw APIError.serverError(http.statusCode, message)
        }
    }
}

// Local copy to avoid cross-file dependency in the utility layer
private struct APIErrorDTOLocal: Decodable {
    let error: String?
    let message: String?
}
