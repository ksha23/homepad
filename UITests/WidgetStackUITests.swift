import XCTest

/// A widget stack on the Home Screen flips with a vertical swipe, as an
/// iPadOS Smart Stack does, and leaves the pages and its widgets' apps alone:
/// a swipe up flips it without moving the page or opening an app, and a
/// sideways swipe that starts on it still turns the page.
final class WidgetStackUITests: XCTestCase {
    /// Widgets that never ask Smart Rotate to show them, so the stack rests where the swipe leaves it.
    private static let stack = "personal.date+smarthome.scenes+kitchen.recipeOfTheDay:medium"

    override func setUp() {
        continueAfterFailure = false
    }

    func testASwipeFlipsTheStackAndOnlyTheStack() {
        // Landscape, as the iPads stand.
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowHome", "YES", "-HomePadCondition", "active", "-HomePadResetHomeScreen", "YES",
                               "-HomePadHomeWidgets", Self.stack]
        app.launch()
        // The label under a stack names the widget on top.
        let date = app.staticTexts["Date"].firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 15), "the stack rests on its first widget")
        sleep(2)
        let label = date.frame
        let home = app.buttons["Home"].firstMatch
        XCTAssertTrue(home.exists, "the Home icon shares the first page")
        let homeBefore = home.frame
        let window = app.windows.firstMatch

        // Up from low on the stack, quickly, as a person flips one.
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: label.midX, dy: label.minY - 30))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        sleep(2)
        XCTAssertFalse(date.exists, "a swipe up should flip the stack off its first widget")
        XCTAssertTrue(app.staticTexts["Scenes"].firstMatch.exists, "a swipe up should flip to the stack's next widget")
        XCTAssertEqual(home.frame.midX, homeBefore.midX, accuracy: 2, "the swipe should not move the page")
        XCTAssertTrue(home.isHittable, "the swipe should open no app")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "stack-flipped"
        shot.lifetime = .keepAlways
        add(shot)

        // Sideways from the same spot, the page turns.
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -window.frame.width * 0.5, dy: 0)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        sleep(2)
        XCTAssertFalse(window.frame.contains(CGPoint(x: home.frame.midX, y: home.frame.midY)),
                       "a sideways swipe that starts on the stack should still turn the page")
    }
}
