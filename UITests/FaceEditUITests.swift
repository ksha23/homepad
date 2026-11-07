import XCTest

/// Holding the face opens the editor for that face, and Done goes back to the face, not to My Faces.
final class FaceEditUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testHoldingTheFaceOpensItsEditorAndDoneGoesBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowFace", "faces.digital", "-HomePadCondition", "active",
                               "-HomePadDemoContent", "YES", "-HomePadMember", "Alex", "-HomePadRecognized", "YES"]
        app.launch()
        sleep(4)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 8), "the editor opens")
        XCTAssertFalse(app.staticTexts["My Faces"].exists, "straight to the editor, not My Faces")
        XCTAssertTrue(app.staticTexts["Digital"].firstMatch.exists, "the editor is for the face on the wall")
        sleep(1)
        done.tap()

        let homeBar = app.buttons.matching(identifier: "home-bar").firstMatch
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: homeBar)
        wait(for: [gone], timeout: 8)
        XCTAssertFalse(app.staticTexts["My Faces"].exists, "back on the face")
    }
}
