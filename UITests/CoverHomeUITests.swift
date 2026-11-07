import XCTest

/// The home bar reaches an app's full-screen covers: from Music's Now Playing player a short pull on the
/// bar springs back to the player, and a swipe up goes Home into the Music icon. Going Home closes the
/// player, so Music opens again on its page and its mini player brings the player back. Recorded on video
/// to check that the window shrinks into the icon with the player in it.
final class CoverHomeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTheHomeBarGoesHomeFromNowPlaying() {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadShowHome", "YES", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES", "-HomePadAudioDemo", "YES",
                               "-HomePadMusicSource", "thisIPad"]
        app.launch()
        let music = app.buttons["Music"].firstMatch
        XCTAssertTrue(music.waitForExistence(timeout: 15), "the Home Screen shows")
        music.tap()
        let miniPlayer = app.buttons["music.miniPlayer"]
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 10), "Music opens with its mini player")
        sleep(1)
        miniPlayer.tap()
        // Now Playing's header button, there only while the player is up.
        let upNext = app.buttons["Up Next"]
        XCTAssertTrue(upNext.waitForExistence(timeout: 6), "the player opens")
        sleep(2)

        // A short, slow pull that stops: the window springs back to the player. Twice, since a slow pull
        // once raced the bar's tap and went Home.
        for round in 1...2 {
            pullHomeBar(app, to: 0.96, velocity: 120, hold: 0.4)
            sleep(2)
            XCTAssertTrue(upNext.isHittable, "a short pull springs back to the player (round \(round))")
        }

        // A swipe up: the player shrinks into the Music icon and the Home Screen takes touches.
        pullHomeBar(app, to: 0.45, velocity: .fast, hold: 0)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: upNext)
        wait(for: [gone], timeout: 6)
        sleep(2)
        XCTAssertTrue(music.isHittable, "the swipe goes Home")

        // Music opens on its page, and the mini player brings the player back.
        music.tap()
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8), "Music opens again")
        sleep(1)
        XCTAssertFalse(upNext.exists, "going Home closed the player")
        miniPlayer.tap()
        XCTAssertTrue(upNext.waitForExistence(timeout: 6), "the mini player opens the player again")
    }

    /// Drags the home bar from its middle up to `y` (a share of the screen's height). A drag from the very
    /// edge is the simulator's own Home gesture, so it starts on the bar.
    private func pullHomeBar(_ app: XCUIApplication, to y: CGFloat, velocity: XCUIGestureVelocity, hold: TimeInterval) {
        let start = app.buttons.matching(identifier: "home-bar").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: hold)
    }
}
