import XCTest

/// Opening an app out of its icon and closing it back in must leave the shell responsive.
/// A measuring loop in the zoom once froze the app on the first close.
final class AppZoomUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The app on the Home Screen with a recognized member, so personal apps open without the gate.
    private func launchOnHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowHome", "YES", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES"]
        app.launch()
        return app
    }

    /// Drags the home bar up past the threshold, the shell's own swipe Home.
    private func swipeHome(_ app: XCUIApplication) {
        // Starts on the shell's home bar. A drag from the very edge of the screen is the system's own
        // Home gesture in the simulator and would leave the app instead of testing the shell's swipe.
        let start = app.buttons["home-bar"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    func testOpenAndCloseByTheHomeBarTwice() {
        let app = launchOnHome()
        let icon = app.buttons["Calendar"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 15), "the Home Screen shows")
        for round in 1...2 {
            icon.tap()
            let bar = app.buttons["home-bar"]
            XCTAssertTrue(bar.waitForExistence(timeout: 8), "the app opens and shows its home bar (round \(round))")
            sleep(1)
            bar.tap()
            XCTAssertTrue(icon.waitForExistence(timeout: 8), "tapping the home bar returns to the Home Screen (round \(round))")
            sleep(1)
        }
    }

    /// Opens an app and closes it again as soon as its home bar is there, before the open has finished,
    /// twice. Recorded on video to check that nothing of the app shows outside its shrinking window.
    func testAQuickOpenAndCloseLeavesNothingBehind() {
        let app = launchOnHome()
        let icon = app.buttons["Calendar"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 15), "the Home Screen shows")
        let bar = app.buttons["home-bar"]
        for round in 1...2 {
            icon.tap()
            XCTAssertTrue(bar.waitForExistence(timeout: 8), "the app opens (round \(round))")
            bar.tap()
            XCTAssertTrue(icon.waitForExistence(timeout: 8), "the quick close goes Home (round \(round))")
            sleep(2)
        }
        XCTAssertTrue(icon.isHittable, "the Home Screen takes touches after quick closes")
    }

    /// Opens an app, closes it to Home, does the same with another, then opens the first again. Recorded on
    /// video to check that the last open grows the first app as it was left, not a plain launch page.
    func testReopeningAnAppAfterAnotherOneShowsItAsLeft() {
        let app = launchOnHome()
        let calendar = app.buttons["Calendar"].firstMatch
        let reminders = app.buttons["Reminders"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 15), "the Home Screen shows")
        let bar = app.buttons["home-bar"]
        for icon in [calendar, reminders, calendar] {
            icon.tap()
            XCTAssertTrue(bar.waitForExistence(timeout: 8), "the app opens")
            sleep(2)
            bar.tap()
            XCTAssertTrue(icon.waitForExistence(timeout: 8), "the app closes to Home")
            sleep(2)
        }
    }

    /// Swipes up from the bottom edge and keeps screenshots of the close as it lands in the icon.
    func testSwipeUpClosesIntoTheIcon() {
        let app = launchOnHome()
        let icon = app.buttons["Calendar"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 15))
        func shot(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        icon.tap()
        shot("a-open-0.1s")
        usleep(400_000)
        shot("b-open-0.5s")
        sleep(2)
        shot("c-open-done")
        swipeHome(app)
        shot("d-close-0.0s")
        usleep(200_000)
        shot("e-close-0.2s")
        usleep(300_000)
        shot("f-close-0.5s")
        usleep(600_000)
        shot("g-close-1.1s")
        sleep(2)
        shot("h-close-done")
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home-bar"].exists, "the app is gone after the swipe")
    }

    /// Landscape, on a later Home Screen page, as the iPads stand: opens an app there and swipes it Home.
    /// Recorded on video to check that the page does not move sideways as the Home Screen comes forward.
    func testSwipeHomeOnALaterPage() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launchOnHome()
        // World Clock sits on a later page in the demo layout.
        let worldClock = app.buttons["World Clock"]
        XCTAssertTrue(worldClock.waitForExistence(timeout: 15))
        let window = app.windows.firstMatch.frame
        func isOnScreen() -> Bool { window.contains(CGPoint(x: worldClock.frame.midX, y: worldClock.frame.midY)) }
        for _ in 0..<4 where !isOnScreen() {
            app.swipeLeft()
            sleep(1)
        }
        XCTAssertTrue(isOnScreen(), "World Clock should be on screen after paging")
        let before = worldClock.frame
        worldClock.tap()
        XCTAssertTrue(app.buttons["home-bar"].waitForExistence(timeout: 8), "the app opens")
        sleep(1)
        swipeHome(app)
        XCTAssertTrue(worldClock.waitForExistence(timeout: 8), "the swipe goes Home")
        sleep(2)
        XCTAssertEqual(worldClock.frame.midX, before.midX, accuracy: 1, "the page comes back where it was")
    }

    /// After a swipe Home the next app must show and take touches. The swipe once left the live app
    /// hidden, so the next app opened invisible and the Home Screen under it ignored every tap.
    func testAnAppOpensAfterASwipeHome() {
        let app = launchOnHome()
        let icon = app.buttons["Calendar"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 15), "the Home Screen shows")
        let bar = app.buttons["home-bar"]
        icon.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 8), "the app opens")
        sleep(1)
        swipeHome(app)
        XCTAssertTrue(icon.waitForExistence(timeout: 8), "the swipe goes Home")
        sleep(1)
        icon.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 8), "the app opens again after the swipe")
        sleep(1)
        bar.tap()
        XCTAssertTrue(icon.waitForExistence(timeout: 8), "its home bar takes the tap")
        sleep(1)
        XCTAssertTrue(icon.isHittable, "the Home Screen takes touches again")
    }
}
