import XCTest

/// A widget on the face opens its app, growing out of the widget, and the app closes to the Home Screen,
/// as every app opened from the face does. Recorded on video to check the window's path, with the zoom's
/// origin and landing in Documents/swipe-trace.txt.
final class FaceWidgetUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAFaceWidgetOpensItsAppAndTheAppClosesToHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowFace", "faces.digital", "-HomePadCondition", "active",
                               "-HomePadDemoContent", "YES", "-HomePadMember", "Alex", "-HomePadRecognized", "YES",
                               "-HomePadFacesWidgets", "personal.weather:medium", "-HomePadSwipeTrace", "YES"]
        app.launch()
        sleep(4)
        XCTAssertFalse(app.buttons.matching(identifier: "home-bar").firstMatch.exists, "the face shows")

        // The Digital face puts the widget in its first open area, at the bottom left in portrait.
        let x = 0.28
        let y = 0.88
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        let homeBar = app.buttons.matching(identifier: "home-bar").firstMatch
        XCTAssertTrue(homeBar.waitForExistence(timeout: 8), "the widget opens its app")
        sleep(2)

        // A swipe up on the bar closes the app, to the Home Screen.
        let start = homeBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: homeBar)
        wait(for: [gone], timeout: 6)
        sleep(2)
        XCTAssertTrue(app.buttons["Weather"].firstMatch.waitForExistence(timeout: 4), "the Home Screen shows")
    }
}
