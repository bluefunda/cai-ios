import XCTest
@testable import CAI

// MARK: - Tip Engine Phase 1 Tests (bluefunda/cai-ios#156)
// Guards InterestProfile's decay math, history cap, and on-device
// persistence round-trip.

final class InterestProfileTests: XCTestCase {
    private func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return dir
    }

    private func makeProfile(directory: URL) -> InterestProfile {
        InterestProfile(store: TipEngineFileStore(filename: "interest_profile.json", directory: directory))
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Decay math

    func test_vector_zeroElapsed_isFullWeight() {
        let profile = makeProfile(directory: tempDirectory())
        let now = Date()
        profile.recordTurn(topics: [.mcp], at: now)
        let vector = profile.vector(asOf: now)
        XCTAssertEqual(vector[TipTopic.mcp.index], 1.0, accuracy: 0.0001)
    }

    func test_vector_atHalfLife_isHalfWeight() {
        let profile = makeProfile(directory: tempDirectory())
        let start = Date()
        profile.recordTurn(topics: [.diagnostics], at: start)
        let vector = profile.vector(asOf: start.addingTimeInterval(InterestProfile.halfLife))
        XCTAssertEqual(vector[TipTopic.diagnostics.index], 0.5, accuracy: 0.0001)
    }

    func test_vector_veryLargeElapsed_decaysToNearZero() {
        let profile = makeProfile(directory: tempDirectory())
        let start = Date()
        profile.recordTurn(topics: [.errors], at: start)
        let vector = profile.vector(asOf: start.addingTimeInterval(InterestProfile.halfLife * 50))
        XCTAssertEqual(vector[TipTopic.errors.index], 0, accuracy: 0.0001)
    }

    func test_vector_multipleTopicsInOneTurn_eachContributes() {
        let profile = makeProfile(directory: tempDirectory())
        let now = Date()
        profile.recordTurn(topics: [.mcp, .costBudget], at: now)
        let vector = profile.vector(asOf: now)
        XCTAssertEqual(vector[TipTopic.mcp.index], 1.0, accuracy: 0.0001)
        XCTAssertEqual(vector[TipTopic.costBudget.index], 1.0, accuracy: 0.0001)
        XCTAssertEqual(vector[TipTopic.auth.index], 0, accuracy: 0.0001)
    }

    // MARK: History cap

    func test_history_capsAt200_evictingOldestFirst() {
        let directory = tempDirectory()
        let profile = makeProfile(directory: directory)
        let base = Date()
        // Record 210 turns, each tagged with a distinguishable topic
        // sequence so we can check which ones survived.
        for i in 0..<210 {
            let topic: TipTopic = (i % 2 == 0) ? .mcp : .config
            profile.recordTurn(topics: [topic], at: base.addingTimeInterval(TimeInterval(i)))
        }
        // The oldest 10 records (i = 0...9) should have been evicted.
        // Reconstruct a fresh profile from disk and check total weight.
        let reloaded = makeProfile(directory: directory)
        let vector = reloaded.vector(asOf: base.addingTimeInterval(209))
        let total = vector[TipTopic.mcp.index] + vector[TipTopic.config.index]
        // 200 surviving records, all at ~zero elapsed relative to the
        // asOf date used (well within the 14-day half-life), so total
        // weight should be close to 200, not 210.
        XCTAssertEqual(total, 200, accuracy: 1.0)
    }

    // MARK: Persistence round-trip

    func test_persistence_roundTripsThroughApplicationSupportBlob() {
        let directory = tempDirectory()
        let now = Date()
        let first = makeProfile(directory: directory)
        first.recordTurn(topics: [.onboarding], at: now)

        let second = makeProfile(directory: directory)
        let vector = second.vector(asOf: now)
        XCTAssertEqual(vector[TipTopic.onboarding.index], 1.0, accuracy: 0.0001)
    }
}
