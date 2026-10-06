import XCTest

/// Manual, real-backend check of the live "thinking" flow — NOT part of the fixture-based
/// screenshot suite. Runs against whatever backend the build points at, using the session
/// already signed in on the simulator (no fixture mode), so it is skipped unless explicitly
/// requested with the THOUGHTS_LIVE_TEST=1 environment variable.
final class ThoughtsLiveUITests: XCTestCase {
    @MainActor
    func testSendPromptAndObserveThinking() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["THOUGHTS_LIVE_TEST"] == "1",
                          "Set THOUGHTS_LIVE_TEST=1 to run against a real, signed-in backend.")
        let app = XCUIApplication()
        app.launch()

        // Start from a fresh chat so the "first prompt" path is exercised.
        let newChat = app.buttons["New Chat"]
        if newChat.waitForExistence(timeout: 5) { newChat.tap() }

        let field = app.descendants(matching: .any)["composerTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "composer not found — is the simulator signed in?")
        field.tap()
        field.typeText(
            "A farmer has 3 fields. Field A yields 20% more than Field B, and Field C yields 15% less than Field A. "
                + "Together they produce 1,240 kg. Work out each field's yield step by step, then check your answer adds up."
        )

        // Optional: dismiss the keyboard first, to isolate whether its hide animation (which
        // resizes the message list) is what hides the empty reply row.
        if ProcessInfo.processInfo.environment["THOUGHTS_DISMISS_KEYBOARD"] == "1" {
            app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.tap() : app.swipeDown()
            app.descendants(matching: .any)["composerTextField"].swipeDown()
            Thread.sleep(forTimeInterval: 1.5)
        }

        let send = app.buttons["composerSendButton"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        // Capture the screen every 0.5s for 45s (attached to the result bundle).
        // Accessibility probe: is the waiting indicator ("Generating response") still in the live UI, and where?
        // Uses one consistent tree snapshot per sample, so an element vanishing mid-sample
        // can't fail the test.
        if ProcessInfo.processInfo.environment["THOUGHTS_AX_PROBE"] == "1" {
            func find(_ node: XCUIElementSnapshot, _ match: (XCUIElementSnapshot) -> Bool) -> [XCUIElementSnapshot] {
                (match(node) ? [node] : []) + node.children.flatMap { find($0, match) }
            }
            let start = Date()
            var dumped = false
            while Date().timeIntervalSince(start) < 8 {
                let elapsed = Date().timeIntervalSince(start)
                if let root = try? app.snapshot() {
                    let thinking = find(root) { $0.label.localizedCaseInsensitiveContains("generating response") }
                    let cells = find(root) { $0.elementType == .cell }
                    let desc = thinking.map { "\(NSCoder.string(for: $0.frame))" }.joined(separator: ",")
                    print(String(format: "[AXPROBE +%.1fs] thinking=%d %@ cells=%d", elapsed, thinking.count, desc, cells.count)
                        + " cellFrames=" + cells.map { NSCoder.string(for: $0.frame) }.joined(separator: " "))
                    if !dumped && elapsed > 2 {
                        dumped = true
                        print("[AXPROBE-TREE]\n" + app.debugDescription)
                    }
                } else {
                    print(String(format: "[AXPROBE +%.1fs] snapshot failed", elapsed))
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        let shots = Int(ProcessInfo.processInfo.environment["THOUGHTS_SHOTS"] ?? "") ?? 90
        for index in 0..<shots {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = String(format: "t%05.1f", Double(index) * 0.5)
            shot.lifetime = .keepAlways
            add(shot)
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Switches between existing chats from the sidebar, screenshotting rapidly right after
    /// each switch — to see the switch transition (overlapping text) and whether history
    /// thinking cards render after a reload.
    @MainActor
    func testSwitchBetweenChats() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["THOUGHTS_LIVE_TEST"] == "1",
                          "Set THOUGHTS_LIVE_TEST=1 to run against a real, signed-in backend.")
        let app = XCUIApplication()
        app.launch()

        for rowIndex in [0, 1, 2] {
            let hamburger = app.buttons["hamburgerButton"]
            XCTAssertTrue(hamburger.waitForExistence(timeout: 10))
            hamburger.tap()
            let rows = app.descendants(matching: .any).matching(identifier: "conversationRow")
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
            guard rows.count > rowIndex else { break }
            rows.element(boundBy: rowIndex).tap()
            for frame in 0..<14 {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "switch\(rowIndex)-f\(frame)"
                shot.lifetime = .keepAlways
                add(shot)
            }
            Thread.sleep(forTimeInterval: 1.5)
            let settled = XCTAttachment(screenshot: app.screenshot())
            settled.name = "switch\(rowIndex)-settled"
            settled.lifetime = .keepAlways
            add(settled)
        }
    }
}
