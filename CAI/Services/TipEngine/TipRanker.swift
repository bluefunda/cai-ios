import Foundation

/// A candidate tip paired with its cosine-similarity score against the
/// current interest vector.
struct TipCandidate {
    let entry: TipManifestEntry
    let score: Double
}

/// Ranks eligible candidates. Rules-only for the MVP (`RulesBasedTipRanker`
/// below), but kept behind a protocol so a Thompson-sampling ranker can drop
/// in later (per issue #158) without any caller needing to change — no
/// ranking logic lives outside this boundary.
protocol TipRanker {
    func rank(_ candidates: [TipCandidate], personaId: String) -> TipManifestEntry?
}

/// Sorts by cosine score descending, ties broken by catalog order (stable
/// sort). When the interest vector is all-zero (brand-new user, no history
/// yet — every candidate's score is 0), falls back to a small fixed
/// per-persona prior so a new user still sees a tip instead of nothing.
struct RulesBasedTipRanker: TipRanker {
    /// Cold-start tip-family priors by persona id, checked only when every
    /// candidate scored 0. Empty/unrecognized personas get no prior boost,
    /// i.e. plain catalog order.
    var coldStartPriorFamily: [String: String] = [
        "general": "onboarding"
    ]

    func rank(_ candidates: [TipCandidate], personaId: String) -> TipManifestEntry? {
        guard !candidates.isEmpty else { return nil }
        let allZero = candidates.allSatisfy { $0.score == 0 }
        if allZero, let priorFamily = coldStartPriorFamily[personaId],
           let prior = candidates.first(where: { $0.entry.family == priorFamily }) {
            return prior.entry
        }
        return candidates.max { lhs, rhs in lhs.score < rhs.score }?.entry
    }
}

enum CosineSimilarity {
    static func score(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
