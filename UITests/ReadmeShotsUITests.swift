import XCTest

/// The README's sheet screenshots. `-HomePadForceLandscape` turns the app but
/// not its sheets or the keyboard, so these tests turn the simulator itself.
/// Each opens one sheet with debug launch arguments and keeps a screenshot
/// named after its README shot. `scripts/readme_images.py` runs them and
/// copies the shots into the README images. A plain UI test run skips them.
///
/// XCTest screenshots leave out the on-screen keyboard. A shot with the
/// keyboard up names itself in an activity, "README screen <shot>", and holds
/// the screen while the script takes it with `xcrun simctl io <sim> screenshot`.
final class ReadmeShotsUITests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment

    override func setUpWithError() throws {
        try XCTSkipIf(environment["HOMEPAD_README_SHOTS"] == nil, "scripts/readme_images.py runs these")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = environment["HOMEPAD_README_PORTRAIT"] == nil ? .landscapeLeft : .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Faces

    func testFaceGallery() {
        let app = launch(["-HomePadOpenApp", "faces", "-HomePadFacesAdd", "YES"])
        keepSheet(app, "face-gallery")
    }

    func testFaceWidgetGallery() {
        let app = launch(["-HomePadOpenApp", "faces", "-HomePadFacesEdit", "faces.modular", "-HomePadFacesEditWidgets", "YES",
                          "-HomePadFacesWidgets", "personal.weather:medium@4,0;smarthome.favorites:large@4,2",
                          "-HomePadFacesWidgetGallery", "YES"])
        keepSheet(app, "face-widget-gallery")
    }

    // MARK: Home Screen and people

    func testHomeWidgetGallery() {
        let app = launch(Self.editHome + ["-HomePadHomeSheet", "addItems"])
        keepSheet(app, "home-widget-gallery")
    }

    /// Every app starts on the demo Home Screen, so a few come off first.
    func testHomeAddApp() {
        let app = launch(Self.editHome)
        for name in ["Photos", "Intercom", "Dashboards", "World Clock", "Timers"] {
            let remove = app.buttons["Remove \(name)"].firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout: 10), "\(name)'s remove badge")
            remove.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(1)
        }
        tap(app, "Add App")
        keepSheet(app, "home-add-app")
    }

    func testHomeWallpaper() {
        let app = launch(Self.editHome + ["-HomePadHomeSheet", "wallpaper"])
        keepSheet(app, "home-wallpaper")
    }

    /// Edit mode on the default Home Screen, whatever an earlier test changed.
    private static let editHome = ["-HomePadShowHome", "YES", "-HomePadEditHomeScreen", "YES", "-HomePadResetHomeScreen", "YES"]

    func testPersonEditor() {
        let app = launch(["-HomePadSettingsPane", "people"])
        tap(app, "Sam", prefix: true)
        keepSheet(app, "person-editor")
    }

    // MARK: Assistant and presence

    func testAssistantProvider() {
        let app = launch(["-HomePadSettingsPane", "assistant"])
        tap(app, "Claude", prefix: true)
        keepSheet(app, "assistant-provider")
    }

    func testEnrollment() {
        let app = launch(["-HomePadSettingsPane", "presence", "-HomePadPresencePane", "enroll", "-HomePadSimulatePresence", "near"])
        keepSheet(app, "presence-enroll")
    }

    // MARK: Music

    /// Now Playing is a full-screen presentation, which `-HomePadForceLandscape` does not turn either.
    func testNowPlaying() {
        let app = launch(["-HomePadOpenApp", "nowplaying", "-HomePadAudioDemo", "YES"])
        keepScreen(app, "now-playing", showing: app.buttons["Up Next"], "Now Playing opens")
    }

    func testUpNext() {
        let app = launch(["-HomePadOpenApp", "nowplaying", "-HomePadAudioDemo", "YES"])
        tap(app, "Up Next")
        keepSheet(app, "up-next")
    }

    // MARK: Kitchen

    func testRecipePreview() {
        // The first TheMealDB result, so it waits for the network and the picture.
        let app = launch(["-HomePadOpenApp", "recipes", "-KitchenDemo", "preview", "-KitchenDemoNoAlarms", "YES"])
        keepSheet(app, "recipe-preview", timeout: 30, settle: 6)
    }

    func testIngredients() {
        let app = launch(["-HomePadOpenApp", "recipes", "-KitchenDemo", "card", "-KitchenDemoNoAlarms", "YES"])
        tap(app, "Ingredients")
        keepSheet(app, "ingredients")
    }

    // MARK: Personal

    func testAddCity() {
        let app = launch(["-HomePadOpenApp", "worldclock"])
        tap(app, "Add City")
        search(app, "San")
        XCTAssertTrue(app.staticTexts["San Francisco"].waitForExistence(timeout: 10), "the matching cities")
        keepSheet(app, "worldclock-add-city")
    }

    func testWeatherLocation() {
        let app = launch(["-HomePadOpenApp", "weather"])
        tap(app, "Choose Location")
        // MapKit's places, so it waits for the network.
        search(app, "Portland")
        XCTAssertTrue(app.staticTexts["Cities"].waitForExistence(timeout: 20), "the matching places")
        keepSheet(app, "weather-location")
    }

    // MARK: Family Board, with the keyboard up

    func testBoardComposer() {
        let app = launch(["-HomePadOpenApp", "board", "-ConnectDemoData", "YES", "-ConnectDemoNotes", "9", "-ConnectDemoEditor", "new"])
        typeIntoNote(app, "Who can pick up Sam from soccer at 5?")
        holdForScreenshot("board-composer")
    }

    func testBoardEditor() {
        let app = launch(["-HomePadOpenApp", "board", "-ConnectDemoData", "YES", "-ConnectDemoNotes", "9", "-ConnectDemoEditor", "first"])
        typeIntoNote(app, " Bring the insurance card.")
        holdForScreenshot("board-editor")
    }

    // MARK: Helpers

    /// Launches with the README's demo household: Alex, an admin, recognized.
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                                           "-HomePadMember", "Alex", "-HomePadRecognized", "YES"]
        app.launch()
        return app
    }

    /// Taps the button with this label, or the first that starts with it.
    private func tap(_ app: XCUIApplication, _ label: String, prefix: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons.matching(NSPredicate(format: prefix ? "label BEGINSWITH %@" : "label == %@", label)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15), "\(label) to open the sheet", file: file, line: line)
        // A tap while the screen still settles lands beside the button.
        sleep(1)
        button.tap()
    }

    /// Waits for the sheet's header, lets the sheet and its pictures settle,
    /// and keeps a screenshot named after the README shot.
    private func keepSheet(
        _ app: XCUIApplication, _ shot: String, timeout: TimeInterval = 15, settle: UInt32 = 2,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        keepScreen(app, shot, showing: app.otherElements["sheetHeader"].firstMatch, "the sheet opens",
                   timeout: timeout, settle: settle, file: file, line: line)
    }

    /// Waits for `element`, lets the screen settle, and keeps a screenshot named after the shot.
    private func keepScreen(
        _ app: XCUIApplication, _ shot: String, showing element: XCUIElement, _ message: String,
        timeout: TimeInterval = 15, settle: UInt32 = 2, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message, file: file, line: line)
        sleep(settle)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = shot
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Types into the sheet's search field. The return key puts the keyboard
    /// away, so the results show in full.
    private func search(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.otherElements["sheetHeader"].firstMatch.waitForExistence(timeout: 15), "the sheet opens",
                      file: file, line: line)
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText(text + "\n")
    }

    /// Opens the keyboard at the end of the note and types, the way a person would.
    private func typeIntoNote(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields["board.noteText"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "the composer opens", file: file, line: line)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.95)).tap()
        sleep(1)
        field.typeText(text)
        XCTAssertTrue(app.otherElements["inputView"].firstMatch.waitForExistence(timeout: 6), "the on-screen keyboard is up",
                      file: file, line: line)
        // Let the keyboard's suggestions and the note's size settle.
        sleep(2)
    }

    /// Names the shot in the log and holds the screen while the script takes it.
    private func holdForScreenshot(_ shot: String) {
        XCTContext.runActivity(named: "README screen \(shot)") { _ in sleep(6) }
    }
}
