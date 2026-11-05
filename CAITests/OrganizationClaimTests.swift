import XCTest
@testable import CAI

// MARK: - Organization Claim Tests
// Keycloak's `organization` claim arrives as a string, an array, or an object keyed
// by org alias (when the org mapper includes attributes/IDs). BlueRequests
// entitlement depends on seeing every alias, while `User.organization` must keep
// mirroring cai-bff's "first entry wins" (bluefunda/cai-bff#166).

final class OrganizationClaimTests: XCTestCase {
    func test_stringClaim_yieldsSingleOrg() {
        let claims: [String: Any] = ["organization": "trm"]
        XCTAssertEqual(AuthManager.organizations(from: claims), ["trm"])
        XCTAssertEqual(AuthManager.firstOrganization(from: claims), "trm")
    }

    func test_arrayClaim_keepsOrderAndFirstWins() {
        let claims: [String: Any] = ["organization": ["acme", "trm"]]
        XCTAssertEqual(AuthManager.organizations(from: claims), ["acme", "trm"])
        XCTAssertEqual(AuthManager.firstOrganization(from: claims), "acme")
    }

    func test_objectClaim_usesAliasKeysSorted() {
        let claims: [String: Any] = [
            "organization": [
                "trm": ["id": "6f1c…"],
                "acme": ["id": "0a2b…"]
            ]
        ]
        XCTAssertEqual(AuthManager.organizations(from: claims), ["acme", "trm"])
        XCTAssertEqual(AuthManager.firstOrganization(from: claims), "acme")
    }

    func test_objectClaim_decodedFromJSON() throws {
        let json = Data(#"{"organization":{"trm":{"id":"abc","name":"TRM"}}}"#.utf8)
        let claims = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(AuthManager.organizations(from: claims), ["trm"])
    }

    func test_missingOrEmptyClaim_yieldsNoOrgs() {
        XCTAssertEqual(AuthManager.organizations(from: [:]), [])
        XCTAssertEqual(AuthManager.organizations(from: ["organization": ""]), [])
        XCTAssertEqual(AuthManager.organizations(from: ["organization": [String]()]), [])
        XCTAssertNil(AuthManager.firstOrganization(from: [:]))
    }

    func test_blankAndNonStringEntries_areDropped() {
        let claims: [String: Any] = ["organization": [" trm ", "", 42] as [Any]]
        XCTAssertEqual(AuthManager.organizations(from: claims), ["trm"])
    }

    func test_userOrganization_isFirstOfOrganizations() {
        let user = User(id: "u", email: "", name: "", roles: [], organizations: ["acme", "trm"])
        XCTAssertEqual(user.organization, "acme")
        XCTAssertNil(User(id: "u", email: "", name: "", roles: []).organization)
    }

    func test_requestsRoles_comeFromAdminTrmClientOnly() {
        let claims: [String: Any] = [
            "realm_access": ["roles": ["admin"]],
            "resource_access": [
                "admin-trm": ["roles": ["release-manager", "default-roles-trm"]],
                "account": ["roles": ["admin"]]
            ]
        ]
        XCTAssertEqual(AuthManager.requestsRoles(from: claims), ["release-manager", "default-roles-trm"])
        XCTAssertEqual(AuthManager.requestsRoles(from: ["realm_access": ["roles": ["admin"]]]), [])
    }
}
