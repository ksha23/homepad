import XCTest

/// Confirmation dialogs in Settings open from the row that asks for them. On
/// iPad a dialog is a popover. A dialog on a `Section` still opened, but a
/// section hands its modifiers to every row, so its popover pointed at
/// another row. Each test taps a row, expects the dialog next to it, and
/// confirms it.
final class SettingsDialogUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Devices & Sharing. Showing a pairing code makes the household, so
    /// Leave Household is there to tap once the code is put away.
    func testLeaveHousehold() {
        let app = launch(["-HomePadSettingsPane", "connect", "-ConnectPairingCode", "123456"])
        let stop = app.buttons["Stop Pairing"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15), "the pairing code")
        stop.tap()
        XCTAssertTrue(app.buttons["Show Pairing Code"].waitForExistence(timeout: 5), "the code is put away")
        let leave = app.buttons["Leave Household"]
        XCTAssertTrue(leave.waitForExistence(timeout: 15), "Leave Household")
        leave.tap()
        XCTAssertTrue(app.staticTexts["Leave this household?"].waitForExistence(timeout: 5), "the confirmation opens")
        XCTAssertTrue(app.staticTexts["This device stops receiving intercom messages, shared items and alerts until you pair it again."].exists)
        keepScreenshot(named: "Leave Household")
        // The row's Leave Household comes first, then the dialog's.
        let confirm = app.buttons.matching(identifier: "Leave Household").element(boundBy: 1)
        expectDialog(title: app.staticTexts["Leave this household?"], button: confirm,
                     nextTo: app.buttons.matching(identifier: "Leave Household").element(boundBy: 0))
        confirm.tap()
        XCTAssertTrue(leave.waitForNonExistence(timeout: 5), "the household is left")
    }

    /// Presence & Privacy. Sets up Alex's face with the simulated camera,
    /// unless an earlier run did, then deletes it from the row's Options menu.
    func testDeleteFaceData() {
        let app = launch(["-HomePadSettingsPane", "presence", "-HomePadSimulatePresence", "near"])
        XCTAssertTrue(app.switches["Face Recognition"].firstMatch.waitForExistence(timeout: 15), "the Presence pane")
        // A list makes only the rows it shows, so scroll to the people first.
        // Alex is the first of them.
        let options = app.buttons["Options"]
        let setUp = app.buttons["Set Up"].firstMatch
        let pane = app.collectionViews.element(boundBy: app.collectionViews.count - 1)
        for _ in 0..<8 where !options.exists && !setUp.exists {
            pane.swipeUp(velocity: .slow)
            sleep(1)
        }
        if !options.exists {
            bringUp(setUp, in: app)
            setUp.tap()
            let start = app.buttons["Get Started"]
            XCTAssertTrue(start.waitForExistence(timeout: 10), "face setup opens")
            start.tap()
            let done = app.buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 90), "the simulated setup finishes")
            done.tap()
        }
        XCTAssertTrue(options.waitForExistence(timeout: 10), "Alex's Options menu")
        bringUp(options, in: app)
        // The menu's label is not hittable to XCTest, so tap where it is.
        options.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let delete = app.buttons["Delete Face Data"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the menu's Delete Face Data")
        delete.tap()
        XCTAssertTrue(app.staticTexts["Delete face data for Alex?"].waitForExistence(timeout: 5), "the confirmation opens")
        keepScreenshot(named: "Delete Face Data")
        let confirm = app.buttons["Delete Face Data"].firstMatch
        expectDialog(title: app.staticTexts["Delete face data for Alex?"], button: confirm, nextTo: options)
        confirm.tap()
        XCTAssertTrue(options.waitForNonExistence(timeout: 5), "Alex's face data is deleted")
    }

    // MARK: Helpers

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                                           "-HomePadMember", "Alex", "-HomePadRecognized", "YES"]
        app.launch()
        return app
    }

    /// Scrolls the settings pane until the element is well inside the screen,
    /// clear of the edges a tap would miss at.
    private func bringUp(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        let pane = app.collectionViews.element(boundBy: app.collectionViews.count - 1)
        for _ in 0..<8 where element.frame.maxY > screen.maxY - 160 {
            pane.swipeUp(velocity: .slow)
            sleep(1)
        }
    }

    /// The dialog's popover sits right above or right below the row that
    /// asked, with its arrow on the row. `control` is the row's own button,
    /// halfway down the row.
    private func expectDialog(
        title: XCUIElement, button: XCUIElement, nextTo control: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let above = control.frame.minY - button.frame.maxY
        let below = title.frame.minY - control.frame.maxY
        XCTAssertTrue((0..<90).contains(above) || (0..<90).contains(below),
                      "the dialog points at the row that asked: title \(title.frame), button \(button.frame), row \(control.frame)",
                      file: file, line: line)
    }

    /// The screen with the dialog open, to see which row it points at. In
    /// landscape the screenshot comes out sideways.
    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
