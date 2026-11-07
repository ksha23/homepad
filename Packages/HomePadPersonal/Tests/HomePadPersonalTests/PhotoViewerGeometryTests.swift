import CoreGraphics
import HomePadUI
import Testing
@testable import HomePadPersonal

/// The Photos viewer's photo follows the finger down and lands on its
/// thumbnail from wherever it was let go, at the finger's speed.
struct PhotoViewerGeometryTests {
    /// A 13-inch iPad in landscape, and a 4:3 photo fitted to it.
    let screen = CGRect(x: 0, y: 0, width: 1376, height: 1032)
    let fitted = CGRect(x: 0, y: 0, width: 1376, height: 1032)
    let policy = SwipeDismissPolicy.standard

    @Test func atRestThePhotoStaysPut() {
        #expect(PhotoViewerGeometry.pulled(fitted, by: .zero, policy: policy) == fitted)
    }

    @Test func pulledDownItFollowsTheFingerAndShrinksAboutItsCenter() {
        let pulled = PhotoViewerGeometry.pulled(fitted, by: CGSize(width: 30, height: policy.fadeDistance), policy: policy)
        #expect(abs(pulled.width - fitted.width * policy.minimumScale) < 0.001)
        #expect(abs(pulled.height - fitted.height * policy.minimumScale) < 0.001)
        #expect(abs(pulled.midX - (fitted.midX + 30)) < 0.001, "across with the finger")
        #expect(abs(pulled.midY - (fitted.midY + policy.fadeDistance)) < 0.001, "down with the finger")
    }

    @Test func aThumbnailOnScreenIsWhereItLands() {
        let thumbnail = CGRect(x: 482, y: 563, width: 203, height: 203)
        let landing = PhotoViewerGeometry.landing(thumbnail: thumbnail, from: fitted, in: screen)
        #expect(landing == PhotoLanding(rect: thumbnail, kind: .thumbnail))
    }

    @Test func aThumbnailOffScreenLandsAtTheNearestPlaceOnScreen() {
        let above = CGRect(x: 482, y: -400, width: 203, height: 203)
        let landing = PhotoViewerGeometry.landing(thumbnail: above, from: fitted, in: screen)
        #expect(landing == PhotoLanding(rect: CGRect(x: 482, y: 0, width: 203, height: 203), kind: .nearest))
        let below = CGRect(x: 1300, y: 1500, width: 203, height: 203)
        #expect(PhotoViewerGeometry.landing(thumbnail: below, from: fitted, in: screen).rect
                == CGRect(x: 1376 - 203, y: 1032 - 203, width: 203, height: 203))
    }

    @Test func withoutAThumbnailItSlidesOffTheBottom() {
        let pulled = CGRect(x: 100, y: 300, width: 1200, height: 900)
        let landing = PhotoViewerGeometry.landing(thumbnail: nil, from: pulled, in: screen)
        #expect(landing.kind == .away)
        #expect(landing.rect == CGRect(x: 100, y: 1032, width: 1200, height: 900))
    }

    @Test func theFingersSpeedAlongTheWayCarriesOn() {
        let start = CGRect(x: 0, y: 0, width: 100, height: 100)
        let end = CGRect(x: 0, y: 400, width: 100, height: 100)
        #expect(PhotoViewerGeometry.springVelocity(CGSize(width: 0, height: 800), from: start, to: end) == 2,
                "800 points a second on a 400 point way covers twice the way a second")
        #expect(PhotoViewerGeometry.springVelocity(CGSize(width: 0, height: -400), from: start, to: end) == -1,
                "let go moving away, it carries on away first")
        #expect(PhotoViewerGeometry.springVelocity(CGSize(width: 900, height: 0), from: start, to: end) == 0,
                "speed across the way adds nothing")
        #expect(PhotoViewerGeometry.springVelocity(CGSize(width: 0, height: 500), from: start, to: start) == 0)
        #expect(PhotoViewerGeometry.springVelocity(CGSize(width: 0, height: 1_000_000), from: start, to: end) == 20)
    }
}
