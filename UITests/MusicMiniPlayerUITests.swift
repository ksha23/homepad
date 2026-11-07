import XCTest

/// The Music app's mini player: one bar floating at the bottom of every page.
/// A tap opens Now Playing, a swipe down comes back to the same page as it
/// was, a swipe sideways skips, its buttons only play, pause and skip, and
/// the last row of a page scrolls clear of it. Music also opens again where
/// it was left. In landscape, as the iPads stand, so screenshots come out
/// sideways.
final class MusicMiniPlayerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ arguments: [String], condition: String = "active") -> XCUIApplication {
        let app = XCUIApplication()
        // This iPad's demo, whatever source an earlier test saved (one picks Music Assistant).
        app.launchArguments = ["-HomePadOpenApp", "music", "-HomePadAudioDemo", "YES", "-HomePadCondition", condition,
                               "-HomePadDemoContent", "YES", "-HomePadMember", "Alex", "-HomePadRecognized", "YES",
                               "-HomePadMusicSource", "thisIPad"] + arguments
        app.launch()
        return app
    }

    private func miniPlayer(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["music.miniPlayer"]
    }

    /// Now Playing's header button, there only while Now Playing is open.
    private func nowPlaying(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Up Next"]
    }

    /// The shell's Now Playing pill, which Music hides.
    private func pill(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Now playing:")).firstMatch
    }

    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        app.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: to), withVelocity: .default, thenHoldForDuration: 0.3)
    }

    private func swipeDownFromMiddle(_ app: XCUIApplication) {
        drag(app, from: CGVector(dx: 0.5, dy: 0.42), to: CGVector(dx: 0.5, dy: 0.78))
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 6) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    /// Listen Now, scrolled: a tap on the bar opens Now Playing, and a swipe
    /// down shows Listen Now again at the same scroll position.
    func testTappingTheBarOpensNowPlayingAndSwipingDownComesBack() {
        let app = launch(["-HomePadMusicSection", "listenNow"])
        let shelf = app.staticTexts["Made for You"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 15))
        XCTAssertTrue(miniPlayer(app).waitForExistence(timeout: 6), "the bar shows while music plays")
        XCTAssertFalse(pill(app).exists, "the shell's pill stays hidden inside Music")
        drag(app, from: CGVector(dx: 0.5, dy: 0.7), to: CGVector(dx: 0.5, dy: 0.5))
        let scrolledY = shelf.frame.minY

        miniPlayer(app).tap()
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 6), "a tap on the bar opens Now Playing")
        swipeDownFromMiddle(app)
        waitUntilGone(nowPlaying(app))
        XCTAssertTrue(shelf.waitForExistence(timeout: 4), "back on Listen Now")
        XCTAssertEqual(shelf.frame.minY, scrolledY, accuracy: 2, "Listen Now keeps its scroll position")
        XCTAssertTrue(miniPlayer(app).exists)
    }

    /// After the player is swiped away, the bar opens it again, and so does
    /// the chevron's way out. Each close must leave nothing behind that keeps
    /// the next tap from working.
    func testTheBarReopensThePlayerAfterASwipeDown() {
        let app = launch(["-HomePadMusicSection", "listenNow"])
        XCTAssertTrue(miniPlayer(app).waitForExistence(timeout: 15))
        for round in 1...2 {
            miniPlayer(app).tap()
            XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 6), "round \(round): the bar opens the player")
            swipeDownFromMiddle(app)
            waitUntilGone(nowPlaying(app))
        }
        miniPlayer(app).tap()
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 6), "the bar opens the player after two swipes")
        app.buttons["Close Player"].tap()
        waitUntilGone(nowPlaying(app))
        miniPlayer(app).tap()
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 6), "and after the chevron")
    }

    /// A tap on the bar right after a swipe down, as soon as the player is out
    /// of sight, opens it again. The swipe's slide finishing later must not
    /// swallow the tap or close the reopened player.
    func testATapRightAfterTheSwipeReopensThePlayer() {
        let app = launch(["-HomePadMusicSection", "listenNow"])
        XCTAssertTrue(miniPlayer(app).waitForExistence(timeout: 15))
        miniPlayer(app).tap()
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 6))
        swipeDownFromMiddle(app)
        miniPlayer(app).tap()
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 6), "the tap opens the player again")
        sleep(2)
        XCTAssertTrue(nowPlaying(app).exists, "and it stays open")
    }

    /// The same from an album page: the swipe comes back to the album.
    func testNowPlayingFromTheBarSwipesBackToTheAlbum() {
        let app = launch(["-HomePadMusicPage", "Night Signals"])
        let shuffle = app.buttons["Shuffle"]
        XCTAssertTrue(shuffle.waitForExistence(timeout: 15))
        XCTAssertTrue(miniPlayer(app).waitForExistence(timeout: 6), "every page has the bar")
        miniPlayer(app).tap()
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 6))
        swipeDownFromMiddle(app)
        waitUntilGone(nowPlaying(app))
        XCTAssertTrue(shuffle.waitForExistence(timeout: 4), "back on the album page")
        XCTAssertTrue(app.staticTexts["Night Signals"].exists)
    }

    /// Play and pause stay on the page, and a paused song keeps its bar, with Play.
    func testTheBarsButtonsPlayAndPauseWithoutOpeningNowPlaying() {
        let app = launch(["-HomePadMusicSection", "radio"])
        XCTAssertTrue(miniPlayer(app).waitForExistence(timeout: 15))
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 6))
        pause.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 4), "the button turns into Play")
        XCTAssertFalse(nowPlaying(app).exists, "the button does not open Now Playing")
        sleep(1)
        XCTAssertTrue(miniPlayer(app).exists, "a paused song keeps its bar")
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 4))
        XCTAssertFalse(nowPlaying(app).exists)
    }

    /// Scrolled to its end, Listen Now's last row sits above the bar, not under it.
    func testTheLastRowScrollsClearOfTheBar() throws {
        let app = launch(["-HomePadMusicSection", "listenNow"])
        XCTAssertTrue(app.staticTexts["Made for You"].waitForExistence(timeout: 15))
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 6))
        // The capsule around the bar's buttons, which reaches a little past them.
        let barFrame = bar.frame.union(app.buttons["Pause"].frame).union(app.buttons["Next"].frame)
            .insetBy(dx: -Self.capsuleMargin, dy: -Self.capsuleMargin)
        var lastBottom: CGFloat = 0
        for _ in 0..<10 {
            app.swipeUp()
            sleep(1)
            let bottom = try contentFrames(app).filter { !barFrame.contains($0) }.map(\.maxY).max() ?? 0
            if abs(bottom - lastBottom) < 1 { break }
            lastBottom = bottom
        }
        XCTAssertGreaterThan(lastBottom, bar.frame.minY - 400, "the page scrolled to its end")
        XCTAssertLessThanOrEqual(lastBottom, bar.frame.minY + 1, "the last row ends above the bar")
    }

    /// How far the bar's capsule reaches past its buttons.
    private static let capsuleMargin: CGFloat = 16

    /// The frames of every button, text and image on screen, read in one snapshot.
    private func contentFrames(_ app: XCUIApplication) throws -> [CGRect] {
        var frames: [CGRect] = []
        func walk(_ element: XCUIElementSnapshot) {
            if [.button, .staticText, .image].contains(element.elementType), !element.frame.isEmpty {
                frames.append(element.frame)
            }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        return frames
    }

    /// Music opens again on the section, the Library's kind and the page it was left on.
    func testMusicOpensWhereItWasLeft() {
        // Starts from Listen Now with nothing saved, without the Music launch
        // arguments, which would pin the place and save nothing.
        let first = launch(["-audio.music.place.section", Self.setting("\"listenNow\""),
                            "-audio.music.place.libraryKind", Self.setting("\"playlists\""),
                            "-audio.music.place.page", Self.setting("null")])
        let library = first.buttons["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        library.tap()
        let albums = first.buttons["Albums"]
        XCTAssertTrue(albums.waitForExistence(timeout: 6))
        albums.tap()
        let album = first.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Night Signals")).firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 6))
        album.tap()
        XCTAssertTrue(first.buttons["Shuffle"].waitForExistence(timeout: 6))
        first.terminate()

        let app = launch([])
        XCTAssertTrue(app.buttons["Shuffle"].waitForExistence(timeout: 15), "the album page opens again")
        XCTAssertTrue(app.staticTexts["Night Signals"].exists)
        // The back button, named for the section under the page (or that
        // section in the sidebar, on a wide screen).
        app.buttons["Library"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Albums"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Albums"].isSelected, "the Library is still on Albums")

        // Leaves the place as it found it.
        app.buttons["Playlists"].tap()
        app.buttons["Listen Now"].tap()
    }

    /// A setting pinned for one launch: the JSON the settings store keeps, as
    /// property list data in the arguments domain.
    private static func setting(_ json: String) -> String {
        "<" + json.utf8.map { String(format: "%02x", $0) }.joined() + ">"
    }

    // MARK: Swiping to skip

    /// A swipe left across the bar plays the next song and a swipe right goes
    /// back, as in Apple Music. A swipe that starts on Pause skips too,
    /// without pausing. None of them opens Now Playing, and a tap still does.
    func testSwipingTheBarSkipsForwardAndBack() {
        let app = launch(["-HomePadMusicSection", "listenNow"])
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 6))
        let first = bar.label

        swipe(from: bar, by: -240)
        waitFor(bar, "label != %@", first, "a swipe left plays the next song")
        XCTAssertFalse(nowPlaying(app).exists, "the swipe left does not open Now Playing")

        swipe(from: pause, by: 240)
        waitFor(bar, "label == %@", first, "a swipe right goes back to the song before")
        XCTAssertTrue(pause.exists, "a swipe that starts on Pause does not pause")
        XCTAssertFalse(nowPlaying(app).exists, "the swipe right does not open Now Playing")

        bar.tap()
        XCTAssertTrue(nowPlaying(app).waitForExistence(timeout: 6), "a tap still opens Now Playing")
    }

    /// A short sideways wobble, let go slowly, springs back: the same song,
    /// and no Now Playing, since it was a drag and not a tap.
    func testAShortWobbleDoesNothing() {
        let app = launch(["-HomePadMusicSection", "listenNow"])
        let bar = miniPlayer(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        let first = bar.label
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -32, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.4)
        sleep(2)
        XCTAssertEqual(bar.label, first, "the song stays")
        XCTAssertFalse(nowPlaying(app).exists, "the wobble does not open Now Playing")
    }

    /// Keeps landscape screenshots of the bar on Listen Now, in Dark, Light
    /// and night, for review.
    func testScreenshotsOfTheBar() {
        let looks: [(name: String, arguments: [String], condition: String)] = [
            ("dark", [], "active"),
            ("light", ["-shell.display.appearance", "<226c6967687422>"], "active"),
            ("night", [], "night"),
        ]
        for look in looks {
            let app = launch(["-HomePadMusicSection", "listenNow"] + look.arguments, condition: look.condition)
            XCTAssertTrue(miniPlayer(app).waitForExistence(timeout: 15))
            sleep(2)
            keepScreenshot("music-bar-\(look.name)")
            app.terminate()
        }
    }

    /// A quick drag sideways from the middle of `element`, let go at speed.
    private func swipe(from element: XCUIElement, by distance: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)),
                    withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func waitFor(_ element: XCUIElement, _ format: String, _ value: String, _ message: String) {
        let predicate = NSPredicate(format: format, value)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 6)
        XCTAssertEqual(result, .completed, message)
    }

    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
