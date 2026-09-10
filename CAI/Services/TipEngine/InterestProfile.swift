import Foundation

/// One completed chat turn's contribution to the interest profile — which
/// `TipTopic`s it touched, and when. Kept as a bounded history (not a
/// running scalar total) so decay math stays exact and testable: the
/// contribution of any single turn can always be recomputed from its own
/// `occurredAt`, with no accumulated floating-point drift and no timers.
struct InterestTurnRecord: Codable, Equatable {
    let topics: [TipTopic]
    let occurredAt: Date
}

struct InterestProfileState: Codable, Equatable {
    var history: [InterestTurnRecord] = []
}

/// On-device, EWMA-style interest profile over `TipTopic`, built from
/// completed chat turns. Tip Engine Phase 1 (bluefunda/cai-ios#156).
///
/// Deliberately holds no live subscription to a backend classifier — see
/// `TurnTopicSource` for why (no domain/intent/sap_confidence signal
/// reaches iOS today) and how a real one slots in later without touching
/// this type.
final class InterestProfile {
    /// 14-day half-life, per issue #156.
    static let halfLife: TimeInterval = 14 * 24 * 60 * 60
    /// Oldest entries are evicted first once history exceeds this.
    static let historyCap = 200

    private let store: TipEngineFileStore<InterestProfileState>
    private var state: InterestProfileState

    init(store: TipEngineFileStore<InterestProfileState> = TipEngineFileStore(filename: "interest_profile.json")) {
        self.store = store
        self.state = store.load() ?? InterestProfileState()
    }

    /// Records one completed turn's topics and persists immediately.
    /// History is capped at `historyCap`, dropping the oldest entries first.
    func recordTurn(topics: [TipTopic], at date: Date = Date()) {
        guard !topics.isEmpty else { return }
        state.history.append(InterestTurnRecord(topics: topics, occurredAt: date))
        if state.history.count > Self.historyCap {
            state.history.removeFirst(state.history.count - Self.historyCap)
        }
        store.save(state)
    }

    /// The current interest vector, indexed by `TipTopic.index`. Decay is
    /// computed lazily here from each record's elapsed wall-clock time
    /// (`pow(0.5, elapsed / halfLife)`) rather than stored — so calling this
    /// twice a day apart with no new turns yields a smaller vector purely
    /// from the passage of time, with no background timer involved.
    func vector(asOf now: Date = Date()) -> [Double] {
        var result = [Double](repeating: 0, count: TipTopic.dimension)
        for record in state.history {
            let elapsed = max(0, now.timeIntervalSince(record.occurredAt))
            let decay = pow(0.5, elapsed / Self.halfLife)
            for topic in record.topics {
                result[topic.index] += decay
            }
        }
        return result
    }
}
