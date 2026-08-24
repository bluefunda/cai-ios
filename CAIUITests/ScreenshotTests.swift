import XCTest

/// Captures the App Store screenshot set for one CPP campaign (chat|code),
/// selected via the `SNAPSHOT_CAMPAIGN` env var (see CAIUITests.setUpWithError
/// and fastlane's `screenshots` lane). All screens here render from the demo
/// data `ScreenshotFixtures` seeds locally — no network/backend involved.
final class ScreenshotTests: CAIUITests {

    @MainActor
    func testScreenshots() throws {
        // Dismiss the keyboard BEFORE opening the sidebar: on iPad, a focused
        // text field shrinks the available detail height, and NavigationSplitView's
        // `.automatic` columnVisibility reacts by collapsing the sidebar again
        // right after "Show Sidebar" opens it if the keyboard is still up.
        dismissKeyboardIfNeeded() // iPad can auto-focus the message field on a fresh "New Chat"
        openSidebarIfNeeded()

        // SwiftUI exposes .accessibilityIdentifier on a plain HStack by
        // stamping it onto each un-combined child (Image + StaticText) rather
        // than one "Other" container element, so match any element type.
        let conversationRow = app.descendants(matching: .any)["conversationRow"].firstMatch
        XCTAssertTrue(
            conversationRow.waitForExistence(timeout: 10),
            "Expected a seeded demo conversation in the sidebar — check ScreenshotFixtures"
        )
        snapshot("01-Sidebar")

        conversationRow.tap()
        sleep(1) // let the seeded transcript render
        dismissKeyboardIfNeeded()
        snapshot("02-Chat")

        // Selecting a conversation can close the iPhone drawer, or (rarely)
        // leave the iPad split view collapsed — reopen either kind before
        // reaching for anything that lives in the sidebar/drawer.
        openSidebarIfNeeded()

        // Subscription paywall, via the always-visible "Upgrade to Pro" banner
        // (ScreenshotFixtures always seeds hasActiveSubscription = false so
        // this banner is guaranteed present).
        let upgradeButton = app.buttons["upgradeToProButton"]
        if upgradeButton.waitForExistence(timeout: 5) {
            upgradeButton.tap()
            sleep(1)
            snapshot("03-Subscription")
            let done = app.buttons["Done"]
            if done.waitForExistence(timeout: 5) {
                done.tap()
            }
        }

        openSidebarIfNeeded()

        // Settings, via the profile row menu.
        let profileButton = app.buttons["profileMenuButton"]
        if profileButton.waitForExistence(timeout: 5) {
            profileButton.tap()
            let settingsItem = app.buttons["Settings"]
            if settingsItem.waitForExistence(timeout: 5) {
                settingsItem.tap()
                sleep(1)
                snapshot("04-Settings")
            }
        }
    }

    /// iPhone shows the sidebar as a hidden drawer (hamburgerButton toggles
    /// it); iPad shows it inline via NavigationSplitView, which can still
    /// start/end up collapsed behind the system-provided "Show Sidebar"
    /// button since columnVisibility is `.automatic`. Tries both, no-ops if
    /// neither is present (sidebar already open).
    @MainActor
    private func openSidebarIfNeeded() {
        let hamburger = app.buttons["hamburgerButton"]
        if hamburger.waitForExistence(timeout: 5) {
            hamburger.tap()
            return
        }
        let showSidebar = app.buttons["Show Sidebar"]
        if showSidebar.waitForExistence(timeout: 5) {
            showSidebar.tap()
        }
    }

    /// The message field can end up focused (e.g. a fresh "New Chat" on
    /// iPad) — dismiss it so the software keyboard doesn't sit in every shot.
    @MainActor
    private func dismissKeyboardIfNeeded() {
        guard app.keyboards.count > 0 else { return }
        let hideKeyboard = app.buttons["Hide keyboard"]
        if hideKeyboard.waitForExistence(timeout: 2) {
            // A plain .tap() has XCUITest try an AX "scroll to visible" action
            // first, which can fail outright when the button sits right at
            // the screen edge (as it does on iPad); a coordinate tap hits the
            // point directly without that step.
            hideKeyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}
