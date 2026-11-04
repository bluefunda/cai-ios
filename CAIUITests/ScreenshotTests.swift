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

/// Requests screenshots (Requests list, request detail, Ask AI chat), from the Requests
/// fixtures — `-bf_requests_fixtures YES` gives the demo user the Requests space with
/// RequestsFixtures data, no backend. Each scene is also attached to the test result.
final class RequestsScreenshotTests: CAIUITests {
    @MainActor
    override func setUpWithError() throws {
        app.launchArguments += ["-bf_feature_requests", "YES", "-bf_requests_fixtures", "YES"]
        try super.setUpWithError()
    }

    @MainActor
    func testRequestsScreenshots() throws {
        openSidebarIfNeeded()
        let requestsSpace = app.descendants(matching: .any)["sidebar.space.requests"].firstMatch
        XCTAssertTrue(requestsSpace.waitForExistence(timeout: 10), "Requests space missing — check the fixtures flags")
        requestsSpace.tap()
        let requestsRow = app.descendants(matching: .any)["sidebar.destination.requests"].firstMatch
        if requestsRow.waitForExistence(timeout: 3) { requestsRow.tap() }
        closeSidebarIfNeeded()

        let request = app.descendants(matching: .any)["requests.crRow.32"].firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 10), "Expected fixture request CR-1042 (id 32)")
        capture("05-Requests")

        request.tap()
        let commentsTab = app.descendants(matching: .any)["requests.detail.tab.comments"].firstMatch
        let askAI = app.buttons["requests.detail.askAI"]
        XCTAssertTrue(askAI.waitForExistence(timeout: 10), "Ask AI on the request detail")
        sleep(1)
        if commentsTab.exists {
            XCTAssertTrue(commentsTab.isHittable, "Comments isn't cut off")
        }
        capture("06-Request")

        askAI.tap()
        let chip = app.descendants(matching: .any)["chat.requestContext"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "the new chat shows the request it's about")
        // A new chat focuses the composer; iPhone has no Hide keyboard key, so drag the
        // keyboard down from the chat area for a clean shot.
        dismissKeyboardIfNeeded()
        if app.keyboards.count > 0 {
            app.staticTexts["How can I help you today?"].firstMatch.swipeDown()
        }
        capture("07-AskAI")
    }

    /// The board (regular width only), Configurations and User Details, for checking the
    /// layouts on iPhone, iPad and Mac.
    @MainActor
    func testRequestsLayoutScreenshots() throws {
        openSidebarIfNeeded()
        let requestsSpace = app.descendants(matching: .any)["sidebar.space.requests"].firstMatch
        XCTAssertTrue(requestsSpace.waitForExistence(timeout: 10), "Requests space missing — check the fixtures flags")
        requestsSpace.tap()
        let requestsRow = app.descendants(matching: .any)["sidebar.destination.requests"].firstMatch
        if requestsRow.waitForExistence(timeout: 3) { requestsRow.tap() }
        closeSidebarIfNeeded()
        XCTAssertTrue(app.descendants(matching: .any)["requests.crRow.32"].firstMatch.waitForExistence(timeout: 10))

        let viewMode = app.segmentedControls["requests.viewMode"].firstMatch
        if viewMode.waitForExistence(timeout: 3) {
            viewMode.buttons.element(boundBy: 1).tap()
            sleep(1)
            capture("08-Board")
        }

        let newRequest = app.buttons["requests.newRequest"].firstMatch
        if newRequest.waitForExistence(timeout: 3) {
            newRequest.tap()
            XCTAssertTrue(app.descendants(matching: .any)["requests.new.create"].firstMatch.waitForExistence(timeout: 10))
            sleep(1)
            capture("08b-NewRequest")
            app.buttons["Cancel"].firstMatch.tap()
            let create = app.descendants(matching: .any)["requests.new.create"].firstMatch
            _ = create.waitForNonExistence(timeout: 5)
        }

        openAdmin("configurations")
        XCTAssertTrue(app.staticTexts["Request Types"].firstMatch.waitForExistence(timeout: 10), "Configurations cards")
        sleep(1)
        capture("09-Configurations")

        openAdmin("userManagement")
        let user = app.staticTexts["Priya Shah"].firstMatch
        XCTAssertTrue(user.waitForExistence(timeout: 10), "fixture user in User Management")
        capture("10-Users")
        user.tap()
        XCTAssertTrue(app.buttons["admin.user.status"].firstMatch.waitForExistence(timeout: 10), "Activate/Deactivate button")
        sleep(1)
        capture("11-UserDetails")

        openAdmin("projects")
        let newProject = app.buttons["projects.new"].firstMatch
        XCTAssertTrue(newProject.waitForExistence(timeout: 10), "New project in the Projects toolbar")
        newProject.tap()
        XCTAssertTrue(app.descendants(matching: .any)["projects.new.create"].firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        capture("12-NewProject")
        app.buttons["Cancel"].firstMatch.tap()
        _ = app.descendants(matching: .any)["projects.new.create"].firstMatch.waitForNonExistence(timeout: 5)

        let firstProject = app.staticTexts["Fixture project description."].firstMatch
        if firstProject.waitForExistence(timeout: 5) {
            firstProject.tap()
            let edit = app.buttons["projects.edit"].firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 10), "Edit project on the project screen")
            edit.tap()
            XCTAssertTrue(app.descendants(matching: .any)["projects.new.create"].firstMatch.waitForExistence(timeout: 10))
            sleep(1)
            capture("13-EditProject")
            app.buttons["Cancel"].firstMatch.tap()
        }
    }

    @MainActor
    private func openAdmin(_ destination: String) {
        let row = app.descendants(matching: .any)["sidebar.destination.\(destination)"].firstMatch
        // iPhone's drawer keeps its rows in the hierarchy while closed, off screen.
        if !(row.exists && row.isHittable) { openSidebarIfNeeded() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(destination) in the sidebar")
        row.tap()
        let hamburger = app.buttons["hamburgerButton"]
        if row.exists, row.isHittable, hamburger.exists { hamburger.tap() }
    }

    @MainActor
    private func capture(_ name: String) {
        snapshot(name)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openSidebarIfNeeded() {
        let hamburger = app.buttons["hamburgerButton"]
        if hamburger.waitForExistence(timeout: 5) {
            hamburger.tap()
            return
        }
        let showSidebar = app.buttons["Show Sidebar"]
        if showSidebar.waitForExistence(timeout: 3) { showSidebar.tap() }
    }

    /// iPhone's drawer stays over the content after picking a destination on some runs.
    @MainActor
    private func closeSidebarIfNeeded() {
        let hamburger = app.buttons["hamburgerButton"]
        if !app.descendants(matching: .any)["requests.crRow.32"].firstMatch.waitForExistence(timeout: 3),
           hamburger.exists {
            hamburger.tap()
        }
    }

    @MainActor
    private func dismissKeyboardIfNeeded() {
        guard app.keyboards.count > 0 else { return }
        let hideKeyboard = app.buttons["Hide keyboard"]
        if hideKeyboard.waitForExistence(timeout: 2) {
            hideKeyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}
