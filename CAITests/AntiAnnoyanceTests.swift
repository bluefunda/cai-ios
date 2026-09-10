import XCTest
@testable import CAI

// MARK: - Tip Engine Phase 4 Tests (bluefunda/cai-ios#159)
// Guards session/day caps, the dismissal backoff ladder, retirement, and
// the permanent opt-out toggle.

final class AntiAnnoyanceTests: XCTestCase {
    private func makeAntiAnnoyance() -> AntiAnnoyance {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return AntiAnnoyance(store: TipEngineFileStore(filename: "anti_annoyance.json", directory: dir))
    }

    // MARK: Session / day caps

    func test_sessionCap_blocksAfterOneShownPerSession() {
        let anti = makeAntiAnnoyance()
        anti.startSession()
        XCTAssertTrue(anti.isEligible(tipId: "t1", family: "f1"))
        anti.recordShown(tipId: "t1", family: "f1")
        XCTAssertFalse(anti.isEligible(tipId: "t2", family: "f2"))
        anti.startSession()
        XCTAssertTrue(anti.isEligible(tipId: "t2", family: "f2"))
    }

    func test_dayCap_blocksAfterThreeShownPerDay_acrossSessions() {
        let anti = makeAntiAnnoyance()
        let day1 = Date()
        for i in 0..<3 {
            anti.startSession(at: day1.addingTimeInterval(TimeInterval(i)))
            anti.recordShown(tipId: "t\(i)", family: "f\(i)", at: day1.addingTimeInterval(TimeInterval(i)))
        }
        anti.startSession(at: day1.addingTimeInterval(10))
        XCTAssertFalse(anti.isEligible(tipId: "t4", family: "f4", at: day1.addingTimeInterval(10)))

        // Next day, the window rolls over.
        let day2 = day1.addingTimeInterval(25 * 3600)
        anti.startSession(at: day2)
        XCTAssertTrue(anti.isEligible(tipId: "t4", family: "f4", at: day2))
    }

    // MARK: Dismissal backoff ladder

    func test_dismissalBackoff_advances24h_72h_14d_thenPermanent() {
        let anti = makeAntiAnnoyance()
        let t0 = Date()

        anti.recordDismissed(family: "fam", at: t0)
        XCTAssertFalse(anti.isEligible(tipId: "t", family: "fam", at: t0.addingTimeInterval(23 * 3600)))
        XCTAssertTrue(anti.isEligible(tipId: "t", family: "fam", at: t0.addingTimeInterval(25 * 3600)))

        let t1 = t0.addingTimeInterval(25 * 3600)
        anti.recordDismissed(family: "fam", at: t1)
        XCTAssertFalse(anti.isEligible(tipId: "t", family: "fam", at: t1.addingTimeInterval(71 * 3600)))
        XCTAssertTrue(anti.isEligible(tipId: "t", family: "fam", at: t1.addingTimeInterval(73 * 3600)))

        let t2 = t1.addingTimeInterval(73 * 3600)
        anti.recordDismissed(family: "fam", at: t2)
        XCTAssertFalse(anti.isEligible(tipId: "t", family: "fam", at: t2.addingTimeInterval(13 * 24 * 3600)))
        XCTAssertTrue(anti.isEligible(tipId: "t", family: "fam", at: t2.addingTimeInterval(15 * 24 * 3600)))

        let t3 = t2.addingTimeInterval(15 * 24 * 3600)
        anti.recordDismissed(family: "fam", at: t3)
        // Permanent — even a century later, still suppressed.
        XCTAssertFalse(anti.isEligible(tipId: "t", family: "fam", at: t3.addingTimeInterval(100 * 365 * 24 * 3600)))
    }

    // MARK: Retirement

    func test_retirement_afterThreeShownWithNoTap() {
        let anti = makeAntiAnnoyance()
        for i in 0..<3 {
            anti.startSession(at: Date().addingTimeInterval(TimeInterval(i * 100_000)))
            anti.recordShown(tipId: "t", family: "f", at: Date().addingTimeInterval(TimeInterval(i * 100_000)))
        }
        anti.startSession()
        XCTAssertFalse(anti.isEligible(tipId: "t", family: "f"))
    }

    func test_retirement_doesNotApplyIfTapped() {
        let anti = makeAntiAnnoyance()
        for i in 0..<3 {
            anti.startSession(at: Date().addingTimeInterval(TimeInterval(i * 100_000)))
            anti.recordShown(tipId: "t", family: "f", at: Date().addingTimeInterval(TimeInterval(i * 100_000)))
        }
        anti.recordTapped(tipId: "t")
        anti.startSession()
        XCTAssertTrue(anti.isEligible(tipId: "t", family: "f"))
    }

    // MARK: Opt-out toggle

    func test_optOut_persistsAndZeroesEligibility() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: TipEngineFileStore<AntiAnnoyanceState> = TipEngineFileStore(filename: "anti_annoyance.json", directory: dir)
        let first = AntiAnnoyance(store: store)
        first.setOptedOut(true)
        XCTAssertFalse(first.isEligible(tipId: "t", family: "f"))

        let second = AntiAnnoyance(store: store)
        XCTAssertTrue(second.isOptedOut)
        XCTAssertFalse(second.isEligible(tipId: "t", family: "f"))
    }
}
