import CoreGraphics
import HomePadUI
import SwiftUI

/// When a swipe up from the bottom edge goes Home, and the springs the app zoom
/// runs on. While the finger is down the window follows it
/// (`AppZoomGeometry.dragPose`), and letting go either lands it in its icon or
/// springs it back, carrying the finger's speed either way.
struct HomeSwipePolicy: Sendable {
    /// Upward travel that is enough to go Home when let go.
    var closeDistance: CGFloat = 56
    /// A flick this far up (predicted end of the drag) goes Home after a short pull.
    var flickDistance: CGFloat = 180
    /// The shortest pull a flick may have.
    var flickMinimum: CGFloat = 12
    /// Upward finger speed (points per second) that counts as a flick on its own.
    var flickVelocity: CGFloat = 650

    static let standard = HomeSwipePolicy()

    /// An app growing out of its icon: close to critically damped, with a touch of overshoot at the end.
    static let openSpring = Spring(response: 0.48, dampingRatio: 0.86)
    /// An app shrinking into its icon, or springing back to full screen: no visible overshoot.
    static let closeSpring = Spring(response: 0.42, dampingRatio: 0.92)

    /// Whether letting go at `translation` (with the drag's predicted end and
    /// its vertical velocity, negative is up) goes Home.
    func shouldGoHome(translation: CGFloat, predicted: CGFloat, velocity: CGFloat = 0) -> Bool {
        let up = -translation
        if up >= closeDistance { return true }
        return up >= flickMinimum && (-predicted >= flickDistance || -velocity >= flickVelocity)
    }
}

extension ShellNavigator {
    /// The home bar's tap and swipe, for the bar over the app on screen and over the covers it presents
    /// (`\.homeBar`, HomePadUI's `HomeBar`).
    var homeBarActions: HomeBarActions {
        HomeBarActions(
            goHome: { [weak self] in self?.closeApp() },
            track: { [weak self] in self?.trackHomeSwipe(translation: $0) },
            finish: { [weak self] in self?.finishHomeSwipe(translation: $0, predicted: $1, velocity: $2) },
            settle: { [weak self] in self?.settleHomeSwipe() }
        )
    }

    /// Follows the finger of a swipe up from the bottom. Only an app on screen reacts.
    func trackHomeSwipe(translation: CGSize) {
        guard screen.appID != nil else { return }
        trackZoom(translation: translation)
    }

    /// Lets go of the swipe: goes Home when it was far or fast enough, otherwise springs back.
    /// `velocity` is the finger's speed in points per second (negative height is up).
    func finishHomeSwipe(translation: CGSize, predicted: CGSize, velocity: CGSize) {
        guard screen.appID != nil else {
            if HomeSwipePolicy.standard.shouldGoHome(translation: translation.height, predicted: predicted.height,
                                                     velocity: velocity.height) { swipeUpFromBottom() }
            return
        }
        let goesHome = HomeSwipePolicy.standard.shouldGoHome(translation: translation.height, predicted: predicted.height,
                                                             velocity: velocity.height)
        let fingerVelocity = AppZoomGeometry.standard.dragVelocity(velocity, at: zoomAnimator.pose, screen: zoomAnimator.screen)
        guard goesHome else {
            cancelZoom(fingerVelocity: fingerVelocity)
            return
        }
        // Going Home carries the window the rest of the way into its icon at the finger's speed (`beginCloseZoom`).
        closeVelocity = fingerVelocity
        swipeUpFromBottom()
    }

    /// The finger is gone without the swipe finishing, as when the system takes the touch: a window
    /// still held where the finger left it springs back to full screen.
    func settleHomeSwipe() {
        guard zoomAnimator.isHeld else { return }
        cancelZoom(fingerVelocity: .zero)
    }
}
