import XCTest

/// Taps and drags on accessory controls, on the demo home. A press gesture laid
/// over the accessory buttons once swallowed every tap on dimmable lights and
/// blinds, so these check that taps and press and drag both still arrive.
final class AccessoryControlUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowHome", "YES", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES"] + extra
        app.launch()
        return app
    }

    /// The first element whose accessibility label starts with `prefix`, such as "Desk Lamp, ".
    private func element(_ app: XCUIApplication, labelPrefix prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func waitForLabel(_ element: XCUIElement, _ format: String, _ args: CVarArg...) {
        expectation(for: NSPredicate(format: format, argumentArray: args), evaluatedWith: element)
        waitForExpectations(timeout: 6)
    }

    func testTapOnAFavoriteRowTogglesTheLight() {
        let app = launch()
        let row = element(app, labelPrefix: "Living Room Lamp, ")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertEqual(row.label, "Living Room Lamp, Off")
        row.tap()
        waitForLabel(row, "label BEGINSWITH %@", "Living Room Lamp, On")
    }

    func testPressAndDragOnAFavoriteRowSetsBrightness() {
        let app = launch()
        let row = element(app, labelPrefix: "Kitchen Lights, ")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertEqual(row.label, "Kitchen Lights, On, 70%")
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.6, thenDragTo: end)
        waitForLabel(row, "label BEGINSWITH %@ AND NOT (label ENDSWITH %@)", "Kitchen Lights, On, ", "70%")
    }

    /// Holding a light without sliding once left its slider up for good, and the
    /// row ignored every tap after: the slide only reset when a drag ended, and a
    /// hold that never moves has no drag to end.
    func testHoldingAFavoriteRowWithoutSlidingLetsGo() {
        let app = launch()
        let row = element(app, labelPrefix: "Kitchen Lights, ")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertEqual(row.label, "Kitchen Lights, On, 70%")
        row.press(forDuration: 1.2)
        // Nothing changed, and the row takes taps again once the slider is down.
        XCTAssertEqual(row.label, "Kitchen Lights, On, 70%")
        sleep(1)
        row.tap()
        waitForLabel(row, "label == %@", "Kitchen Lights, Off")
    }

    func testHoldingAHomeAppTileLetsGo() {
        let app = launch(["-HomePadOpenApp", "home", "-HomePadSmartHomeRoom", "Kitchen"])
        let tile = element(app, labelPrefix: "Kitchen Lights, ")
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        XCTAssertEqual(tile.label, "Kitchen Lights, On, 70%")
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)).press(forDuration: 1.5)
        // A menu that opened is dismissed by tapping outside it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()
        sleep(1)
        XCTAssertEqual(tile.label, "Kitchen Lights, On, 70%")
        // The icon still toggles, so the tile is not stuck mid-slide.
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25)).tap()
        waitForLabel(tile, "label == %@", "Kitchen Lights, Off")
    }

    func testHomeAppTileIconTogglesAndTileOpensControls() {
        let app = launch(["-HomePadOpenApp", "home", "-HomePadSmartHomeRoom", "Kitchen"])
        let tile = element(app, labelPrefix: "Kitchen Lights, ")
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        // The icon at the tile's top left is the quick action.
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25)).tap()
        waitForLabel(tile, "label == %@", "Kitchen Lights, Off")
        // Anywhere else opens the full controls.
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)).tap()
        XCTAssertTrue(app.buttons["Turn On"].waitForExistence(timeout: 6))
    }

    /// Opens and closes a light's controls three times in landscape, as the
    /// iPads stand. The controls' page should reach the screen's edges, the
    /// shell's margin included, in the same frames as the rest of the page.
    /// Record the simulator during this test to measure that frame by frame.
    func testLightControlsOpenAndCloseInLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        let app = launch(["-HomePadOpenApp", "home", "-HomePadSmartHomeRoom", "Kitchen"])
        let tile = element(app, labelPrefix: "Kitchen Lights, ")
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        let close = app.buttons["Close"].firstMatch
        for _ in 0..<3 {
            sleep(1)
            tile.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)).tap()
            XCTAssertTrue(close.waitForExistence(timeout: 6))
            sleep(1)
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 6))
        }
    }

    func testPressAndDragOnAHomeAppTileSetsBrightness() {
        let app = launch(["-HomePadOpenApp", "home", "-HomePadSmartHomeRoom", "Kitchen"])
        let tile = element(app, labelPrefix: "Kitchen Lights, ")
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        XCTAssertEqual(tile.label, "Kitchen Lights, On, 70%")
        let start = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.75))
        let end = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.75))
        start.press(forDuration: 0.6, thenDragTo: end)
        waitForLabel(tile, "label BEGINSWITH %@ AND NOT (label ENDSWITH %@)", "Kitchen Lights, On, ", "70%")
        // A slide sets the level only: the tile's controls do not open.
        XCTAssertFalse(app.buttons["Turn Off"].exists)
    }
}
