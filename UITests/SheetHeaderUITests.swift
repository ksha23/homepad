import XCTest

/// Every sheet has HomePad's own header: its title, at most one prominent
/// action and the round close button, with no Cancel or Done in its corners.
/// Each test opens one sheet the way a person would, checks the header and
/// keeps a screenshot. In landscape the screenshot comes out sideways.
final class SheetHeaderUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Kitchen

    func testIngredients() {
        let app = launch(["-HomePadOpenApp", "recipes", "-KitchenDemo", "card", "-KitchenDemoNoAlarms", "YES"])
        tap(app, "Ingredients")
        expectSheet(app, title: "Ingredients", action: "Add ", prefix: true)
    }

    func testRecipePreview() {
        let app = launch(["-HomePadOpenApp", "recipes", "-KitchenDemo", "preview", "-KitchenDemoNoAlarms", "YES"])
        // Save to My Recipes, or Open in My Recipes once an earlier run saved it.
        expectSheet(app, title: nil, action: nil, timeout: 30)
        XCTAssertTrue(app.otherElements["sheetHeader"].buttons.matching(NSPredicate(format: "label ENDSWITH %@", "My Recipes")).firstMatch.exists)
    }

    func testNewTimer() {
        let app = launch(["-HomePadOpenApp", "timers", "-KitchenDemo", "timers", "-KitchenDemoNoAlarms", "YES"])
        tap(app, "New timer")
        expectSheet(app, title: "New Timer", action: nil)
        // The demo timers are saved, so cancel them before they ring over later tests.
        app.otherElements["sheetHeader"].buttons["Close"].tap()
        let cancels = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Cancel "))
        for _ in 0..<6 where cancels.count > 0 {
            cancels.firstMatch.tap()
            sleep(1)
        }
        XCTAssertEqual(cancels.count, 0, "no demo timer is left")
    }

    // MARK: Camera Lab

    func testTimelapsePlayer() {
        let app = launch(["-HomePadOpenApp", "cameralab", "-CameraLabTool", "timelapse"])
        tap(app, "Play Timelapse")
        expectSheet(app, title: "HomePad Timelapse", action: nil)
    }

    // MARK: Personal

    func testCalendars() {
        let app = launch(["-HomePadOpenApp", "calendar"])
        tap(app, "Calendars")
        expectSheet(app, title: "Calendars", action: nil)
    }

    func testAddCity() {
        let app = launch(["-HomePadOpenApp", "worldclock"])
        tap(app, "Add City")
        expectSheet(app, title: "Add City", action: nil)
    }

    func testWeatherLocation() {
        let app = launch(["-HomePadOpenApp", "weather"])
        tap(app, "Choose Location")
        expectSheet(app, title: "Weather Location", action: nil)
    }

    /// From a section of a settings pane, which presents from its row.
    func testWeatherLocationFromSettings() {
        let app = launch(["-HomePadSettingsPane", "personal"])
        tap(app, "Location", prefix: true)
        expectSheet(app, title: "Weather Location", action: nil)
    }

    func testCalendarChooser() {
        let app = launch(["-HomePadSettingsPane", "personal"])
        tap(app, "Shared with Everyone", prefix: true)
        expectSheet(app, title: "Shared with Everyone", action: "Save")
    }

    // MARK: Faces

    func testFaceGallery() {
        let app = launch(["-HomePadOpenApp", "faces", "-HomePadFacesAdd", "YES"])
        expectSheet(app, title: "Face Gallery", action: nil)
    }

    func testSlotGallery() {
        let app = launch(["-HomePadOpenApp", "faces", "-HomePadFacesEdit", "faces.weather", "-HomePadFacesEditPage", "1"])
        tap(app, "City", prefix: true)
        expectSheet(app, title: "City", action: nil)
    }

    // MARK: Widgets and the Home Screen

    func testWidgetGallery() {
        let app = launch(["-HomePadShowHome", "YES", "-HomePadEditHomeScreen", "YES", "-HomePadHomeSheet", "addItems"])
        expectSheet(app, title: "Widgets", action: nil)
    }

    /// A widget's page in the face editor's gallery: a back button to the
    /// gallery before the title, and the close button.
    func testWidgetPage() {
        let app = launch(["-HomePadOpenApp", "faces", "-HomePadFacesEdit", "faces.modular", "-HomePadFacesEditWidgets", "YES",
                          "-HomePadFacesWidgetGallery", "YES", "-HomePadFacesWidgetGalleryItem", "personal.weather"])
        expectSheet(app, title: "Weather", action: nil, timeout: 15)
        XCTAssertTrue(app.buttons["Widgets"].exists, "a widget's page has a back button")
    }

    func testAddApp() {
        let app = launch(["-HomePadShowHome", "YES", "-HomePadEditHomeScreen", "YES", "-HomePadHomeSheet", "addApps"])
        expectSheet(app, title: "Add App", action: nil)
    }

    func testWallpaper() {
        let app = launch(["-HomePadShowHome", "YES", "-HomePadEditHomeScreen", "YES", "-HomePadHomeSheet", "wallpaper"])
        expectSheet(app, title: "Wallpaper", action: nil)
    }

    func testAddAControl() {
        let app = launch(["-HomePadShowPanel", "controlCenter", "-HomePadEditControlCenter", "YES"])
        tap(app, "Add a Control")
        expectSheet(app, title: "Add a Control", action: nil)
    }

    func testAddPerson() {
        let app = launch(["-HomePadSettingsPane", "people"])
        tap(app, "Add Person")
        expectSheet(app, title: "Add Person", action: "Add")
    }

    // MARK: Audio

    func testAddStation() {
        let app = launch(["-HomePadSettingsPane", "audio"])
        tap(app, "Add Station by URL…")
        expectSheet(app, title: "Add Station", action: "Add")
    }

    func testUpNext() {
        let app = launch(["-HomePadOpenApp", "nowplaying", "-HomePadAudioDemo", "YES"])
        tap(app, "Up Next")
        expectSheet(app, title: "Up Next", action: nil)
    }

    // MARK: Smart Home

    func testWebPanel() {
        let app = launch(["-HomePadSettingsPane", "smarthome"])
        tap(app, "Add Web Panel")
        expectSheet(app, title: "Web Panel", action: "Save")
    }

    func testFavorites() {
        let app = launch(["-HomePadSettingsPane", "smarthome"])
        tap(app, "Favorites")
        expectSheet(app, title: "Favorites", action: nil)
    }

    func testRoomsAndAccessories() {
        let app = launch(["-HomePadSettingsPane", "smarthome"])
        tap(app, "Rooms and Accessories")
        expectSheet(app, title: "Rooms and Accessories", action: "Edit")
    }

    // MARK: Presence

    func testEnrollment() {
        let app = launch(["-HomePadSettingsPane", "presence", "-HomePadPresencePane", "enroll"])
        expectSheet(app, title: "Recognize", action: nil, titlePrefix: true)
    }

    // MARK: Assistant

    func testFallbackOrder() {
        let app = launch(["-HomePadSettingsPane", "assistant"])
        tap(app, "Fallback Order")
        expectSheet(app, title: "Fallback Order", action: "Save")
    }

    func testMemberAssistant() {
        let app = launch(["-HomePadSettingsPane", "assistant"])
        tap(app, "Alex", prefix: true)
        expectSheet(app, title: "Alex", action: "Save")
    }

    func testProvider() {
        let app = launch(["-HomePadSettingsPane", "assistant"])
        tap(app, "Claude", prefix: true)
        expectSheet(app, title: "Claude", action: nil, titlePrefix: true)
    }

    // MARK: Helpers

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                                           "-HomePadMember", "Alex", "-HomePadRecognized", "YES"]
        app.launch()
        return app
    }

    /// Taps the button with this label, or the first that starts with it. A
    /// list only makes the rows it shows, so a settings pane is scrolled
    /// until the row is there.
    private func tap(_ app: XCUIApplication, _ label: String, prefix: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let format = prefix ? "label BEGINSWITH %@" : "label == %@"
        let button = app.buttons.matching(NSPredicate(format: format, label)).firstMatch
        var found = button.waitForExistence(timeout: 12)
        var scrolls = 0
        while scrolls < 8, !found {
            // The list on screen is the settings pane. A slow swipe stops on
            // the row instead of gliding past it.
            let lists = app.collectionViews
            (lists.count > 0 ? lists.element(boundBy: lists.count - 1) : app).swipeUp(velocity: .slow)
            scrolls += 1
            found = button.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(found, "\(label) to open the sheet", file: file, line: line)
        // A row at the bottom edge sits under the home indicator's touch area.
        if button.frame.maxY > app.windows.firstMatch.frame.maxY - 80, app.collectionViews.count > 0 {
            app.collectionViews.element(boundBy: app.collectionViews.count - 1).swipeUp(velocity: .slow)
            scrolls += 1
        }
        // A tap while the screen still settles or the list still glides lands beside the row.
        sleep(scrolls > 0 ? 2 : 1)
        button.tap()
    }

    /// The sheet's header: its title, its action when it has one and its
    /// close button, with no Cancel anywhere. Keeps a screenshot named after
    /// the test.
    private func expectSheet(
        _ app: XCUIApplication, title: String?, action: String?, prefix: Bool = false, titlePrefix: Bool = false,
        timeout: TimeInterval = 10, name: String? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        let header = app.otherElements["sheetHeader"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: timeout), "the sheet's header", file: file, line: line)
        sleep(1)
        keepScreenshot(named: name ?? String(shortName(of: self)))
        if let title {
            let format = titlePrefix ? "label BEGINSWITH %@" : "label == %@"
            XCTAssertTrue(header.staticTexts.matching(NSPredicate(format: format, title)).firstMatch.exists,
                          "the sheet's title \(title)", file: file, line: line)
        }
        if let action {
            let format = prefix ? "label BEGINSWITH %@" : "label == %@"
            XCTAssertTrue(header.buttons.matching(NSPredicate(format: format, action)).firstMatch.exists,
                          "the sheet's action \(action)", file: file, line: line)
        }
        XCTAssertTrue(header.buttons["Close"].exists, "the sheet's close button", file: file, line: line)
        XCTAssertFalse(app.buttons["Cancel"].exists, "no Cancel corner", file: file, line: line)
    }

    private func shortName(of test: XCTestCase) -> Substring {
        // "-[SheetHeaderUITests testAddCity]" to "AddCity".
        test.name.split(separator: " ").last?.dropFirst(4).dropLast() ?? "Sheet"
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
