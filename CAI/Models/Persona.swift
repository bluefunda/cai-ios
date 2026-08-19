import Foundation

/// The user's SAP specialty, sent as chat context so responses use the right
/// terminology and depth (bluefunda/cai-ios#177). Additive to the existing
/// `agentName`-based routing (e.g. "abaper") rather than a replacement for
/// it — there's no BASIS/FI/IS-U/Leader agent on the backend yet, so this is
/// a separate, backend-optional field the router can pick up when ready.
///
/// The catalog itself is backend-driven (cai-mcp-go's persona display
/// catalog, served via `GET /personas`, see `ChatManager.loadPersonas()`)
/// rather than a hardcoded case list, so new personas can ship without an
/// app update. `fallbackCatalog` below is only the offline/cold-start
/// default — see `PersonaCatalog` for the disk cache that makes it
/// instantly available at launch.
struct Persona: Identifiable, Equatable, Codable {
    let id: String
    /// The identifier sent to the backend (bluefunda/cai-bff#110). `.general`
    /// has no wire representation — cai-bff/cai-llm-router treat an absent
    /// persona as "no persona lens", the same behavior `.general` means
    /// locally, so it's nil rather than sent as the literal string "general"
    /// (which cai-bff's persona allowlist doesn't recognize).
    let wireValue: String?
    let label: String
    /// Short form for compact UI (the composer chip, bluefunda/cai-ios#204).
    let shortLabel: String
    let detail: String
    let icon: String
    /// Display order in pickers/menus, as served by the backend catalog.
    var order: Int = 0

    /// Back-compat alias for `id` — the old `Persona` enum was
    /// `RawRepresentable` over this same identifier string, and a lot of
    /// call sites (local `ChatMessage.persona` storage, tests) still read it
    /// as `rawValue`.
    var rawValue: String { id }
}

extension Persona {
    /// Client-only sentinel meaning "no SAP focus" — never served by the
    /// backend catalog (cai-bff's persona allowlist has no "general" entry;
    /// see `wireValue`), so it's declared here rather than fetched.
    static let general = Persona(
        id: "general", wireValue: nil, label: "General", shortLabel: "General",
        detail: "No specific SAP focus", icon: "sparkles", order: 0
    )

    /// Hardcoded snapshot of the backend persona catalog, used only as the
    /// cold-start/offline default before the first successful fetch — see
    /// `PersonaCatalog.loadCached()`. Keep in sync with cai-mcp-go's
    /// `src/config/personas.yaml` on a best-effort basis; it does not need
    /// to be exact since the backend is always the source of truth once
    /// reachable.
    static let fallbackCatalog: [Persona] = [
        Persona(id: "abap", wireValue: "abap", label: "ABAP Developer", shortLabel: "ABAP",
                detail: "Custom development, dumps, and code review",
                icon: "chevron.left.forwardslash.chevron.right", order: 1),
        Persona(id: "basis", wireValue: "basis", label: "BASIS Admin", shortLabel: "BASIS",
                detail: "System administration and technical operations",
                icon: "server.rack", order: 2),
        Persona(id: "fi", wireValue: "fi", label: "FI Consultant", shortLabel: "FI",
                detail: "Financial Accounting",
                icon: "dollarsign.circle", order: 3),
        Persona(id: "fi-ca", wireValue: "fi-ca", label: "FI-CA Consultant", shortLabel: "FI-CA",
                detail: "Contract Accounting (utilities/telecom billing)",
                icon: "doc.text.magnifyingglass", order: 4),
        Persona(id: "is-u", wireValue: "is-u", label: "IS-U Consultant", shortLabel: "IS-U",
                detail: "Utilities industry solution",
                icon: "bolt.fill", order: 5),
        Persona(id: "leader", wireValue: "leader", label: "Leader / SI Founder", shortLabel: "Leader",
                detail: "Engagement scoping and client delivery",
                icon: "briefcase", order: 6)
    ]

    static let abap = fallbackCatalog.first { $0.id == "abap" }!
    static let basis = fallbackCatalog.first { $0.id == "basis" }!
    static let fi = fallbackCatalog.first { $0.id == "fi" }!
    static let fiCA = fallbackCatalog.first { $0.id == "fi-ca" }!
    static let isU = fallbackCatalog.first { $0.id == "is-u" }!
    static let leader = fallbackCatalog.first { $0.id == "leader" }!

    /// Resolves a stored/wire identifier string (e.g. from `ChatMessage.persona`
    /// or the `cai_persona` UserDefaults key) against a live catalog, falling
    /// back to `fallbackCatalog` and finally `.general` so a persona badge or
    /// default can always be shown even before the network catalog has loaded.
    static func resolve(_ raw: String, in catalog: [Persona] = []) -> Persona? {
        if raw == general.id { return general }
        if let match = catalog.first(where: { $0.id == raw }) { return match }
        return fallbackCatalog.first { $0.id == raw }
    }
}

// MARK: - Persona Catalog Cache

/// Disk cache for the backend persona catalog (bluefunda/cai-ios#242-ish:
/// replace the hardcoded persona enum with cai-mcp-go's `/personas` API).
/// Best practice for a reference/display catalog like this: never block UI
/// on the network fetch — load the cached (or fallback) list synchronously
/// so it's available instantly at cold start, then refresh in the background
/// against a TTL (stale-while-revalidate). See `ChatManager.loadPersonas()`.
enum PersonaCatalog {
    private static let cacheKey = "cai_persona_catalog_cache_v1"
    private static let cacheTimestampKey = "cai_persona_catalog_cache_ts_v1"
    private static let ttl: TimeInterval = 24 * 60 * 60

    /// Synchronous and instant — safe to call from a `@Published` property
    /// initializer, before any network call could possibly have completed.
    static func loadCached() -> [Persona] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([Persona].self, from: data),
              !decoded.isEmpty else {
            return Persona.fallbackCatalog
        }
        return decoded
    }

    static var isStale: Bool {
        let last = UserDefaults.standard.double(forKey: cacheTimestampKey)
        return Date().timeIntervalSince1970 - last > ttl
    }

    static func store(_ personas: [Persona]) {
        guard let data = try? JSONEncoder().encode(personas) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
    }
}
