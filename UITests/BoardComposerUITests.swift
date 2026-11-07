import XCTest

/// Typing a Family Board note with the on-screen keyboard up. In landscape the
/// keyboard takes about half the height, so the note, its color, the pin and
/// Post must all fit in what is left above it, without overlapping.
final class BoardComposerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    func testTypingANewNoteInLandscape() {
        let app = type(editor: "new", orientation: .landscapeLeft, text: "Dentist at 4, then pick up Sam from soccer")
        expectAboveTheKeyboard(app, ["Post", "Pin to Top"])
    }

    func testTypingANewNoteInPortrait() {
        let app = type(editor: "new", orientation: .portrait, text: "Dentist at 4, then pick up Sam from soccer")
        expectAboveTheKeyboard(app, ["Post", "Pin to Top"])
    }

    /// A long note shrinks to stay whole, and Delete Note stays above the keyboard.
    func testEditingALongNoteInLandscape() {
        let app = type(editor: "first", orientation: .landscapeLeft,
                       text: " Also the library books are due Friday, and we are out of oat milk and coffee filters")
        expectAboveTheKeyboard(app, ["Save", "Pin to Top", "Delete Note"])
    }

    /// Post stays in the header, dimmed, until the note has text.
    func testPostIsDimmedUntilTheNoteHasText() {
        let app = launch(editor: "new", orientation: .landscapeLeft)
        let post = app.buttons["Post"]
        XCTAssertTrue(post.waitForExistence(timeout: 30))
        XCTAssertFalse(post.isEnabled)
        app.textFields["board.noteText"].typeText("Hi")
        XCTAssertTrue(post.isEnabled)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.buttons["Done"].exists)
    }

    // MARK: Helpers

    private func launch(editor: String, orientation: UIDeviceOrientation) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadOpenApp", "board", "-ConnectDemoData", "YES", "-ConnectDemoNotes", "6",
                               "-ConnectDemoEditor", editor, "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES"]
        app.launch()
        return app
    }

    private func type(editor: String, orientation: UIDeviceOrientation, text: String) -> XCUIApplication {
        let app = launch(editor: editor, orientation: orientation)
        let field = app.textFields["board.noteText"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "the composer opens")
        keepScreenshot(named: "Opened")
        field.tap()
        sleep(1)
        field.typeText(text)
        sleep(1)
        keepScreenshot(named: "Typed")
        // XCTest screenshots leave out the on-screen keyboard. Hold the screen
        // so `xcrun simctl io <sim> screenshot` can take it from outside.
        sleep(5)
        return app
    }

    /// The note and the named buttons sit above the keyboard, and the note
    /// overlaps none of them.
    private func expectAboveTheKeyboard(_ app: XCUIApplication, _ buttons: [String], file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = app.otherElements["inputView"].firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 6), "the on-screen keyboard is up", file: file, line: line)
        let top = keyboard.frame.minY
        let note = app.textFields["board.noteText"].frame
        XCTAssertLessThanOrEqual(note.maxY, top + 0.5, "the note ends above the keyboard", file: file, line: line)
        for name in buttons {
            let frame = app.buttons[name].firstMatch.frame
            XCTAssertLessThanOrEqual(frame.maxY, top + 0.5, "\(name) is above the keyboard", file: file, line: line)
            XCTAssertFalse(frame.intersects(note), "\(name) overlaps the note", file: file, line: line)
        }
    }

    /// The whole screen as the simulator draws it, without the keyboard. In
    /// landscape the image comes out sideways.
    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
