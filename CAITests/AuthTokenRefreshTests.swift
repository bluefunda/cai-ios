import XCTest
@testable import CAI

// MARK: - Token Refresh Resilience Tests
// Guards the fix for cai-ios#151: a transient refresh failure (network error,
// momentary server issue) must not be treated the same as a genuinely dead
// refresh token (Keycloak invalid_grant) -- only the latter should end the
// session / clear the Keychain.

@MainActor
final class AuthTokenRefreshTests: XCTestCase {
    private class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = MockURLProtocol.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func seedStoredRefreshToken(_ token: String = "stored-refresh-token") {
        KeychainStore.saveAuthTokens(refreshToken: token, realm: "individual", expiresAt: nil)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        KeychainStore.clearAuthTokens()
        super.tearDown()
    }

    func test_restoreSession_transientNetworkFailure_doesNotClearKeychain() async {
        seedStoredRefreshToken()
        var callCount = 0
        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            throw URLError(.notConnectedToInternet)
        }

        let authManager = AuthManager(session: makeMockSession())
        await authManager.restoreSession()

        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertGreaterThan(callCount, 1, "expected internal retries on a transient failure")
        XCTAssertNotNil(KeychainStore.loadAuthTokens(), "stored refresh token must survive a transient failure")
    }

    func test_restoreSession_invalidGrant_clearsKeychain() async {
        seedStoredRefreshToken()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"error":"invalid_grant","error_description":"Token is not active"}"#.utf8))
        }

        let authManager = AuthManager(session: makeMockSession())
        await authManager.restoreSession()

        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(KeychainStore.loadAuthTokens(), "a confirmed-dead refresh token must clear the Keychain")
    }

    func test_restoreSession_succeedsAfterTransientFailureThenSuccess() async {
        seedStoredRefreshToken()
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                throw URLError(.timedOut)
            }
            let json = """
            {"access_token":"fresh-token","refresh_token":"new-refresh","expires_in":300,"token_type":"Bearer"}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json)
        }

        let authManager = AuthManager(session: makeMockSession())
        await authManager.restoreSession()

        XCTAssertTrue(authManager.isAuthenticated, "a retry succeeding should restore the session")
        XCTAssertEqual(authManager.accessToken, "fresh-token")
        XCTAssertEqual(callCount, 2, "expected exactly one retry before success")
    }

    func test_restoreSession_serverErrorWithoutInvalidGrantBody_treatedAsTransient() async {
        seedStoredRefreshToken()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("Internal Server Error".utf8))
        }

        let authManager = AuthManager(session: makeMockSession())
        await authManager.restoreSession()

        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNotNil(KeychainStore.loadAuthTokens(), "a 5xx with no invalid_grant body must not clear the Keychain")
    }

    func test_authError_refreshTokenInvalid_hasSessionExpiredMessage() {
        XCTAssertEqual(AuthError.refreshTokenInvalid.errorDescription, "Session expired. Please sign in again.")
    }
}
