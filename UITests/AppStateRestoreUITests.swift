import XCTest

/// Apps reopen where they were left: change something, close the app, open it
/// again from its Home Screen icon, and find it as it was. A launch that opens
/// a screen keeps app state in memory for that launch, so each test starts
/// from the defaults and never changes what the simulator saved.
final class AppStateRestoreUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        // Landscape, as the iPads stand.
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(_ appID: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowCloseButtons", "YES", "-HomePadOpenApp", appID, "-HomePadCondition", "active", "-HomePadResetHomeScreen", "YES"]
        app.launch()
        return app
    }

    /// Closes the app on screen with its close button, back to the Home Screen.
    private func close(_ app: XCUIApplication) {
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 6))
        close.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: close)
        waitForExpectations(timeout: 6)
    }

    /// Opens an app again from its Home Screen icon, paging to it if needed,
    /// in the same launch. (Opening a link with `XCUIApplication.open` relaunches.)
    private func reopen(_ title: String, in app: XCUIApplication) {
        let icon = app.buttons[title].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 6))
        let window = app.windows.firstMatch.frame
        func isOnScreen() -> Bool { window.contains(CGPoint(x: icon.frame.midX, y: icon.frame.midY)) }
        for _ in 0..<4 where !isOnScreen() {
            app.swipeLeft()
            sleep(1)
        }
        XCTAssertTrue(isOnScreen(), "\(title) should be on a Home Screen page")
        icon.tap()
    }

    // MARK: Calendar

    func testCalendarReopensInWeekViewOnTheSameWeek() {
        let app = launch("calendar")
        let view = app.buttons["View"].firstMatch
        XCTAssertTrue(view.waitForExistence(timeout: 10))
        XCTAssertEqual(view.value as? String, "Day")
        view.tap()
        let week = app.buttons["Week"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar.week.'"))
        XCTAssertTrue(days.firstMatch.waitForExistence(timeout: 5))
        let thisWeek = days.firstMatch.identifier
        app.buttons["Next"].firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons[thisWeek])
        waitForExpectations(timeout: 5)
        let nextWeek = days.firstMatch.identifier
        XCTAssertNotEqual(nextWeek, thisWeek)

        close(app)
        reopen("Calendar", in: app)
        XCTAssertTrue(app.buttons[nextWeek].waitForExistence(timeout: 10), "Calendar should reopen on the week it was left on")
        XCTAssertEqual(app.buttons["View"].firstMatch.value as? String, "Week")
    }

    // MARK: Reminders

    func testRemindersReopensOnTheChosenList() {
        let app = launch("reminders")
        let groceries = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Groceries'"))
        // The Groceries tile among the smart lists, selected while it shows.
        let chosen = groceries.matching(NSPredicate(format: "selected == true")).firstMatch
        XCTAssertTrue(groceries.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(chosen.exists, "Reminders should open on Today or All")
        groceries.firstMatch.tap()
        XCTAssertTrue(chosen.waitForExistence(timeout: 5))

        close(app)
        reopen("Reminders", in: app)
        XCTAssertTrue(chosen.waitForExistence(timeout: 10), "Reminders should reopen on Groceries")
    }

    /// A closed app stays suspended, like an iPadOS app, so even what no app saves, such as a
    /// reminder typed and not yet added, is still there when it reopens.
    func testRemindersKeepsAnUnsentReminderWhileSuspended() {
        let app = launch("reminders")
        let field = app.textFields["New Reminder"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Milk")

        close(app)
        reopen("Reminders", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Milk", "the unsent reminder should still be there")
    }

    // MARK: Photos

    func testPhotosReopensOnTheOpenAlbumWhereTheGridWasLeft() {
        let app = launch("photos")
        let library = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Library'")).firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        let back = app.buttons["Albums"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        let first = app.buttons["photos.grid.demo:0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        app.swipeUp()
        sleep(2)
        let scrolled = !first.isHittable

        close(app)
        reopen("Photos", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Photos should reopen inside the album")
        if scrolled {
            sleep(1)
            XCTAssertFalse(first.isHittable, "the grid should reopen where it was scrolled to")
        }
    }

    // MARK: Settings

    func testSettingsReopensOnTheSamePane() {
        let app = launch("settings")
        let about = app.buttons["About"].firstMatch
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        XCTAssertFalse(about.isSelected)
        about.tap()
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: about)
        waitForExpectations(timeout: 5)

        close(app)
        reopen("Settings", in: app)
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: about)
        waitForExpectations(timeout: 5)
    }
}
