import Foundation

/// Hand-transcribed Swift mirror of `bluefunda/tipcatalog`'s `Tip` struct
/// (tip.go) / `tip.schema.json`, as of catalog v1.1.0. There is no Go→Swift
/// codegen tooling in this repo (no SPM, no build plugins), so this is a
/// single manually-maintained source of truth rather than a generated
/// artifact — if `TipManifestEntry` and `tip-catalog`'s schema drift,
/// `TipCatalogTests` decoding a live-fetched manifest is the tripwire.
///
/// Scoped down to what the iOS client actually needs: only the `ios` render
/// slot is decoded (not `cli`/`vscode`/`adt`).
struct TipManifestEntry: Codable, Equatable {
    let id: String
    let family: String
    let surfaces: [String]
    /// Absent (`omitempty`) on many real tips — not `required` in
    /// tip.schema.json, unlike `embedding`/`surfaces`.
    let domainScope: [String]?
    let personaGate: String?
    let triggerConditions: [String]?
    let minTier: String?
    /// Go duration string (e.g. "24h") — this is the catalog's own
    /// re-show cooldown, separate from `AntiAnnoyance`'s dismissal backoff
    /// ladder. Parsed by `GoDuration.parse`.
    let cooldown: String?
    let render: TipRender
    let deepLink: String?
    /// Multi-hot vector over `TipTopic`'s ordering, one dimension per case.
    let embedding: [Double]
    let catalogVersion: String

    enum CodingKeys: String, CodingKey {
        case id, family, surfaces
        case domainScope = "domain_scope"
        case personaGate = "persona_gate"
        case triggerConditions = "trigger_conditions"
        case minTier = "min_tier"
        case cooldown, render
        case deepLink = "deep_link"
        case embedding
        case catalogVersion = "catalog_version"
    }

    /// Whether this entry declares the `ios` surface. Entries without it
    /// are dropped by `TipCatalog` before they ever reach a caller.
    var supportsIOS: Bool { surfaces.contains("ios") }
}

struct TipRender: Codable, Equatable {
    let ios: TipRenderContent?
}

struct TipRenderContent: Codable, Equatable {
    let title: String
    let body: String
}

/// Parses the subset of Go's `time.ParseDuration` format tip-catalog
/// actually emits for `cooldown` (h/m/s, optionally combined, e.g. "24h",
/// "1h30m").
enum GoDuration {
    static func parse(_ string: String) -> TimeInterval? {
        var remaining = Substring(string)
        var total: TimeInterval = 0
        var matchedAny = false
        let units: [(String, TimeInterval)] = [("h", 3600), ("m", 60), ("s", 1)]
        while !remaining.isEmpty {
            guard let digitsEnd = remaining.firstIndex(where: { !$0.isNumber && $0 != "." }) else {
                return nil
            }
            guard let value = Double(remaining[remaining.startIndex..<digitsEnd]) else { return nil }
            let afterDigits = remaining[digitsEnd...]
            guard let (unit, seconds) = units.first(where: { afterDigits.hasPrefix($0.0) }) else {
                return nil
            }
            total += value * seconds
            matchedAny = true
            remaining = afterDigits.dropFirst(unit.count)
        }
        return matchedAny ? total : nil
    }
}
