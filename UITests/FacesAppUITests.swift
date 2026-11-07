import XCTest

/// The Faces app: tapping a face shows it. A live face thumbnail ignores
/// touches, and a button drawn from one once had nothing to tap.
final class FacesAppUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTappingAFaceShowsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadOpenApp", "faces", "-HomePadCondition", "active"]
        app.launch()
        let photos = app.buttons["Photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        XCTAssertNotEqual(photos.value as? String, "Showing now")
        photos.tap()
        expectation(for: NSPredicate(format: "value == %@", "Showing now"), evaluatedWith: photos)
        waitForExpectations(timeout: 5)
    }

    /// The face editor's widgets page: Edit Widget under the preview opens the
    /// selected widget's settings, in landscape as the iPads stand.
    func testEditWidgetOnAFace() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadOpenApp", "faces", "-HomePadFacesEdit", "faces.modular", "-HomePadFacesEditWidgets", "YES",
                               "-HomePadFacesWidgets", "smarthome.favorites:tall@4,0;personal.reminders:small@4,3",
                               "-HomePadFacesWidgetSelect", "0", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES"]
        app.launch()
        let edit = app.buttons["Edit Widget"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 15), "the selected widget has settings")
        sleep(2)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "face-editor-edit-widget-button"
        attachment.lifetime = .keepAlways
        add(attachment)
        edit.tap()
        XCTAssertTrue(app.otherElements["sheetHeader"].firstMatch.waitForExistence(timeout: 6), "Edit Widget should open")
        sleep(2)
        let sheet = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sheet.name = "face-edit-widget-favorites"
        sheet.lifetime = .keepAlways
        add(sheet)
        app.otherElements["sheetHeader"].buttons["Close"].firstMatch.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 6), "closing returns to the editor")
    }
}
