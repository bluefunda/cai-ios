import Foundation

/// One tip family's dismissal state. `stage` indexes
/// `AntiAnnoyance.backoffLadder`; once past the ladder's end the family is
/// permanently suppressed (`until == nil` combined with `stage >=
/// backoffLadder.count` reads as permanent — see `isSuppressed`).
struct FamilyDismissal: Codable, Equatable {
    var stage: Int
    var until: Date?
}

/// One tip's impression state, for the "shown 3x with no tap" retirement
/// rule — independent of its family's dismissal state, since a user can tap
/// some tips in a family while ignoring others.
struct TipImpression: Codable, Equatable {
    var shownCount: Int = 0
    var tapped: Bool = false
    /// Stamped by `recordShown` — lets `TipSelector` enforce each tip's own
    /// `cooldown` field (distinct from the family-level backoff ladder
    /// below).
    var lastShownAt: Date?
}

struct AntiAnnoyanceState: Codable, Equatable {
    var dismissals: [String: FamilyDismissal] = [:]
    var impressions: [String: TipImpression] = [:]
    var sessionShownCount: Int = 0
    var dayShownCount: Int = 0
    var dayWindowStart: Date = .distantPast
    /// Device-wide permanent opt-out (Settings toggle), independent of any
    /// per-family/per-tip state above.
    var optedOut: Bool = false
}

/// Tip Engine Phase 4 (bluefunda/cai-ios#159) — session/day caps, dismissal
/// backoff, and retirement. Core MVP functionality, integrated into
/// `TipSelector`'s eligibility stage rather than bolted on separately.
final class AntiAnnoyance {
    /// 24h → 72h → 14d, then permanent past the end of this list.
    static let backoffLadder: [TimeInterval] = [24 * 3600, 72 * 3600, 14 * 24 * 3600]
    static let maxPerSession = 1
    static let maxPerDay = 3
    static let retireAfterShownCount = 3
    private static let dayWindow: TimeInterval = 24 * 3600

    private let store: TipEngineFileStore<AntiAnnoyanceState>
    private(set) var state: AntiAnnoyanceState

    init(store: TipEngineFileStore<AntiAnnoyanceState> = TipEngineFileStore(filename: "anti_annoyance.json")) {
        self.store = store
        self.state = store.load() ?? AntiAnnoyanceState()
    }

    /// Call once per app session (e.g. on cold start) to reset the
    /// per-session counter. Day counter rolls over lazily based on
    /// elapsed wall-clock time, same "no timers" approach as
    /// `InterestProfile`'s decay.
    func startSession(at date: Date = Date()) {
        state.sessionShownCount = 0
        rollDayWindowIfNeeded(at: date)
        persist()
    }

    var isOptedOut: Bool { state.optedOut }

    func setOptedOut(_ value: Bool) {
        state.optedOut = value
        persist()
    }

    /// Whether `tipId` (in `family`) is currently eligible to be shown,
    /// independent of ranking. Pure given `state` — the eligibility stage
    /// in `TipSelector` calls this per candidate.
    func isEligible(tipId: String, family: String, at date: Date = Date()) -> Bool {
        if state.optedOut { return false }
        if state.sessionShownCount >= Self.maxPerSession { return false }
        if currentDayShownCount(at: date) >= Self.maxPerDay { return false }
        if isFamilySuppressed(family, at: date) { return false }
        if isRetired(tipId) { return false }
        return true
    }

    /// Records that `tipId` (in `family`) was shown — advances session/day
    /// counters and the per-tip impression count.
    func recordShown(tipId: String, family: String, at date: Date = Date()) {
        rollDayWindowIfNeeded(at: date)
        state.sessionShownCount += 1
        state.dayShownCount += 1
        var impression = state.impressions[tipId] ?? TipImpression()
        impression.shownCount += 1
        impression.lastShownAt = date
        state.impressions[tipId] = impression
        persist()
    }

    /// The last time `tipId` was shown, or nil if never — `TipSelector`
    /// compares this against the tip's own `cooldown` field.
    func lastShown(tipId: String) -> Date? {
        state.impressions[tipId]?.lastShownAt
    }

    func recordTapped(tipId: String) {
        var impression = state.impressions[tipId] ?? TipImpression()
        impression.tapped = true
        state.impressions[tipId] = impression
        persist()
    }

    /// Dismissing a tip suppresses its whole family, advancing one step
    /// down the backoff ladder each time (until permanent).
    func recordDismissed(family: String, at date: Date = Date()) {
        var dismissal = state.dismissals[family] ?? FamilyDismissal(stage: 0, until: nil)
        if dismissal.stage < Self.backoffLadder.count {
            dismissal.until = date.addingTimeInterval(Self.backoffLadder[dismissal.stage])
        } else {
            dismissal.until = nil
        }
        dismissal.stage += 1
        state.dismissals[family] = dismissal
        persist()
    }

    // MARK: - Private

    private func isFamilySuppressed(_ family: String, at date: Date) -> Bool {
        guard let dismissal = state.dismissals[family] else { return false }
        guard let until = dismissal.until else {
            // `until` is only nil once `stage` has advanced past the
            // ladder's last timed step (recordDismissed's else-branch) —
            // i.e. permanent suppression.
            return dismissal.stage > Self.backoffLadder.count
        }
        return date < until
    }

    private func isRetired(_ tipId: String) -> Bool {
        guard let impression = state.impressions[tipId] else { return false }
        return impression.shownCount >= Self.retireAfterShownCount && !impression.tapped
    }

    private func currentDayShownCount(at date: Date) -> Int {
        rollDayWindowIfNeeded(at: date)
        return state.dayShownCount
    }

    private func rollDayWindowIfNeeded(at date: Date) {
        if date.timeIntervalSince(state.dayWindowStart) >= Self.dayWindow {
            state.dayWindowStart = date
            state.dayShownCount = 0
        }
    }

    private func persist() {
        store.save(state)
    }
}
