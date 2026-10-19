import XCTest
@testable import CAI

// MARK: - Requests API Client Tests
// Guards P11 of docs/BLUEREQUESTS_INTEGRATION.md: a 401/403 from trm-gw is a
// non-fatal "BlueRequests unavailable", never a sign-out of chat — plus the
// header contract trm-gw / trm-backend-go rely on.

@MainActor
final class RequestsAPIClientTests: XCTestCase {
    private class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        static var lastRequest: URLRequest?

        /// Only intercepts BlueRequests traffic, so registering globally (needed for
        /// the RequestsServices test, which uses URLSession.shared) can't swallow
        /// anything else.
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.absoluteString.hasPrefix(AppConfig.requestsBaseURL) ?? false
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            MockURLProtocol.lastRequest = request
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

    private func makeClient() -> RequestsAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return RequestsAPIClient(
            baseURL: AppConfig.requestsBaseURL,
            tokenProvider: { "test-token" },
            session: URLSession(configuration: config)
        )
    }

    private func respond(status: Int, body: String = "") {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.lastRequest = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func test_sendsBearerAndAccessTokenHeaders_andNoRealmHeader() async throws {
        respond(status: 200, body: #"{"releases":[]}"#)

        let _: ReleaseListResponse = try await makeClient().get("/rest/trm/v1/release")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Access-Token"), "test-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Realm"))
        XCTAssertEqual(request.url?.absoluteString, "https://api.bluefunda.com/requests/rest/trm/v1/release")
    }

    func test_401And403_mapToRequestsUnavailable() async {
        for status in [401, 403] {
            respond(status: status, body: #"{"error":"forbidden"}"#)
            do {
                let _: ReleaseListResponse = try await makeClient().get("/rest/trm/v1/release")
                XCTFail("Expected a throw for HTTP \(status)")
            } catch RequestsAPIError.requestsUnavailable(let code) {
                XCTAssertEqual(code, status)
            } catch {
                XCTFail("Expected requestsUnavailable for HTTP \(status), got \(error)")
            }
        }
    }

    func test_blankBody_decodesAsEmptyList() async throws {
        respond(status: 200, body: "  ")
        let response: ReleaseListResponse = try await makeClient().get("/rest/trm/v1/release")
        XCTAssertTrue(response.releases.isEmpty)
    }

    #if DEBUG
    /// End to end through RequestsServices with a signed-in AuthManager: a trm-gw
    /// 401 must leave the chat session intact.
    func test_requests401_doesNotEndChatSession() async {
        let authManager = AuthManager()
        authManager.seedForScreenshots(
            user: User(id: "u-1", email: "a@example.com", name: "A", roles: [], organizations: ["trm"]),
            accessToken: "live-token"
        )
        URLProtocol.registerClass(MockURLProtocol.self)
        respond(status: 401)
        let services = RequestsServices(authManager: authManager, useFixtures: false)

        do {
            _ = try await services.changeRequestService.listChangeRequests(filter: ChangeRequestFilter())
            XCTFail("Expected requestsUnavailable")
        } catch RequestsAPIError.requestsUnavailable(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Expected requestsUnavailable, got \(error)")
        }

        XCTAssertTrue(authManager.isAuthenticated)
        XCTAssertNotNil(authManager.currentUser)
        XCTAssertEqual(authManager.accessToken, "live-token")
        XCTAssertNil(authManager.error)
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Access-Token"), "live-token")
    }
    #endif
}

// MARK: - Unread Poller Gating

@MainActor
final class UnreadCountPollerTests: XCTestCase {
    func test_pollsOnlyWhenRequestsAvailableAndAppActive() {
        let poller = UnreadCountPoller(service: FixtureNotificationsService(), interval: 3600)

        poller.update(isRequestsAvailable: false, isAppActive: true)
        XCTAssertFalse(poller.isPolling)
        poller.update(isRequestsAvailable: true, isAppActive: false)
        XCTAssertFalse(poller.isPolling)
        poller.update(isRequestsAvailable: true, isAppActive: true)
        XCTAssertTrue(poller.isPolling)
        poller.update(isRequestsAvailable: true, isAppActive: false)
        XCTAssertFalse(poller.isPolling)
    }

    func test_losingEntitlementClearsCounts_backgroundingKeepsThem() async throws {
        let poller = UnreadCountPoller(service: FixtureNotificationsService(), interval: 3600)
        poller.update(isRequestsAvailable: true, isAppActive: true)
        for _ in 0..<50 where poller.counts == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(poller.counts?.totalUnreadMessages, 2)

        poller.update(isRequestsAvailable: true, isAppActive: false)
        XCTAssertNotNil(poller.counts)

        poller.update(isRequestsAvailable: false, isAppActive: false)
        XCTAssertNil(poller.counts)
    }
}
