import XCTest

/// An app opened from inside a Home Screen widget closes back into that widget. Home Favorites opens Home
/// from a row with no quick action (the thermostat). Recorded on video, with the zoom's origin and landing
/// in Documents/swipe-trace.txt.
final class HomeWidgetZoomUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testHomeFavoritesClosesBackIntoItself() {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowHome", "YES", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES", "-HomePadSwipeTrace", "YES"]
        app.launch()
        sleep(4)

        // The thermostat row at the top of Home Favorites, in portrait.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.162)).tap()
        let homeBar = app.buttons.matching(identifier: "home-bar").firstMatch
        XCTAssertTrue(homeBar.waitForExistence(timeout: 8), "the row opens Home")
        sleep(2)

        let start = homeBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: homeBar)
        wait(for: [gone], timeout: 6)
        sleep(2)
    }
}
