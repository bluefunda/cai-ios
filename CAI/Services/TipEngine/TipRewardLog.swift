import CryptoKit
import Foundation

enum TipRewardEventType: String, Codable {
    case shown = "tip_shown"
    case tapped = "tip_tapped"
    case completed = "tip_completed"
    case dismissed = "tip_dismissed"
}

struct TipRewardRecord: Codable, Equatable {
    let event: TipRewardEventType
    let tipId: String
    let catalogVersion: String
    /// SHA-256 of the interest vector at event time, never the raw vector
    /// itself — the profile stays on-device even if these records
    /// eventually leave it. Field names/shape otherwise match the CLI's
    /// reward-event schema so a future shared training set stays possible.
    let interestVectorHash: String
    let surface: String
    let occurredAt: Date

    init(event: TipRewardEventType, tipId: String, catalogVersion: String, interestVector: [Double], occurredAt: Date = Date()) {
        self.event = event
        self.tipId = tipId
        self.catalogVersion = catalogVersion
        self.interestVectorHash = Self.hash(interestVector)
        self.surface = "ios"
        self.occurredAt = occurredAt
    }

    private static func hash(_ vector: [Double]) -> String {
        let bytes = vector.flatMap { withUnsafeBytes(of: $0) { Array($0) } }
        let digest = SHA256.hash(data: Data(bytes))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Tip Engine Phase 5 (bluefunda/cai-ios#160) — reward-event logging for a
/// future bandit `TipRanker`. Kept fully on-device for now: the app has no
/// analytics/telemetry consent gate anywhere today, so there's no existing
/// mechanism to send events behind, and building one from scratch is
/// separate follow-up work, not part of this MVP.
final class TipRewardLog {
    private let store: TipEngineFileStore<[TipRewardRecord]>

    init(store: TipEngineFileStore<[TipRewardRecord]> = TipEngineFileStore(filename: "reward_log.json")) {
        self.store = store
    }

    private(set) lazy var records: [TipRewardRecord] = store.load() ?? []

    func log(_ event: TipRewardEventType, tipId: String, catalogVersion: String, interestVector: [Double], at date: Date = Date()) {
        let record = TipRewardRecord(
            event: event, tipId: tipId, catalogVersion: catalogVersion,
            interestVector: interestVector, occurredAt: date
        )
        records.append(record)
        store.save(records)
    }
}
