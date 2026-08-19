import XCTest
@testable import CAI

// MARK: - Persona Catalog Tests
// Guards ChatManager.loadPersonas(): fetching cai-mcp-go's /personas catalog
// (via cai-bff), caching it to disk with a TTL so cold start never blocks on
// the network, and falling back gracefully when the fetch fails.

@MainActor
final class PersonaCatalogTests: XCTestCase {
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

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        UserDefaults.standard.removeObject(forKey: "cai_persona_catalog_cache_v1")
        UserDefaults.standard.removeObject(forKey: "cai_persona_catalog_cache_ts_v1")
        UserDefaults.standard.removeObject(forKey: "cai_persona")
        super.tearDown()
    }

    private func mockChatManager() -> ChatManager {
        let chatManager = ChatManager(service: MockChatService())
        chatManager.apiService = BFFAPIService(
            baseURL: "https://example.com",
            tokenProvider: { "test-token" },
            session: makeMockSession()
        )
        return chatManager
    }

    func test_loadPersonas_populatesCatalogFromBackend_sortedByOrder() async {
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.hasSuffix("/personas") ?? false)
            let json = """
            {"personas": [
                {"id": "leader", "wireValue": "leader", "label": "Leader", "shortLabel": "Leader", "detail": "d", "icon": "briefcase", "order": 2},
                {"id": "abap", "wireValue": "abap", "label": "ABAP Developer", "shortLabel": "ABAP", "detail": "d", "icon": "chevron", "order": 1}
            ], "success": true}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let chatManager = mockChatManager()
        await chatManager.loadPersonas()

        XCTAssertEqual(chatManager.availablePersonas.map(\.id), ["abap", "leader"], "should be sorted by order")
        XCTAssertEqual(PersonaCatalog.loadCached().map(\.id), ["abap", "leader"], "a successful fetch should update the disk cache")
    }

    /// Regression guard: cai-mcp-go's real personas.yaml includes a "general"
    /// entry (id: general, wire_value: "", detail: "No specific SAP focus")
    /// -- it's part of the actual backend catalog, not something the app can
    /// assume is absent. General is a UI sentinel reachable only by toggling
    /// persona mode off, so it must never show up as a pickable row.
    func test_loadPersonas_excludesGeneralFromTheFetchedCatalog() async {
        MockURLProtocol.requestHandler = { request in
            let json = """
            {"personas": [
                {"id": "general", "label": "General", "shortLabel": "General", "detail": "No specific SAP focus", "icon": "sparkles", "order": 0},
                {"id": "abap", "wireValue": "abap", "label": "ABAP Developer", "shortLabel": "ABAP", "detail": "d", "icon": "chevron", "order": 1}
            ], "success": true}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let chatManager = mockChatManager()
        await chatManager.loadPersonas()

        XCTAssertEqual(chatManager.availablePersonas.map(\.id), ["abap"], "general must be filtered out of the selectable catalog")
        XCTAssertFalse(PersonaCatalog.loadCached().contains(where: { $0.id == "general" }), "general must not be persisted to the disk cache either")
    }

    func test_loadPersonas_skipsNetworkCall_whenCacheIsFresh() async {
        PersonaCatalog.store([.fi])
        var requestMade = false
        MockURLProtocol.requestHandler = { request in
            requestMade = true
            throw URLError(.badURL)
        }

        let chatManager = mockChatManager()
        chatManager.availablePersonas = PersonaCatalog.loadCached()
        await chatManager.loadPersonas()

        XCTAssertFalse(requestMade, "a fresh cache should short-circuit the network fetch entirely")
        XCTAssertEqual(chatManager.availablePersonas, [.fi])
    }

    func test_loadPersonas_onFailure_keepsWhateverWasAlreadyLoaded() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        let chatManager = mockChatManager()
        chatManager.availablePersonas = [.basis]
        await chatManager.loadPersonas()

        XCTAssertEqual(chatManager.availablePersonas, [.basis], "a failed refresh must not wipe out the existing catalog")
    }

    func test_loadPersonas_dropsStaleDefaultPersona_ifRetiredServerSide() async {
        UserDefaults.standard.set("fi-ca", forKey: "cai_persona")
        MockURLProtocol.requestHandler = { request in
            let json = #"{"personas": [{"id": "fi", "wireValue": "fi", "label": "FI", "shortLabel": "FI", "detail": "d", "icon": "i", "order": 1}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let chatManager = mockChatManager()
        XCTAssertEqual(chatManager.persona.id, "fi-ca")

        await chatManager.loadPersonas()

        XCTAssertEqual(chatManager.persona, .general, "a persona retired server-side should fall back to General rather than silently keep sending a dead id")
    }

    func test_resolve_findsWellKnownPersonasWithoutALiveCatalog() {
        XCTAssertEqual(Persona.resolve("is-u"), .isU)
        XCTAssertEqual(Persona.resolve("general"), .general)
        XCTAssertNil(Persona.resolve("not-a-real-persona"))
    }

    func test_loadCached_fallsBackToHardcodedCatalog_whenNothingCachedYet() {
        XCTAssertEqual(PersonaCatalog.loadCached(), Persona.fallbackCatalog)
    }

    /// Regression guard for the "still see General after updating" report:
    /// simulates an on-disk cache written by a build that predates the
    /// general-filtering fix (i.e. written directly, bypassing
    /// PersonaCatalog.store, which already excludes it) -- loadCached() must
    /// sanitize it on read rather than requiring a cache-clear or a 24h wait
    /// for the TTL to force a re-fetch.
    func test_loadCached_sanitizesAPreExistingCacheThatIncludesGeneral() {
        let poisoned = [Persona.general, .abap, .fi]
        UserDefaults.standard.set(try! JSONEncoder().encode(poisoned), forKey: "cai_persona_catalog_cache_v1")

        XCTAssertEqual(PersonaCatalog.loadCached().map(\.id), ["abap", "fi"])
    }
}
