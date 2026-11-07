import XCTest

/// A swipe down on a photo opened from the Library grid lands it back on its thumbnail. Recorded on video
/// to check the landing. The launch opens the album's second photo full screen.
final class PhotoDismissUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testASwipeDownLandsThePhotoOnItsThumbnail() {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadOpenApp", "photos", "-HomePadCondition", "active", "-HomePadDemoContent", "YES",
                               "-HomePadMember", "Alex", "-HomePadRecognized", "YES",
                               "-HomePadPhotosAlbum", "library", "-HomePadPhotosViewer", "2"]
        app.launch()
        sleep(6)

        // A swipe down from the middle of the photo.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        sleep(3)
        let photos = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'photos.grid.'"))
        XCTAssertTrue(photos.firstMatch.isHittable, "the grid shows again")
    }
}
