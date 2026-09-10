import Foundation
import CryptoKit

enum TipCatalogError: Error {
    case network
    case badResponse
    case missingAssets
    case invalidSignature
    case decodeFailed
}

/// Fetches, verifies, and caches the shared tip manifest. Tip Engine
/// Phase 2 (bluefunda/cai-ios#157).
///
/// The manifest is distributed as GitHub Release assets on the public
/// `bluefunda/tip-catalog` repo (no auth required) rather than through any
/// bluefunda-operated backend — this is what lets tip content update
/// without an App Store review (issue #155's stated goal). Every fetch is
/// verified against the raw file bytes before decoding (matching
/// tip-catalog's own `ed25519.Verify(pub, data, sig)` — signing the literal
/// `catalog.json` bytes, not a re-serialization or a hash of it); any
/// failure anywhere in this path falls back to the bundled snapshot and
/// never blocks app launch.
final class TipCatalog {
    /// Ed25519 public key from tip-catalog's `pubkey.go`. Verifies
    /// `catalog.json` against `catalog.json.sig`.
    private static let publicKeyBase64 = "M1U752fzmcXdY+7L+NlNdsHBvVE4o/S41CuDiHPfyBA="
    private static let releaseAPIURL = URL(string: "https://api.github.com/repos/bluefunda/tip-catalog/releases/latest")!

    private let urlSession: URLSession
    private let bundle: Bundle

    /// Entries filtered to `surfaces` containing `"ios"`. Starts populated
    /// from the bundled snapshot so callers always have something, even
    /// before `refresh()` completes (or if it never succeeds).
    private(set) var entries: [TipManifestEntry]

    init(urlSession: URLSession = .shared, bundle: Bundle = .main) {
        self.urlSession = urlSession
        self.bundle = bundle
        self.entries = Self.loadBundledSnapshot(bundle: bundle)
    }

    /// Cold-start refresh, meant to be fired once (off the main actor) and
    /// awaited or not — callers don't need to block on this, since
    /// `entries` already has the bundled fallback. Atomically replaces
    /// `entries` only on complete success.
    func refresh() async {
        guard let fetched = try? await fetchAndVerify() else { return }
        entries = fetched.filter { $0.supportsIOS }
    }

    private func fetchAndVerify() async throws -> [TipManifestEntry] {
        let (release, releaseResponse) = try await urlSession.data(from: Self.releaseAPIURL)
        guard (releaseResponse as? HTTPURLResponse)?.statusCode == 200 else { throw TipCatalogError.badResponse }

        guard let json = try? JSONSerialization.jsonObject(with: release) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]],
              let catalogURLString = assets.first(where: { ($0["name"] as? String) == "catalog.json" })?["browser_download_url"] as? String,
              let sigURLString = assets.first(where: { ($0["name"] as? String) == "catalog.json.sig" })?["browser_download_url"] as? String,
              let catalogURL = URL(string: catalogURLString),
              let sigURL = URL(string: sigURLString) else {
            throw TipCatalogError.missingAssets
        }

        let (catalogData, catalogResponse) = try await urlSession.data(from: catalogURL)
        guard (catalogResponse as? HTTPURLResponse)?.statusCode == 200 else { throw TipCatalogError.badResponse }
        let (sigData, sigResponse) = try await urlSession.data(from: sigURL)
        guard (sigResponse as? HTTPURLResponse)?.statusCode == 200 else { throw TipCatalogError.badResponse }

        guard let sigText = String(data: sigData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              (try? Self.verify(data: catalogData, signatureBase64: sigText)) == true else {
            throw TipCatalogError.invalidSignature
        }

        guard let decoded = try? JSONDecoder().decode([TipManifestEntry].self, from: catalogData) else {
            throw TipCatalogError.decodeFailed
        }
        return decoded
    }

    /// Verifies `data` (the raw, undecoded `catalog.json` bytes) against a
    /// base64-encoded Ed25519 signature. `publicKeyBase64` defaults to the
    /// embedded production key; tests substitute their own keypair to
    /// exercise the real crypto path without depending on tip-catalog's
    /// actual private key.
    static func verify(data: Data, signatureBase64: String, publicKeyBase64: String = TipCatalog.publicKeyBase64) throws -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let signature = Data(base64Encoded: signatureBase64) else {
            return false
        }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        return key.isValidSignature(signature, for: data)
    }

    private static func loadBundledSnapshot(bundle: Bundle) -> [TipManifestEntry] {
        guard let url = bundle.url(forResource: "catalog_snapshot", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TipManifestEntry].self, from: data) else {
            return []
        }
        return decoded.filter { $0.supportsIOS }
    }
}
