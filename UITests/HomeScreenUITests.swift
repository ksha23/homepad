import XCTest

/// The Home Screen keeps its place: closing an app returns to the page it was opened from.
final class HomeScreenUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A slow swipe that stops short of halfway springs back to the page it started on.
    func testAShortSwipeStaysOnThePage() {
        let app = launch(["-HomePadShowHome", "YES"])
        let home = app.buttons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 15), "the first page shows")
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.55))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.55))
        // About a third of the screen, slowly, and held before letting go, so it is not a flick.
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        sleep(1)
        XCTAssertTrue(isOnScreen(home, in: app), "a swipe short of halfway should spring back to the first page")
    }

    func testClosingAnAppReturnsToTheSamePage() {
        // Landscape, as the iPads stand.
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowHome", "YES", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES", "-HomePadShowCloseButtons", "YES"]
        app.launch()
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
        worldClock.tap()
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 6))
        close.tap()
        XCTAssertTrue(worldClock.waitForExistence(timeout: 6))
        sleep(1)
        XCTAssertTrue(isOnScreen(), "closing the app should return to the page with World Clock")
    }

    /// Dragging an icon in edit mode crashed the app as the drag began: SwiftUI
    /// draws the drag preview without the app's environment objects, which the
    /// tiles read.
    func testDraggingOnTheHomeScreenInEditMode() {
        let app = launch(["-HomePadShowHome", "YES", "-HomePadEditHomeScreen", "YES"])
        // By position: a jiggling icon has no stable hit point, so isHittable throws.
        let window = app.windows.firstMatch.frame
        let icons = app.buttons.allElementsBoundByIndex.filter {
            !$0.label.isEmpty && !$0.label.hasPrefix("Remove") && window.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }
        XCTAssertGreaterThanOrEqual(icons.count, 2, "edit mode should show at least two icons")
        drag(icons[0], to: icons[1])
        XCTAssertEqual(app.state, .runningForeground, "dragging an icon should not crash the app")
    }

    /// Edit mode on the default layout, where Home, Assistant, Music and Calendar share a row.
    private static let editHome = ["-HomePadShowHome", "YES", "-HomePadEditHomeScreen", "YES", "-HomePadResetHomeScreen", "YES"]

    /// A lifted icon follows the finger, the icons it passes move aside before
    /// the drop, and the drop saves it in the slot it was over.
    func testDraggingAnIconMovesItIntoAnotherSlot() {
        let app = launch(Self.editHome)
        let home = app.buttons["Home"].firstMatch
        let assistant = app.buttons["Assistant"].firstMatch
        let music = app.buttons["Music"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        let before = (home: home.frame, assistant: assistant.frame, music: music.frame)
        XCTAssertEqual(before.home.midY, before.music.midY, accuracy: 10, "Home and Music should share a row")
        drag(home, to: music)
        XCTAssertEqual(app.state, .runningForeground, "dragging an icon should not crash the app")
        XCTAssertEqual(home.frame.midX, before.music.midX, accuracy: 20, "Home should land in Music's slot")
        XCTAssertEqual(assistant.frame.midX, before.home.midX, accuracy: 20, "Assistant should move into Home's slot")
        XCTAssertEqual(music.frame.midX, before.assistant.midX, accuracy: 20, "Music should move back one slot")

        // Saved: the new order is there after a relaunch.
        app.terminate()
        let again = launch(["-HomePadShowHome", "YES", "-HomePadEditHomeScreen", "YES"])
        let saved = again.buttons["Home"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertEqual(saved.frame.midX, before.music.midX, accuracy: 20, "the new order should be saved")
    }

    /// A widget takes a slot of its size and the icons flow around it: Scenes
    /// (two cells wide) moved up a row takes Home's and Assistant's cells, they
    /// move along, and Music wraps to the start of the next row.
    func testDraggingAWidgetReflowsTheIconsAroundIt() {
        let app = launch(Self.editHome)
        let scenes = app.staticTexts["Scenes"].firstMatch
        let home = app.buttons["Home"].firstMatch
        let music = app.buttons["Music"].firstMatch
        // Reminders sits a row below Home.
        let reminders = app.buttons["Reminders"].firstMatch
        XCTAssertTrue(scenes.waitForExistence(timeout: 10))
        let before = (scenes: scenes.frame, home: home.frame, music: music.frame, reminders: reminders.frame)
        let up = before.home.midY - before.reminders.midY
        let start = scenes.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 1.0, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up)),
                    withVelocity: .slow, thenHoldForDuration: 1.0)
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(scenes.frame.midY, before.scenes.midY + up, accuracy: 20, "Scenes should move up a row")
        XCTAssertEqual(home.frame.midX, before.music.midX, accuracy: 20, "Home should move past Scenes")
        XCTAssertEqual(music.frame.midY, before.reminders.midY, accuracy: 20, "Music should wrap to the next row")
        // Back at the start of the row, whatever the screen's width: on the 13-inch
        // Recipes starts that row, on the 11-inch it ends it.
        XCTAssertEqual(music.frame.minX, Self.leftmostItemX(in: app), accuracy: 20, "Music should start the next row")
    }

    /// The edit controls still work beside the reorder: a remove badge removes
    /// its icon, and a widget's resize button changes its size.
    func testRemoveBadgesAndResizingStillWork() {
        let app = launch(Self.editHome)
        let remove = app.buttons["Remove Home"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        XCTAssertFalse(app.buttons["Home"].exists, "the remove badge should remove Home")
        let label = app.staticTexts["Up Next"].firstMatch
        let resize = app.buttons["Change size of Up Next"].firstMatch
        XCTAssertTrue(resize.exists)
        let before = label.frame
        resize.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        XCTAssertNotEqual(label.frame, before, "the resize button should change Up Next's size")
    }

    /// Outside edit mode the reorder press stays out of the way: holding an icon
    /// still opens its menu, which enters edit mode.
    func testHoldingAnIconOutsideEditModeShowsItsMenu() {
        let app = launch(["-HomePadShowHome", "YES", "-HomePadResetHomeScreen", "YES"])
        let home = app.buttons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        home.press(forDuration: 1.5)
        let edit = app.buttons["Edit Home Screen"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "holding an icon should open its menu")
        edit.tap()
        XCTAssertTrue(app.buttons["Remove Home"].waitForExistence(timeout: 5), "the menu should enter edit mode")
    }

    /// A quick swipe in edit mode still turns the page, between items or on one:
    /// an item lifts only after a short still press.
    func testQuickSwipeInEditModeTurnsThePage() {
        let app = launch(Self.editHome)
        let home = app.buttons["Home"].firstMatch
        let assistant = app.buttons["Assistant"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        let before = home.frame
        // The gutter between Home and Assistant holds no item.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let gap = origin.withOffset(CGVector(dx: (before.maxX + assistant.frame.minX) / 2, dy: before.midY))
        gap.press(forDuration: 0.05, thenDragTo: gap.withOffset(CGVector(dx: -500, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        XCTAssertFalse(isOnScreen(home, in: app), "a quick swipe on empty space should turn the page")
        // Back, starting on whatever item is under the middle of the screen.
        app.swipeRight(velocity: .fast)
        sleep(1)
        XCTAssertEqual(home.frame.midX, before.midX, accuracy: 20, "a quick swipe on an item should turn the page back and move nothing")
        XCTAssertEqual(home.frame.midY, before.midY, accuracy: 20)
    }

    /// Holding a lifted icon at the side of the screen turns the page, and the
    /// drop puts the icon on that page.
    func testHoldingAnIconAtTheSideMovesItToTheNextPage() {
        let app = launch(Self.editHome)
        let home = app.buttons["Home"].firstMatch
        let assistant = app.buttons["Assistant"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        dragToTheRightSide(home, in: app, holdingFor: 2)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(isOnScreen(home, in: app), "Home should be on the page the drag turned to")
        XCTAssertFalse(isOnScreen(assistant, in: app), "the first page should have turned away")
    }

    /// Held past the last page, a new page opens for the icon, as on iPadOS.
    func testHoldingAnIconPastTheLastPageOpensANewPage() {
        let app = launch(Self.editHome)
        let home = app.buttons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        // Two page turns: to the second page, then past it.
        dragToTheRightSide(home, in: app, holdingFor: 3.5)
        XCTAssertTrue(isOnScreen(home, in: app), "Home should be on the new page")
        XCTAssertFalse(isOnScreen(app.buttons["Settings"].firstMatch, in: app), "the second page should have turned away")
        XCTAssertLessThan(home.frame.midX, app.windows.firstMatch.frame.midX, "Home should be alone in the first slot")
    }

    /// The same for Control Center's tiles, whose preview is the tile itself.
    func testDraggingInControlCenterEditMode() {
        let app = launch(["-HomePadShowPanel", "controlCenter", "-HomePadEditControlCenter", "YES"])
        let volume = app.descendants(matching: .any)["Volume"].firstMatch
        let camera = app.descendants(matching: .any)["Camera"].firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: 15))
        XCTAssertTrue(camera.waitForExistence(timeout: 5))
        let before = volume.frame
        drag(volume, to: camera)
        XCTAssertEqual(app.state, .runningForeground, "dragging a tile should not crash the app")
        XCTAssertNotEqual(volume.frame.origin, before.origin, "the volume tile should land in another slot")
    }

    // MARK: Edit Widget

    /// In edit mode a tap on a widget with settings opens Edit Widget, as on
    /// iPadOS, and the list chosen there shows on the widget at once.
    func testTappingAWidgetInEditModeOpensEditWidget() {
        let app = launch(Self.editHome + ["-HomePadHomeWidgets", "personal.reminders:tall"])
        let remove = app.buttons["Remove Reminders"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        tapBody(of: remove)
        XCTAssertTrue(app.otherElements["sheetHeader"].firstMatch.waitForExistence(timeout: 6), "a tap should open Edit Widget")
        let errands = app.buttons["Errands"].firstMatch
        XCTAssertTrue(errands.waitForExistence(timeout: 6), "Edit Widget should list the reminders lists")
        sleep(1)
        keepScreenshot("edit-widget-reminders")
        errands.tap()
        sleep(1)
        keepScreenshot("edit-widget-reminders-errands")
        app.otherElements["sheetHeader"].buttons["Close"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Errands"].firstMatch.exists, "the widget should show the list chosen for it")
    }

    /// Home Favorites' Edit Widget picks accessories for that widget alone,
    /// and a widget with settings still lifts and moves with a short press.
    func testHomeFavoritesSettingsAndDraggingStillWork() {
        // Favorites that leave Coffee Maker out, whatever an earlier run saved.
        let app = launch(Self.editHome + ["-HomePadHomeWidgets", "smarthome.favorites:tall",
                                          "-HomePadSmartHomeFavorites", "demo:climate.living,demo:lock.front,demo:light.kitchen"])
        let remove = app.buttons["Remove Home Favorites"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        tapBody(of: remove)
        XCTAssertTrue(app.otherElements["sheetHeader"].firstMatch.waitForExistence(timeout: 6), "a tap should open Edit Widget")
        sleep(1)
        keepScreenshot("edit-widget-favorites")
        // Coffee Maker is not a favorite: checking it gives the widget its own list.
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 6), "a home this size gets a search field")
        search.tap()
        search.typeText("coffee\n")
        let coffee = app.buttons["Coffee Maker"].firstMatch
        XCTAssertTrue(coffee.waitForExistence(timeout: 6), "the search should find Coffee Maker")
        coffee.tap()
        sleep(1)
        XCTAssertEqual(coffee.value as? String, "In this widget")
        keepScreenshot("edit-widget-favorites-search")
        app.otherElements["sheetHeader"].buttons["Close"].firstMatch.tap()
        sleep(2)
        // A press on the widget's body still lifts it and moves it.
        let label = app.staticTexts["Home Favorites"].firstMatch
        let before = label.frame
        let body = remove.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 120, dy: 160))
        let target = app.buttons["Home"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        body.press(forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 1.0)
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertNotEqual(label.frame.origin, before.origin, "a press should still lift Home Favorites and move it")
    }

    /// A tap on a widget's body, below and right of its remove badge.
    private func tapBody(of removeBadge: XCUIElement) {
        sleep(1)
        removeBadge.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 120, dy: 160)).tap()
    }

    /// Keeps a screenshot in the test results, for review.
    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The left edge of the Home Screen's first column on screen.
    private static func leftmostItemX(in app: XCUIApplication) -> CGFloat {
        let window = app.windows.firstMatch.frame
        return app.buttons.allElementsBoundByIndex
            .filter { !$0.label.isEmpty && window.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) && $0.frame.width > 60 }
            .map(\.frame.minX)
            .min() ?? 0
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES"] + arguments
        app.launch()
        sleep(3)
        return app
    }

    /// A hold long enough to lift the item, then a move at a finger's pace and a
    /// pause over the target, as a person drags.
    private func drag(_ source: XCUIElement, to target: XCUIElement) {
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 1.0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.0)
        sleep(2)
    }

    /// Lifts an item, carries it to the right side of the screen and holds it there.
    private func dragToTheRightSide(_ element: XCUIElement, in app: XCUIApplication, holdingFor seconds: TimeInterval) {
        let window = app.windows.firstMatch.frame
        let side = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.maxX - 12, dy: element.frame.midY))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: side, withVelocity: .slow, thenHoldForDuration: seconds)
        sleep(2)
    }

    /// True when the element exists and its middle is on screen.
    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists && app.windows.firstMatch.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
    }
}
