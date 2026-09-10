import XCTest
import CryptoKit
@testable import CAI

// MARK: - Tip Engine Phase 2 Tests (bluefunda/cai-ios#157)
// Guards manifest decode/filter behavior and Ed25519 signature verification
// against tip-catalog's actual sign/verify semantics (raw file bytes, not a
// re-serialization or hash).

final class TipCatalogTests: XCTestCase {
    private let validEntryJSON = """
    [{
        "id": "test-tip", "family": "onboarding", "surfaces": ["ios"],
        "domain_scope": ["onboarding"], "min_tier": "free", "cooldown": "24h",
        "render": {"ios": {"title": "Hi", "body": "Welcome"}},
        "embedding": [0,0,0,0,0,0,0,0,0,0,0,0,0,1,0], "catalog_version": "1"
    }]
    """

    private let cliOnlyEntryJSON = """
    [{
        "id": "cli-tip", "family": "cli-basics", "surfaces": ["cli"],
        "render": {"cli": {"title": "Hi", "body": "Welcome"}},
        "embedding": [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0], "catalog_version": "1"
    }]
    """

    func test_decode_validEntry_succeeds() throws {
        let data = Data(validEntryJSON.utf8)
        let entries = try JSONDecoder().decode([TipManifestEntry].self, from: data)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "test-tip")
        XCTAssertEqual(entries[0].render.ios?.title, "Hi")
    }

    func test_filter_excludesEntriesWithoutIOSSurface() throws {
        // cliOnlyEntryJSON's render has no "ios" key at all, but our
        // TipRender only ever decodes an "ios" field, so this still
        // decodes — supportsIOS is what actually excludes it.
        let data = Data(cliOnlyEntryJSON.utf8)
        let entries = try JSONDecoder().decode([TipManifestEntry].self, from: data)
        XCTAssertFalse(entries[0].supportsIOS)
        XCTAssertTrue(entries.filter { $0.supportsIOS }.isEmpty)
    }

    func test_decode_corruptedManifest_throwsRatherThanCrashing() {
        let corrupted = Data("{not valid json".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([TipManifestEntry].self, from: corrupted))
    }

    // MARK: Signature verification (real Ed25519 round-trip, test keypair)

    func test_verify_validSignature_succeeds() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = Data(validEntryJSON.utf8)
        let signature = try key.signature(for: data)
        let ok = try TipCatalog.verify(
            data: data,
            signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()
        )
        XCTAssertTrue(ok)
    }

    func test_verify_tamperedData_fails() throws {
        let key = Curve25519.Signing.PrivateKey()
        let original = Data(validEntryJSON.utf8)
        let signature = try key.signature(for: original)
        let tampered = Data((validEntryJSON + " ").utf8)
        let ok = try TipCatalog.verify(
            data: tampered,
            signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()
        )
        XCTAssertFalse(ok)
    }

    func test_verify_wrongKey_fails() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let otherKey = Curve25519.Signing.PrivateKey()
        let data = Data(validEntryJSON.utf8)
        let signature = try signingKey.signature(for: data)
        let ok = try TipCatalog.verify(
            data: data,
            signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: otherKey.publicKey.rawRepresentation.base64EncodedString()
        )
        XCTAssertFalse(ok)
    }

    // MARK: Fallback never crashes

    func test_init_neverCrashesEvenWithoutABundledSnapshot() {
        // The test runner's own bundle has no catalog_snapshot.json, so
        // this exercises the "bundled snapshot missing/unreadable" path —
        // it must degrade to an empty catalog, not throw or crash, matching
        // "never blocks app launch".
        let catalog = TipCatalog(bundle: Bundle(for: TipCatalogTests.self))
        XCTAssertNotNil(catalog.entries)
    }
}
