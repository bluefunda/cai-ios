import XCTest
@testable import CAI

@MainActor
final class AppUpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AppUpdateCheckerTests")
        defaults.removePersistentDomain(forName: "AppUpdateCheckerTests")
    }

    private func info(latest: String = "2.23.0", minimum: String = "2.0.0") -> AppVersionInfo {
        AppVersionInfo(latest: latest, minimum: minimum, storeUrl: "https://apps.apple.com/app/id1")
    }

    func test_compare_isNumericPerPart() {
        XCTAssertEqual(AppVersionComparison.compare("2.10.0", "2.9.1"), .orderedDescending)
        XCTAssertEqual(AppVersionComparison.compare("2.22", "2.22.0"), .orderedSame)
        XCTAssertEqual(AppVersionComparison.compare("2.22.0", "2.22.1"), .orderedAscending)
        XCTAssertEqual(AppVersionComparison.compare("3.0.0-beta", "3.0.0"), .orderedSame)
    }

    func test_state_fromVersions() {
        XCTAssertEqual(AppUpdateChecker.state(current: "2.23.0", info: info()), .upToDate)
        XCTAssertEqual(AppUpdateChecker.state(current: "2.24.0", info: info()), .upToDate, "a build ahead of the store")
        XCTAssertEqual(AppUpdateChecker.state(current: "2.22.0", info: info()),
                       .available(latest: "2.23.0", storeURL: URL(string: "https://apps.apple.com/app/id1")))
        XCTAssertEqual(AppUpdateChecker.state(current: "1.9.0", info: info()),
                       .required(latest: "2.23.0", storeURL: URL(string: "https://apps.apple.com/app/id1")))
    }

    func test_close_remindsAgainAfterThreeDays_orForANewerVersion() async {
        var clock = Date(timeIntervalSince1970: 0)
        let checker = AppUpdateChecker(currentVersion: "2.22.0", defaults: defaults, now: { clock },
                                       fetch: { self.info() })
        await checker.check()
        XCTAssertTrue(checker.showsBanner)
        XCTAssertFalse(checker.isUpdateRequired)

        checker.dismissBanner()
        XCTAssertFalse(checker.showsBanner)

        // A relaunch keeps it closed within the 3 days…
        var latest = "2.23.0"
        clock = clock.addingTimeInterval(AppUpdateChecker.remindAfter - 60)
        let relaunched = AppUpdateChecker(currentVersion: "2.22.0", defaults: defaults, now: { clock },
                                          fetch: { self.info(latest: latest) })
        await relaunched.check()
        XCTAssertFalse(relaunched.showsBanner)

        // …and shows it again after them.
        clock = clock.addingTimeInterval(120)
        XCTAssertTrue(relaunched.showsBanner)

        // A newer version shows it at once, even within the 3 days.
        relaunched.dismissBanner()
        XCTAssertFalse(relaunched.showsBanner)
        latest = "2.24.0"
        await relaunched.check(force: true)
        XCTAssertTrue(relaunched.showsBanner)
    }

    func test_check_belowMinimum_requiresUpdate_withNoBanner() async {
        let checker = AppUpdateChecker(currentVersion: "1.5.0", defaults: defaults) { self.info() }
        await checker.check()
        XCTAssertTrue(checker.isUpdateRequired)
        XCTAssertFalse(checker.showsBanner)
        checker.dismissBanner()
        XCTAssertTrue(checker.isUpdateRequired, "the blocking screen can't be closed")
    }

    func test_check_isThrottled_andAFailedCheckChangesNothing() async {
        var calls = 0
        var fail = false
        var clock = Date(timeIntervalSince1970: 0)
        let checker = AppUpdateChecker(currentVersion: "2.22.0", defaults: defaults, now: { clock }, fetch: {
            calls += 1
            if fail { throw URLError(.notConnectedToInternet) }
            return self.info()
        })
        await checker.check()
        await checker.check()
        XCTAssertEqual(calls, 1, "a second check within 5 minutes is skipped")

        clock = clock.addingTimeInterval(AppUpdateChecker.minimumInterval + 1)
        fail = true
        await checker.check()
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(checker.showsBanner, "the last known state stays")
    }
}
