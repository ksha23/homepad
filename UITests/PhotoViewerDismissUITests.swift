import XCTest

/// The Photos viewer closes back into the thumbnail it shows, in landscape: a
/// slow swipe down that lets go while still moving, and the close button, for a
/// thumbnail in the middle of the grid and one at its right edge. Each close
/// ends with the viewer gone and the thumbnail back where it was before the
/// viewer opened, so nothing moved under the photo while it landed.
///
/// The tests also drive recordings of the close, made with `xcrun simctl io
/// <sim> recordVideo` around a run. They show demo photos, or the simulator's
/// own library when the environment holds `HOMEPAD_PHOTOS_LIBRARY` (pass
/// `TEST_RUNNER_HOMEPAD_PHOTOS_LIBRARY=1` to xcodebuild). A library of plain
/// photos, each a color found nowhere else on screen, lets a script find the
/// photo's rectangle in every frame.
final class PhotoViewerDismissUITests: XCTestCase {
    /// Grid positions, counted from the top left. The grid has six columns in landscape.
    private enum Cell {
        static let middle = 14
        static let rightEdge = 5
    }

    override func setUp() {
        continueAfterFailure = false
    }

    private var usesLibrary: Bool {
        ProcessInfo.processInfo.environment["HOMEPAD_PHOTOS_LIBRARY"] != nil
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-HomePadOpenApp", "photos", "-HomePadPhotosAlbum", "library",
                         "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                         "-HomePadMember", "Alex", "-HomePadRecognized", "YES"]
        if usesLibrary {
            // The JSON `false` as property list data: demo photos off for this launch.
            arguments += ["-personal.demoData", "<66616c7365>"]
        }
        app.launchArguments = arguments
        app.launch()
        // Turned once the app is up. Turned before the launch, a run
        // sometimes stayed in portrait.
        let device = XCUIDevice.shared
        let orientation = device.orientation
        device.orientation = .landscapeLeft
        addTeardownBlock { device.orientation = orientation }
        return app
    }

    /// A grid thumbnail by its place in the grid, with the grid at its top.
    private func thumbnail(_ app: XCUIApplication, at index: Int) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'photos.grid.'")).element(boundBy: index)
    }

    /// The viewer's "n of m" counter, there only while the viewer is open.
    private func counter(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ of [0-9]+")).firstMatch
    }

    /// Opens the photo at `index` and waits for the viewer to settle. Returns
    /// the thumbnail and where it sat before the viewer opened.
    private func open(_ app: XCUIApplication, at index: Int) -> (XCUIElement, CGRect) {
        let cell = thumbnail(app, at: index)
        XCTAssertTrue(cell.waitForExistence(timeout: 15))
        // Let the app's own zoom in finish, so the grid is at rest.
        sleep(2)
        let frame = cell.frame
        cell.tap()
        // Quiet while it opens (see `assertLanded`).
        sleep(2)
        XCTAssertTrue(counter(app).exists)
        XCTAssertTrue(counter(app).label.hasPrefix("\(index + 1) of "), "the viewer opens on the tapped photo")
        return (cell, frame)
    }

    /// A slow pull down from the middle of the screen, let go while still
    /// moving, so the photo carries the finger's speed into its landing.
    private func pullDownAndLetGo(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: XCUIGestureVelocity(400), thenHoldForDuration: 0)
    }

    /// The viewer is gone, the grid has not moved, and the thumbnail shows
    /// again. It asks the app nothing until the landing is over, so no
    /// snapshot of the app's accessibility tree runs on its main thread while
    /// a recording follows the photo.
    private func assertLanded(_ app: XCUIApplication, _ cell: XCUIElement, at frame: CGRect) {
        sleep(2)
        XCTAssertFalse(counter(app).exists, "the viewer has closed")
        XCTAssertTrue(cell.isHittable, "the thumbnail shows again")
        XCTAssertEqual(cell.frame.minX, frame.minX, accuracy: 1, "the grid has not moved")
        XCTAssertEqual(cell.frame.minY, frame.minY, accuracy: 1, "the grid has not moved")
    }

    func testSwipeDownLandsOnAThumbnailInTheMiddle() {
        let app = launch()
        let (cell, frame) = open(app, at: Cell.middle)
        pullDownAndLetGo(app)
        assertLanded(app, cell, at: frame)
    }

    func testSwipeDownLandsOnAThumbnailAtTheEdge() {
        let app = launch()
        let (cell, frame) = open(app, at: Cell.rightEdge)
        pullDownAndLetGo(app)
        assertLanded(app, cell, at: frame)
    }

    func testCloseButtonLandsOnTheThumbnail() {
        let app = launch()
        let (cell, frame) = open(app, at: Cell.middle)
        app.buttons["Close"].tap()
        assertLanded(app, cell, at: frame)
    }
}
