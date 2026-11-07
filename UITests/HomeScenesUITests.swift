import XCTest

/// Scenes in the Home app: none on the page at first, every scene behind the
/// Scenes button, and a star there puts one on the page and takes it off again.
final class HomeScenesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTheScenesButtonListsScenesAndAStarAddsAFavorite() {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadOpenApp", "home", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES", "-HomePadProximity", "near"]
        app.launch()
        let scenes = app.buttons["Scenes"]
        XCTAssertTrue(scenes.waitForExistence(timeout: 15))
        let chip = app.buttons["Run Movie Night"]
        XCTAssertFalse(chip.exists, "no scene is on the page until it is a favorite")

        scenes.tap()
        let add = app.buttons["Add Movie Night to Favorites"]
        XCTAssertTrue(add.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Run Good Morning"].exists, "the list has every scene")
        add.tap()
        let remove = app.buttons["Remove Movie Night from Favorites"]
        XCTAssertTrue(remove.waitForExistence(timeout: 6))
        keepScreenshot(app, named: "Scenes list")
        dismissPopover(app)
        XCTAssertTrue(chip.waitForExistence(timeout: 6), "a favorite scene shows on the page")
        keepScreenshot(app, named: "Favorite scene on the page")

        // Back to no favorites, as the next test expects.
        scenes.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 6))
        remove.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 6))
        dismissPopover(app)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: chip)
        waitForExpectations(timeout: 6)
    }

    /// A tap outside a popover closes it.
    private func dismissPopover(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.98)).tap()
        sleep(1)
    }

    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
