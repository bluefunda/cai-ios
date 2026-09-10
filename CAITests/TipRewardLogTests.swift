import XCTest
@testable import CAI

// MARK: - Tip Engine Phase 5 Tests (bluefunda/cai-ios#160)
// Guards reward-event emission at each lifecycle point, and that the
// logged interest-vector hash never leaks the raw vector.

final class TipRewardLogTests: XCTestCase {
    private func makeLog() -> TipRewardLog {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return TipRewardLog(store: TipEngineFileStore(filename: "reward_log.json", directory: dir))
    }

    func test_shown_emitsCorrectEvent() {
        let log = makeLog()
        log.log(.shown, tipId: "t1", catalogVersion: "1", interestVector: [1, 0, 0])
        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records[0].event, .shown)
        XCTAssertEqual(log.records[0].tipId, "t1")
        XCTAssertEqual(log.records[0].catalogVersion, "1")
        XCTAssertEqual(log.records[0].surface, "ios")
    }

    func test_fullLifecycle_shownTappedCompleted_allEmitted() {
        let log = makeLog()
        log.log(.shown, tipId: "t1", catalogVersion: "1", interestVector: [1, 0])
        log.log(.tapped, tipId: "t1", catalogVersion: "1", interestVector: [1, 0])
        log.log(.completed, tipId: "t1", catalogVersion: "1", interestVector: [1, 0])
        XCTAssertEqual(log.records.map(\.event), [.shown, .tapped, .completed])
    }

    func test_dismissed_emittedInsteadOfCompleted() {
        let log = makeLog()
        log.log(.shown, tipId: "t1", catalogVersion: "1", interestVector: [1, 0])
        log.log(.dismissed, tipId: "t1", catalogVersion: "1", interestVector: [1, 0])
        XCTAssertEqual(log.records.map(\.event), [.shown, .dismissed])
    }

    func test_interestVectorHash_isStableAndNeverEqualsRawVector() {
        let log = makeLog()
        let vector: [Double] = [0.5, 0.25, 0, 1.0]
        log.log(.shown, tipId: "t1", catalogVersion: "1", interestVector: vector)
        log.log(.shown, tipId: "t2", catalogVersion: "1", interestVector: vector)

        let hash1 = log.records[0].interestVectorHash
        let hash2 = log.records[1].interestVectorHash
        XCTAssertEqual(hash1, hash2, "same vector must hash the same way")
        XCTAssertFalse(hash1.contains("0.5"))
        XCTAssertNotEqual(hash1, vector.map { String($0) }.joined())
    }

    func test_persistence_roundTripsAcrossInstances() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: TipEngineFileStore<[TipRewardRecord]> = TipEngineFileStore(filename: "reward_log.json", directory: dir)
        let first = TipRewardLog(store: store)
        first.log(.shown, tipId: "t1", catalogVersion: "1", interestVector: [1])

        let second = TipRewardLog(store: store)
        XCTAssertEqual(second.records.count, 1)
        XCTAssertEqual(second.records[0].tipId, "t1")
    }
}
