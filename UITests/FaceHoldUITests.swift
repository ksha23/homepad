import XCTest

/// Holding the face opens the Faces app, as a long press on a face customizes
/// it on HomeView and Apple Watch. A tap on the face still goes Home, a tile on
/// the Home face still takes its tap, a swipe still changes the face, and the
/// sleeping cover still only wakes the display.
final class FaceHoldUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(face: String, condition: String = "active", _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowCloseButtons", "YES", "-HomePadShowFace", face, "-HomePadCondition", condition, "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES", "-HomePadProximity", "near"] + extra
        app.launch()
        return app
    }

    /// The Faces app's Add Face button, there only while Faces is open.
    private func facesApp(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Add Face"]
    }

    /// The Home Screen header's avatar button.
    private func homeScreen(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["People, Alex"]
    }

    /// The profile dot the shell draws over every face.
    private func faceIsUp(_ app: XCUIApplication) -> Bool {
        app.staticTexts["Alex recognized"].waitForExistence(timeout: 15)
    }

    private var center: CGVector { CGVector(dx: 0.5, dy: 0.5) }

    func testHoldingTheFaceOpensFaces() {
        let app = launch(face: "faces.numerals")
        XCTAssertTrue(faceIsUp(app))
        app.coordinate(withNormalizedOffset: center).press(forDuration: 1.0)
        XCTAssertTrue(facesApp(app).waitForExistence(timeout: 6), "a hold on the face should open Faces")
        // Letting go after the hold is not also a tap that goes Home.
        sleep(1)
        XCTAssertTrue(facesApp(app).exists)
        XCTAssertFalse(homeScreen(app).exists)
    }

    func testTapOnTheFaceStillGoesHome() {
        let app = launch(face: "faces.numerals")
        XCTAssertTrue(faceIsUp(app))
        app.coordinate(withNormalizedOffset: center).tap()
        XCTAssertTrue(homeScreen(app).waitForExistence(timeout: 6), "a tap on the face should go Home")
        XCTAssertFalse(facesApp(app).exists)
    }

    func testTapOnAHomeFaceTileStillToggles() {
        let app = launch(face: "faces.homeModular")
        let lamp = app.buttons["Living Room Lamp, Off"]
        XCTAssertTrue(lamp.waitForExistence(timeout: 15))
        lamp.tap()
        // A dimmable lamp turns on at its last level: "Living Room Lamp, On, 40%".
        let on = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Living Room Lamp, On")).firstMatch
        XCTAssertTrue(on.waitForExistence(timeout: 6), "a tap on a tile should still toggle it")
        XCTAssertFalse(facesApp(app).exists)
        XCTAssertFalse(homeScreen(app).exists)
    }

    /// As a long press on a widget does on iPadOS: the hold customizes, and the
    /// tile it started on does not fire.
    func testHoldingAHomeFaceTileOpensFacesWithoutPressingIt() {
        let app = launch(face: "faces.homeModular")
        let lamp = app.buttons["Living Room Lamp, Off"]
        XCTAssertTrue(lamp.waitForExistence(timeout: 15))
        lamp.press(forDuration: 1.0)
        XCTAssertTrue(facesApp(app).waitForExistence(timeout: 6), "a hold on a tile should open Faces")
        // The lamp is still off: Faces closes to the Home Screen, whose Favorites list it.
        app.buttons["Close"].firstMatch.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Living Room Lamp, ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        XCTAssertEqual(row.label, "Living Room Lamp, Off", "the held tile should not toggle the lamp")
    }

    /// A slow swipe that ends with the finger resting still never opens Faces:
    /// the hold gave up once the finger moved. The wall starts on the Home face,
    /// so the swipe lands on the next saved face, Numerals. The Home face stays
    /// beside it, off screen.
    func testSwipeChangesTheFaceAndNeverOpensFaces() {
        let app = launch(face: "faces.homeModular")
        let lamp = app.buttons["Living Room Lamp, Off"]
        XCTAssertTrue(lamp.waitForExistence(timeout: 15))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.2)
        let window = app.windows.firstMatch.frame
        let offScreen = NSPredicate { _, _ in
            !lamp.exists || !window.contains(CGPoint(x: lamp.frame.midX, y: lamp.frame.midY))
        }
        expectation(for: offScreen, evaluatedWith: nil)
        waitForExpectations(timeout: 6)
        XCTAssertTrue(faceIsUp(app), "the swipe should show the next face")
        XCTAssertFalse(facesApp(app).exists, "a swipe should never open Faces")
        XCTAssertFalse(homeScreen(app).exists)
    }

    /// A camera tile's tap gives way to the hold too, so Cameras does not open on release.
    func testHoldingACameraTileOpensFaces() {
        let app = launch(face: "faces.homeModular")
        let camera = app.staticTexts["Demo feed for Front Door"]
        XCTAssertTrue(camera.waitForExistence(timeout: 15))
        camera.press(forDuration: 1.0)
        XCTAssertTrue(facesApp(app).waitForExistence(timeout: 6), "a hold on a camera tile should open Faces")
        sleep(1)
        XCTAssertTrue(facesApp(app).exists, "letting go should not also open Cameras")
    }

    /// A light row in a Modular widget takes a still press for its level slider
    /// at 0.25 s, before the hold is due, and keeps it. The saved faces are
    /// pinned to one Modular face with Home Favorites in its first widget slot.
    func testHoldingALightRowInAWidgetKeepsItsSlider() {
        // A large Home Favorites widget in Modular's widget area, landscape and
        // portrait, so the Kitchen Lights row shows (a medium one stops at two rows).
        let app = launch(face: "faces.modular",
                         ["-HomePadFacesWidgets", "smarthome.favorites:large@4,0|smarthome.favorites:large@0,4"])
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Kitchen Lights, ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertEqual(row.label, "Kitchen Lights, On, 70%")
        row.press(forDuration: 1.2)
        sleep(2)
        XCTAssertFalse(facesApp(app).exists, "a light row's own hold should win")
        XCTAssertEqual(row.label, "Kitchen Lights, On, 70%", "holding without sliding changes nothing")
    }

    /// Under the Home Screen the face is frosted wallpaper and takes no touches,
    /// so a hold on the header's date and greeting does not open Faces.
    func testHoldingTheHomeScreenDoesNotOpenFaces() {
        let app = launch(face: "faces.numerals", ["-HomePadShowHome", "YES"])
        let greeting = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@ AND NOT (label BEGINSWITH %@)", "Alex", "People")).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 15))
        greeting.press(forDuration: 1.0)
        sleep(2)
        XCTAssertFalse(facesApp(app).exists, "a hold on the Home Screen should not open Faces")
    }

    /// While the display sleeps a touch only wakes it. With the condition
    /// pinned to sleeping the cover stays, so a hold on it does nothing.
    func testHoldingTheSleepingCoverDoesNotOpenFaces() {
        let app = launch(face: "faces.numerals", condition: "sleeping")
        XCTAssertTrue(app.descendants(matching: .any)["Display sleeping. Tap to wake."].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: center).press(forDuration: 1.0)
        sleep(2)
        XCTAssertFalse(facesApp(app).exists, "a hold while asleep should not open Faces")
    }
}
