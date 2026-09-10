import Foundation

/// The caller-provided facts `TipSelector` needs but shouldn't own — kept
/// as plain values (not `Persona`/`IAPManager` references) so eligibility
/// stays a pure, independently unit-testable function per issue #158.
struct TipSelectionContext {
    /// `Persona.general.id` when in General mode.
    let personaId: String
    /// `!personaEnabled || persona == .general` — see the app's 2-way
    /// mapping of General/SAP-scoped onto the existing `Persona` system
    /// (there is no separate Auto/SAP/General enum).
    let isGeneralMode: Bool
    let hasActiveSubscription: Bool
    let now: Date

    init(personaId: String, isGeneralMode: Bool, hasActiveSubscription: Bool, now: Date = Date()) {
        self.personaId = personaId
        self.isGeneralMode = isGeneralMode
        self.hasActiveSubscription = hasActiveSubscription
        self.now = now
    }
}

/// Tip Engine Phase 3 (bluefunda/cai-ios#158) — three-stage selection:
/// eligibility, candidate scoring, ranking. Must stay synchronous and fast
/// (<5ms budget, verified manually via Instruments, not a unit test) with
/// zero network on this path — `entries` and `profile` are both already
/// in memory by the time this runs.
enum TipSelector {
    static func select(
        from entries: [TipManifestEntry],
        profile: [Double],
        antiAnnoyance: AntiAnnoyance,
        context: TipSelectionContext,
        ranker: TipRanker = RulesBasedTipRanker()
    ) -> TipManifestEntry? {
        let eligible = entries.filter { isEligible($0, context: context, antiAnnoyance: antiAnnoyance) }
        let candidates = eligible.map {
            TipCandidate(entry: $0, score: CosineSimilarity.score(profile, $0.embedding))
        }
        return ranker.rank(candidates, personaId: context.personaId)
    }

    /// Pure eligibility predicate — tier, cooldown/dismissal/retirement
    /// (via `antiAnnoyance`), persona gate, and the General/SAP-scoped
    /// safety boundary. No I/O, no mutation.
    static func isEligible(
        _ entry: TipManifestEntry,
        context: TipSelectionContext,
        antiAnnoyance: AntiAnnoyance
    ) -> Bool {
        if entry.minTier == "pro" && !context.hasActiveSubscription { return false }
        if !antiAnnoyance.isEligible(tipId: entry.id, family: entry.family, at: context.now) { return false }
        if isWithinCooldown(entry, antiAnnoyance: antiAnnoyance, now: context.now) { return false }
        if isBlockedByPersonaGate(entry, context: context) { return false }
        if context.isGeneralMode && isSAPScoped(entry) { return false }
        return true
    }

    /// Per-tip minimum re-show gap (distinct from `AntiAnnoyance`'s
    /// family-level dismissal backoff) — issue #158 explicitly lists
    /// "cooldown" as one of eligibility's five factors, but until now
    /// nothing read `entry.cooldown` at all, so a tip would re-show on
    /// every single selection with no minimum gap. Falls back to a 1h
    /// floor when the field is empty/unparseable, per tip-catalog's
    /// `CONTENT_GUIDE.md`: "a client falls back to a 1h floor if you leave
    /// it empty."
    private static let defaultCooldownFloor: TimeInterval = 3600

    private static func isWithinCooldown(_ entry: TipManifestEntry, antiAnnoyance: AntiAnnoyance, now: Date) -> Bool {
        guard let lastShown = antiAnnoyance.lastShown(tipId: entry.id) else { return false }
        let cooldown = entry.cooldown.flatMap(GoDuration.parse) ?? defaultCooldownFloor
        return now.timeIntervalSince(lastShown) < cooldown
    }

    // TODO(tip-catalog): tip.schema.json's `domain_scope` taxonomy is
    // app/tool-usage topics (mcp, worktree, model-selection, ...), not a
    // dedicated "this tip is SAP-specific" flag — so there is nothing yet
    // to gate on, and this is a no-op pass-through. Tighten once
    // tip-catalog adds an explicit SAP-scope signal; until then, General
    // mode is protected only in the sense that no tip *can* be flagged
    // SAP-scoped, not that any tip actively is.
    private static func isSAPScoped(_ entry: TipManifestEntry) -> Bool {
        false
    }

    /// tip.schema.json's own example value for `persona_gate` is
    /// `"new_user"` — a user-lifecycle segment, not a CAI `Persona` (SAP
    /// specialty). Found live: the one published tip is gated
    /// `"new_user"`, which never equals any `context.personaId`, so
    /// comparing them directly (as issue #158's text literally suggests)
    /// silently excludes every gated tip forever. Only enforce the gate
    /// when it names a persona this app actually has — an unrecognized
    /// segment like "new_user" isn't something the app tracks yet, so it
    /// passes through rather than permanently blocking real content.
    private static let knownPersonaIds: Set<String> = Set(Persona.fallbackCatalog.map(\.id)).union([Persona.general.id])

    private static func isBlockedByPersonaGate(_ entry: TipManifestEntry, context: TipSelectionContext) -> Bool {
        guard let gate = entry.personaGate, !gate.isEmpty, knownPersonaIds.contains(gate) else { return false }
        return gate != context.personaId
    }
}
