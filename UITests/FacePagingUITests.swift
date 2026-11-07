import XCTest

/// Fast swipes between faces, as on the Home Screen's pages: a quick flick pages, and a second flick
/// made while the first is still settling pages again rather than bouncing back. Recorded on video, and
/// each settled face is in Documents/faces-trace.txt.
final class FacePagingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testFastSwipesPageEveryTime() {
        let app = XCUIApplication()
        app.launchArguments = ["-HomePadCondition", "active", "-HomePadDemoContent", "YES", "-HomePadMember", "Alex",
                               "-HomePadRecognized", "YES", "-HomePadShowFace", "faces.modular", "-HomePadFacesTrace", "YES"]
        app.launch()
        sleep(5)
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))

        // One quick flick.
        middle.press(forDuration: 0.01, thenDragTo: left, withVelocity: 3000, thenHoldForDuration: 0)
        sleep(3)
        // Two quick flicks, the second while the first is still settling.
        middle.press(forDuration: 0.01, thenDragTo: left, withVelocity: 3000, thenHoldForDuration: 0)
        middle.press(forDuration: 0.01, thenDragTo: left, withVelocity: 3000, thenHoldForDuration: 0)
        sleep(3)
        // Three in a row.
        for _ in 0..<3 {
            middle.press(forDuration: 0.01, thenDragTo: left, withVelocity: 3000, thenHoldForDuration: 0)
        }
        sleep(3)
    }
}
