import XCTest

/// A swipe down closes full-screen surfaces back to where they were opened, as
/// iPadOS closes sheets, the Music player and the Photos viewer. Edge swipes
/// still belong to the shell, sliders and scrubbers keep their drags, a short
/// pull springs back, and no swipe ever starts the assistant.
final class SwipeDownToDismissUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // This iPad's demo unless a test names a source, since a source one test saves carries over.
        let source = arguments.contains("-HomePadMusicSource") ? [] : ["-HomePadMusicSource", "thisIPad"]
        app.launchArguments = arguments + source + ["-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                                                    "-HomePadMember", "Alex", "-HomePadRecognized", "YES"]
        app.launch()
        return app
    }

    /// A finger drag between two points of the screen (0 to 1 on each axis). It
    /// rests at the end, so the release has no speed and only the distance counts.
    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        app.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: to), withVelocity: .default, thenHoldForDuration: 0.3)
    }

    /// A swipe down from the middle of the screen, a third of its height.
    private func swipeDownFromMiddle(_ app: XCUIApplication) {
        drag(app, from: CGVector(dx: 0.5, dy: 0.42), to: CGVector(dx: 0.5, dy: 0.78))
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 6) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    // MARK: Now Playing

    /// Now Playing's header button, there only while Now Playing is open.
    private func nowPlaying(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Up Next"]
    }

    /// The assistant's overlay, which no swipe may bring up.
    private func assistant(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Dismiss"]
    }

    /// Opened from an album page through Control Center, Now Playing swipes
    /// down to the same page, scrolled where it was.
    func testNowPlayingSwipesDownToMusicAsItWas() {
        let app = launch(["-HomePadOpenApp", "music", "-HomePadAudioDemo", "YES", "-HomePadMusicPage", "Dinner Party"])
        let shuffle = app.buttons["Shuffle"]
        XCTAssertTrue(shuffle.waitForExistence(timeout: 15))
        // Scroll the page down a little.
        drag(app, from: CGVector(dx: 0.6, dy: 0.8), to: CGVector(dx: 0.6, dy: 0.6))
        let scrolledY = shuffle.frame.minY
        // Down from the top right corner: Control Center, whose media tile opens Now Playing.
        drag(app, from: CGVector(dx: 0.95, dy: 0.003), to: CGVector(dx: 0.95, dy: 0.4))
        let open = app.buttons["Open Now Playing"]
        XCTAssertTrue(open.waitForExistence(timeout: 6), "the top edge should still open Control Center")
        open.tap()
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 6))

        swipeDownFromMiddle(app)
        waitUntilGone(nowPlaying(app))
        XCTAssertTrue(shuffle.waitForExistence(timeout: 4), "back on the album page")
        XCTAssertEqual(shuffle.frame.minY, scrolledY, accuracy: 2, "the page keeps its scroll position")
        XCTAssertFalse(assistant(app).exists, "a swipe never starts the assistant")
    }

    /// The pill on another app opens Music, the app that plays, with its
    /// player up. A swipe down leaves Music on screen, with a way back.
    func testThePillOpensMusicWithItsPlayer() {
        let app = launch(["-HomePadOpenApp", "worldclock", "-HomePadAudioDemo", "YES"])
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Now playing:")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
        pill.tap()
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 6))
        swipeDownFromMiddle(app)
        waitUntilGone(nowPlaying(app))
        XCTAssertTrue(app.buttons["music.miniPlayer"].waitForExistence(timeout: 4), "in Music, with its mini player")
        XCTAssertTrue(app.buttons["Back to World Clock"].exists, "and a way back to World Clock")
    }

    /// A pull shorter than the close distance springs back.
    func testAShortPullSpringsBack() {
        let app = launch(["-HomePadOpenApp", "nowplaying", "-HomePadAudioDemo", "YES"])
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 15))
        let restingY = nowPlaying(app).frame.minY
        drag(app, from: CGVector(dx: 0.5, dy: 0.42), to: CGVector(dx: 0.5, dy: 0.47))
        sleep(1)
        XCTAssertTrue(nowPlaying(app).exists, "a short pull should not close")
        XCTAssertEqual(nowPlaying(app).frame.minY, restingY, accuracy: 1, "and it settles back in place")
    }

    /// Dragging the scrubber down, far past the close distance, only seeks.
    func testDraggingTheScrubberDownNeverCloses() {
        let app = launch(["-HomePadOpenApp", "nowplaying", "-HomePadAudioDemo", "YES"])
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 15))
        let scrubber = app.descendants(matching: .any)["Playback position"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 6))
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)),
                   withVelocity: .default, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertTrue(nowPlaying(app).exists, "a drag that starts on the scrubber must not close")
    }

    /// The same for a volume slider (a Music Assistant speaker's).
    func testDraggingAVolumeSliderDownNeverCloses() {
        let app = launch(["-HomePadOpenApp", "nowplaying", "-HomePadAudioDemo", "YES", "-HomePadMusicSource", "musicAssistant"])
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 15))
        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 6))
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)),
                   withVelocity: .default, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertTrue(nowPlaying(app).exists, "a drag that starts on a slider must not close")
    }

    /// Music's player is a full-screen presentation, which HomePad's Control
    /// Center draws under. Over the player the top right corner opens
    /// iPadOS's own Control Center. Once the player is put away, the top edge
    /// opens HomePad's Control Center over Music.
    func testTheTopEdgeOpensControlCenterOnceThePlayerIsAway() {
        let app = launch(["-HomePadOpenApp", "nowplaying", "-HomePadAudioDemo", "YES"])
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 15))
        app.buttons["Close Player"].tap()
        waitUntilGone(nowPlaying(app))
        drag(app, from: CGVector(dx: 0.95, dy: 0.003), to: CGVector(dx: 0.95, dy: 0.45))
        XCTAssertTrue(app.buttons["Open Now Playing"].waitForExistence(timeout: 6), "Control Center opens over Music")
        XCTAssertFalse(assistant(app).exists)
    }

    // MARK: Photos

    private func photosLaunch(_ extra: [String] = []) -> XCUIApplication {
        launch(["-HomePadOpenApp", "photos", "-HomePadPhotosAlbum", "Library"] + extra)
    }

    /// The viewer's page, there only while the viewer or the slideshow is open.
    private func viewerPage(_ app: XCUIApplication) -> XCUIElement {
        app.images["Photo"]
    }

    /// A grid thumbnail. Demo photos count from 0.
    private func thumbnail(_ app: XCUIApplication, demo index: Int) -> XCUIElement {
        app.buttons["photos.grid.demo:\(index)"]
    }

    private func swipeSideways(_ app: XCUIApplication, toNext: Bool) {
        let (start, end) = toNext ? (0.8, 0.2) : (0.2, 0.8)
        drag(app, from: CGVector(dx: start, dy: 0.55), to: CGVector(dx: end, dy: 0.55))
    }

    /// Tapping a photo opens it full screen, and sideways swipes go to the next
    /// and previous photo in grid order.
    func testSwipingSidewaysPagesThroughTheAlbum() {
        let app = photosLaunch()
        let fifth = thumbnail(app, demo: 4)
        XCTAssertTrue(fifth.waitForExistence(timeout: 15))
        fifth.tap()
        XCTAssertTrue(app.staticTexts["5 of 18"].waitForExistence(timeout: 6))
        swipeSideways(app, toNext: true)
        XCTAssertTrue(app.staticTexts["6 of 18"].waitForExistence(timeout: 4), "a swipe left shows the next photo")
        swipeSideways(app, toNext: false)
        XCTAssertTrue(app.staticTexts["5 of 18"].waitForExistence(timeout: 4), "a swipe right goes back")
        swipeSideways(app, toNext: false)
        XCTAssertTrue(app.staticTexts["4 of 18"].waitForExistence(timeout: 4))
    }

    /// Swiping down closes the viewer onto the grid, scrolled to the photo it
    /// ended on, which started off screen.
    func testSwipeDownClosesOnTheGridAtThePhotoItEndedOn() {
        let app = photosLaunch(["-HomePadPhotosViewer", "15"])
        XCTAssertTrue(app.staticTexts["15 of 18"].waitForExistence(timeout: 15))
        swipeSideways(app, toNext: true)
        XCTAssertTrue(app.staticTexts["16 of 18"].waitForExistence(timeout: 4))
        swipeSideways(app, toNext: true)
        XCTAssertTrue(app.staticTexts["17 of 18"].waitForExistence(timeout: 4))

        swipeDownFromMiddle(app)
        waitUntilGone(viewerPage(app))
        let seventeenth = thumbnail(app, demo: 16)
        XCTAssertTrue(seventeenth.waitForExistence(timeout: 4))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(seventeenth.frame), "the grid shows the photo the viewer ended on")
        XCTAssertTrue(app.staticTexts["Library"].exists, "still in the same album")
        XCTAssertFalse(assistant(app).exists)
    }

    /// A drag locks to the axis it starts along: a short pull down neither
    /// pages nor closes, and a sideways swipe never closes.
    func testPagingAndSwipingDownNeverFight() {
        let app = photosLaunch(["-HomePadPhotosViewer", "5"])
        XCTAssertTrue(app.staticTexts["5 of 18"].waitForExistence(timeout: 15))
        drag(app, from: CGVector(dx: 0.5, dy: 0.45), to: CGVector(dx: 0.56, dy: 0.5))
        sleep(1)
        XCTAssertTrue(app.staticTexts["5 of 18"].exists, "a short pull springs back to the same photo")
        // A swipe that drifts down a little as it goes sideways still pages.
        drag(app, from: CGVector(dx: 0.85, dy: 0.45), to: CGVector(dx: 0.2, dy: 0.55))
        XCTAssertTrue(app.staticTexts["6 of 18"].waitForExistence(timeout: 4))
        XCTAssertTrue(viewerPage(app).exists)
    }

    /// On a landscape screen an upright photo leaves black at its sides, and
    /// a swipe that starts there pages and closes like one on the photo.
    func testSwipesFromBesideAnUprightPhotoInLandscape() {
        let device = XCUIDevice.shared
        let orientation = device.orientation
        device.orientation = .landscapeLeft
        addTeardownBlock { device.orientation = orientation }
        // Demo photo 3 is upright.
        let app = photosLaunch(["-HomePadPhotosViewer", "3"])
        XCTAssertTrue(app.staticTexts["3 of 18"].waitForExistence(timeout: 15))
        drag(app, from: CGVector(dx: 0.92, dy: 0.55), to: CGVector(dx: 0.2, dy: 0.55))
        XCTAssertTrue(app.staticTexts["4 of 18"].waitForExistence(timeout: 4), "a swipe from the black beside it pages")
        drag(app, from: CGVector(dx: 0.08, dy: 0.55), to: CGVector(dx: 0.8, dy: 0.55))
        XCTAssertTrue(app.staticTexts["3 of 18"].waitForExistence(timeout: 4))
        drag(app, from: CGVector(dx: 0.92, dy: 0.4), to: CGVector(dx: 0.92, dy: 0.8))
        waitUntilGone(viewerPage(app))
    }

    /// A finger that rests first and then pulls down slowly closes too, as
    /// a quick swipe does.
    func testASlowPullAfterARestCloses() {
        let app = photosLaunch(["-HomePadPhotosViewer", "5"])
        XCTAssertTrue(app.staticTexts["5 of 18"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.5, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)),
                   withVelocity: XCUIGestureVelocity(100), thenHoldForDuration: 0.5)
        waitUntilGone(viewerPage(app))
    }

    /// The top right edge still opens Control Center over the viewer.
    func testTheTopEdgeStillOpensControlCenterOverPhotos() {
        let app = photosLaunch(["-HomePadPhotosViewer", "5", "-HomePadAudioDemo", "YES"])
        XCTAssertTrue(app.staticTexts["5 of 18"].waitForExistence(timeout: 15))
        drag(app, from: CGVector(dx: 0.95, dy: 0.003), to: CGVector(dx: 0.95, dy: 0.45))
        XCTAssertTrue(app.buttons["Open Now Playing"].waitForExistence(timeout: 6), "Control Center should open")
        XCTAssertTrue(app.staticTexts["5 of 18"].exists, "the viewer stays open under it")
    }

    /// The slideshow closes with a swipe down too.
    func testSwipeDownClosesTheSlideshow() {
        let app = photosLaunch()
        let play = app.buttons["Play Slideshow"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertTrue(thumbnail(app, demo: 0).waitForExistence(timeout: 6))
        play.tap()
        XCTAssertTrue(viewerPage(app).waitForExistence(timeout: 6))
        swipeDownFromMiddle(app)
        waitUntilGone(viewerPage(app))
        XCTAssertTrue(play.waitForExistence(timeout: 4), "back on the album")
    }

    /// A video pages and swipes down like a photo, and a drag on its own
    /// scrubber does neither. Needs a video and a few photos in the
    /// simulator's library (`xcrun simctl addmedia`, with Photos access
    /// granted as the Personal README describes), and skips without them.
    func testAVideoPagesAndClosesButKeepsItsScrubber() throws {
        let app = launch(["-HomePadOpenApp", "photos", "-HomePadPhotosAlbum", "library",
                          "-personal.demoData", Self.setting("false")])
        let video = app.buttons["Video"].firstMatch
        guard video.waitForExistence(timeout: 15), app.buttons["Photo"].firstMatch.exists else {
            throw XCTSkip("This simulator's photo library has no video next to a photo")
        }
        video.tap()
        let counter = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ of [0-9]+")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 6))
        let opened = counter.label

        // Show the system controls, then drag the scrubber down and across.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let scrubber = app.sliders.matching(identifier: "Current position").firstMatch
        XCTAssertTrue(scrubber.waitForExistence(timeout: 4), "the video's controls show")
        let middle = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: -250, dy: 250)),
                     withVelocity: .default, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertEqual(counter.label, opened, "a drag on the scrubber, sideways and down, neither pages nor closes")
        if !scrubber.isHittable {
            // The controls hid themselves. Show them again.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(1)
        }
        XCTAssertTrue(scrubber.isHittable)
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: 300)),
                     withVelocity: .default, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertEqual(counter.label, opened, "nor does one straight down")

        // Pages away from the video and back.
        let next = opened.hasPrefix("1 of")
        swipeSideways(app, toNext: next)
        expectation(for: NSPredicate(format: "label != %@", opened), evaluatedWith: counter)
        waitForExpectations(timeout: 4)
        swipeSideways(app, toNext: !next)
        expectation(for: NSPredicate(format: "label == %@", opened), evaluatedWith: counter)
        waitForExpectations(timeout: 4)

        swipeDownFromMiddle(app)
        waitUntilGone(counter)
        XCTAssertTrue(video.waitForExistence(timeout: 4), "back on the grid")
    }

    /// A setting pinned for one launch: the JSON the settings store keeps, as
    /// property list data in the arguments domain.
    private static func setting(_ json: String) -> String {
        "<" + json.utf8.map { String(format: "%02x", $0) }.joined() + ">"
    }

    // MARK: Cameras

    /// A camera opened from the Home app swipes down to the Home app.
    func testACameraSwipesDownToTheHomeApp() {
        let app = launch(["-HomePadOpenApp", "home"])
        let tile = app.descendants(matching: .any)["Driveway camera"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        let live = app.staticTexts["Live"]
        XCTAssertTrue(live.waitForExistence(timeout: 6))
        swipeDownFromMiddle(app)
        waitUntilGone(live)
        XCTAssertTrue(tile.isHittable, "the Home app is back as it was")
    }

    /// One opened from the camera grid swipes down to the grid.
    func testACameraSwipesDownToTheCameraGrid() {
        let app = launch(["-HomePadOpenApp", "cameras"])
        let tiles = app.descendants(matching: .any).matching(identifier: "Living Room camera")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 15))
        // The grid's live tile is the largest. The Home app's strip under the grid has a small one.
        let tile = tiles.allElementsBoundByIndex.max { $0.frame.width < $1.frame.width }!
        tile.tap()
        let live = app.staticTexts["Live"]
        XCTAssertTrue(live.waitForExistence(timeout: 6))
        swipeDownFromMiddle(app)
        waitUntilGone(live)
        XCTAssertTrue(app.staticTexts["Cameras"].exists, "still on the camera grid")
        XCTAssertGreaterThan(tiles.count, 1, "the grid's tile is back over the Home app's")
    }

    /// Pulls a camera down slowly in landscape, as the iPads stand, holds it and
    /// lets it spring back, then pulls it away. In Light, so the Home app behind
    /// is white. The camera's black page should fill the shrinking card to its
    /// rounded edges, the shell's margin included, for the whole pull and the
    /// spring back. Record the simulator during this test to measure that frame
    /// by frame.
    ///
    /// It drags by screen position only: an app opened at launch is missing
    /// from the accessibility tree, which shows the Home Screen behind it.
    func testAPulledCameraKeepsItsPageToItsEdges() {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        let app = launch(["-HomePadOpenApp", "home", "-HomePadSmartHomeCamera", "demo:camera.driveway",
                          "-shell.display.appearance", Self.setting("\"light\"")])
        // The camera opens full screen over the Home app.
        sleep(4)
        // About 110 points down at 100 points a second, short of the close distance, so it springs back.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.3, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.51)),
                   withVelocity: XCUIGestureVelocity(100), thenHoldForDuration: 2)
        sleep(2)
        swipeDownFromMiddle(app)
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Accessory controls

    /// Opens the Home app from its Home Screen icon in landscape, as the iPads
    /// stand. An app opened at launch can be missing from the accessibility tree.
    private func openHomeApp(_ extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        let app = launch(["-HomePadShowHome", "YES"] + extra)
        let icon = app.buttons["Home"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 15))
        icon.tap()
        return app
    }

    /// Opens an accessory's full controls from its tile in the Home app, and
    /// returns the tile. Its icon is the quick action, and a tap anywhere else
    /// opens the controls.
    @discardableResult
    private func openControls(_ app: XCUIApplication, of name: String) -> XCUIElement {
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(name), ")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)).tap()
        return tile
    }

    /// The level control on an accessory's controls, whose value is only a
    /// percentage. A tile's value names its level first ("Brightness 70 percent").
    private func levelControl(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "value MATCHES %@", "[0-9]+ percent")).firstMatch
    }

    /// A light's controls swipe down to the Home app. The swipe starts in the
    /// column beside the brightness, away from the slider.
    func testALightsControlsSwipeDownToTheHomeApp() {
        let app = openHomeApp()
        let tile = openControls(app, of: "Kitchen Lights")
        let turnOff = app.buttons["Turn Off"]
        XCTAssertTrue(turnOff.waitForExistence(timeout: 6))
        drag(app, from: CGVector(dx: 0.85, dy: 0.5), to: CGVector(dx: 0.85, dy: 0.85))
        waitUntilGone(turnOff)
        XCTAssertTrue(tile.isHittable, "the Home app is back as it was")
        XCTAssertFalse(assistant(app).exists, "a swipe never starts the assistant")
    }

    /// Controls closed with a swipe open again: the same accessory's, then another's.
    func testControlsSwipedDownOpenAgain() {
        let app = openHomeApp()
        openControls(app, of: "Kitchen Lights")
        let turnOff = app.buttons["Turn Off"]
        XCTAssertTrue(turnOff.waitForExistence(timeout: 6))
        drag(app, from: CGVector(dx: 0.85, dy: 0.5), to: CGVector(dx: 0.85, dy: 0.85))
        waitUntilGone(turnOff)
        openControls(app, of: "Kitchen Lights")
        XCTAssertTrue(turnOff.waitForExistence(timeout: 6), "the same accessory's controls open again")
        XCTAssertTrue(turnOff.isHittable, "on screen, not left where the swipe took them")
        drag(app, from: CGVector(dx: 0.85, dy: 0.5), to: CGVector(dx: 0.85, dy: 0.85))
        waitUntilGone(turnOff)
        openControls(app, of: "Thermostat")
        XCTAssertTrue(app.buttons["Raise"].waitForExistence(timeout: 6), "another accessory's controls open")
        XCTAssertTrue(app.buttons["Raise"].isHittable)
    }

    /// Controls closed with a quick flick from the middle, as a person swipes, open again.
    func testControlsFlickedDownOpenAgain() {
        let app = openHomeApp()
        openControls(app, of: "Thermostat")
        let raise = app.buttons["Raise"]
        XCTAssertTrue(raise.waitForExistence(timeout: 6))
        app.swipeDown(velocity: .fast)
        waitUntilGone(raise)
        openControls(app, of: "Thermostat")
        XCTAssertTrue(raise.waitForExistence(timeout: 6), "the same accessory's controls open again")
        XCTAssertTrue(raise.isHittable, "on screen, not left where the swipe took them")
        app.swipeDown(velocity: .fast)
        waitUntilGone(raise)
        openControls(app, of: "Kitchen Lights")
        XCTAssertTrue(app.buttons["Turn Off"].waitForExistence(timeout: 6), "another accessory's controls open")
        XCTAssertTrue(app.buttons["Turn Off"].isHittable)
    }

    /// Dragging the brightness down, far past the close distance, only dims
    /// the light. The controls stay open.
    func testDraggingALightsBrightnessDownDimsItAndNeverCloses() {
        let app = openHomeApp()
        openControls(app, of: "Kitchen Lights")
        XCTAssertTrue(app.buttons["Turn Off"].waitForExistence(timeout: 6))
        let brightness = levelControl(app)
        XCTAssertEqual(brightness.value as? String, "70 percent")
        // Half the slider's height down, which is more than the close distance.
        brightness.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: brightness.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)),
                   withVelocity: .default, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertTrue(brightness.exists, "a drag that starts on the brightness must not close")
        let percent = Int((brightness.value as? String ?? "").split(separator: " ").first ?? "") ?? -1
        XCTAssertTrue((10...30).contains(percent), "the drag dims the light by about half, to \(percent)")
        XCTAssertTrue(app.buttons["Turn Off"].exists, "the controls are still open")
    }

    /// A thermostat's controls, whose page is its mode's color, swipe down
    /// too, from the middle of the screen, where the setpoint is.
    func testAThermostatsControlsSwipeDownToTheHomeApp() {
        let app = openHomeApp()
        let tile = openControls(app, of: "Thermostat")
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Raise"].exists, "the thermostat's controls are open")
        swipeDownFromMiddle(app)
        waitUntilGone(close)
        XCTAssertTrue(tile.isHittable, "the Home app is back as it was")
    }

    /// Pulls a light's controls down slowly in Light, where the Home app behind
    /// is white, holds them and lets them spring back, then pulls them away.
    /// The page should fill the shrinking card to its rounded edges, the
    /// shell's margin included, and the light's glow should move with the
    /// card. Record the simulator during this test to measure that frame by
    /// frame.
    func testAPulledLightsControlsKeepTheirPageToTheirEdges() {
        let app = openHomeApp(["-shell.display.appearance", Self.setting("\"light\"")])
        openControls(app, of: "Kitchen Lights")
        XCTAssertTrue(app.buttons["Turn Off"].waitForExistence(timeout: 6))
        sleep(1)
        // About 110 points down at 100 points a second, short of the close distance, so it springs back.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.4))
            .press(forDuration: 0.3, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.51)),
                   withVelocity: XCUIGestureVelocity(100), thenHoldForDuration: 2)
        sleep(2)
        drag(app, from: CGVector(dx: 0.85, dy: 0.42), to: CGVector(dx: 0.85, dy: 0.78))
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
