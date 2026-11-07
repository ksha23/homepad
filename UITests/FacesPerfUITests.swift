import XCTest

/// A tour of the Faces app to measure it by: open it from the Home Screen,
/// scroll My Faces, open the gallery and scroll it, open the editor on a few
/// faces and swipe through their pages, and drag a widget on the Widgets page.
/// It checks only that each screen came up, so it runs the same before and
/// after a change and the numbers compare. Its taps on Up Close and Across the
/// Room land on the picker's accessibility stand-in, whose segments do not line
/// up with the drawn ones, so the distance stays. They stay so the tour matches
/// the one the README's numbers came from.
///
/// Every saved face carries the same widgets and mini widget, as faces in use
/// do. `-HomePadFacesTrace YES` writes the frame rate through each step to
/// Documents/fps-trace.txt. The Faces README's Performance section has how to
/// record it with Instruments. With `TEST_RUNNER_FACES_TOUR_DELAY=<seconds>`
/// the app waits that long on the Home Screen before Faces opens, for a
/// profiler to attach.
final class FacesPerfUITests: XCTestCase {
    /// The faces the editor opens, with how many pages to swipe forward on
    /// each: never as far as the Widgets page, where a swipe moves a widget.
    private static let editorTour: [(title: String, swipes: Int)] = [
        ("Modular", 2), ("Photos", 2), ("Weather", 1), ("Flow", 0),
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    func testFacesAppTour() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let delay = ProcessInfo.processInfo.environment["FACES_TOUR_DELAY"] ?? "2"
        let app = XCUIApplication()
        app.launchArguments = [
            "-HomePadOpenApp", "faces", "-HomePadOpenAppDelay", delay,
            "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
            "-HomePadFacesWidgets", "smarthome.favorites:medium;kitchen.timers:small;personal.weather:small",
            "-HomePadFacesMiniWidget", "shell.glance.mini",
            "-HomePadFacesTrace", "YES",
        ]
        app.launch()

        let addFace = app.buttons["Add Face"]
        XCTAssertTrue(addFace.waitForExistence(timeout: (Double(delay) ?? 2) + 30), "Faces opens")
        sleep(3)

        // My Faces.
        scroll(app, times: 3)

        // The Face Gallery.
        addFace.tap()
        let galleryHeader = app.otherElements["sheetHeader"].firstMatch
        XCTAssertTrue(galleryHeader.waitForExistence(timeout: 10), "the gallery opens")
        sleep(2)
        // One swipe fewer back, so the last one never pulls the sheet down.
        scroll(app, times: 3, back: 2)
        galleryHeader.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(galleryHeader.waitForNonExistence(timeout: 10), "the gallery closes")
        sleep(2)

        // The editor on a few faces.
        for (title, swipes) in Self.editorTour {
            openEditor(app, title: title)
            for _ in 0..<swipes { swipePreview(app, forward: true) }
            for _ in 0..<swipes { swipePreview(app, forward: false) }
            if title == "Modular" {
                app.buttons["Up Close"].firstMatch.tap()
                sleep(2)
                app.buttons["Across the Room"].firstMatch.tap()
                sleep(2)
            }
            closeEditor(app)
        }

        // A widget dragged on Modular's Widgets page, and back.
        openEditor(app, title: "Modular")
        app.buttons["Widgets"].firstMatch.tap()
        let timers = app.otherElements["Timers, Small"].firstMatch
        XCTAssertTrue(timers.waitForExistence(timeout: 10), "the Widgets page shows the face's widgets")
        sleep(2)
        let start = timers.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let left = start.withOffset(CGVector(dx: -timers.frame.width * 1.2, dy: 0))
        start.press(forDuration: 0.2, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 0.5)
        sleep(2)
        let moved = timers.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        moved.press(forDuration: 0.2, thenDragTo: moved.withOffset(CGVector(dx: timers.frame.width * 1.2, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.5)
        sleep(2)
        closeEditor(app)
    }

    /// Swipes up `times`, then back down `back` times, a second apart.
    private func scroll(_ app: XCUIApplication, times: Int, back: Int? = nil) {
        for _ in 0..<times {
            app.swipeUp()
            sleep(1)
        }
        for _ in 0..<(back ?? times) {
            app.swipeDown()
            sleep(1)
        }
    }

    private func openEditor(_ app: XCUIApplication, title: String) {
        let customize = app.buttons["Customize \(title)"].firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 10), "My Faces has \(title)")
        customize.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 10), "the editor opens on \(title)")
        sleep(2)
    }

    private func closeEditor(_ app: XCUIApplication) {
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForNonExistence(timeout: 10), "the editor closes")
        sleep(2)
    }

    /// A horizontal drag across the editor's preview, which pages it.
    private func swipePreview(_ app: XCUIApplication, forward: Bool) {
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.4))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        if forward {
            right.press(forDuration: 0.05, thenDragTo: left)
        } else {
            left.press(forDuration: 0.05, thenDragTo: right)
        }
        sleep(2)
    }
}
