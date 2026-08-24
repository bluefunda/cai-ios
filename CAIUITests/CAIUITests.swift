import XCTest

/// Base case for screenshot UI tests. Launches the app in fixture mode
/// (`ScreenshotFixtures` in the main target seeds a demo user + demo
/// conversations and skips all real network/auth calls — see that file for
/// why this needs no backend or test account).
class CAIUITests: XCTestCase {
    let app = XCUIApplication()

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false

        // In a real `fastlane snapshot` run, setupSnapshot() reads the
        // Fastfile lane's `launch_arguments:` (e.g. "-UITestScreenshots
        // -UITestCampaign code") from fastlane's own cache file and appends
        // them here — that must be the only source of "-UITestCampaign", or
        // whichever default gets added first wins ties in
        // ScreenshotFixtures.campaign's firstIndex(of:) lookup regardless of
        // what the lane actually asked for (a real bug this comment is
        // guarding against — cai-ios screenshot campaigns silently all
        // rendered "chat" content until this was fixed).
        setupSnapshot(app)

        // Direct `xcodebuild test` runs (no fastlane involved) skip that
        // mechanism entirely, so fall back to SNAPSHOT_CAMPAIGN for ad-hoc
        // debugging — only when fastlane's own arguments never arrived.
        if !app.launchArguments.contains("-UITestScreenshots") {
            let campaign = ProcessInfo.processInfo.environment["SNAPSHOT_CAMPAIGN"] ?? "chat"
            app.launchArguments += ["-UITestScreenshots", "-UITestCampaign", campaign]
        }

        app.launch()
    }
}
