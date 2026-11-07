import CoreGraphics
import Testing
@testable import HomePadUI

/// Swiping down to close: where a drag may start, which way it locks, how the
/// surface follows the finger, and whether letting go closes or springs back.
struct SwipeDismissPolicyTests {
    let policy = SwipeDismissPolicy.standard
    /// An 11-inch iPad in landscape.
    let window: CGFloat = 834

    // MARK: Axis lock

    @Test func aDragLocksToTheAxisItStartsAlong() {
        #expect(SwipeDismissPolicy.axis(of: CGSize(width: 2, height: 12)) == .vertical)
        #expect(SwipeDismissPolicy.axis(of: CGSize(width: 0, height: -12)) == .vertical)
        #expect(SwipeDismissPolicy.axis(of: CGSize(width: -12, height: 3)) == .horizontal)
        #expect(SwipeDismissPolicy.axis(of: CGSize(width: 10, height: 10)) == nil, "an exact diagonal belongs to neither")
        #expect(SwipeDismissPolicy.axis(of: .zero) == nil)
    }

    // MARK: Starting

    @Test func aDownwardDragFromTheMiddleBegins() {
        #expect(policy.shouldBegin(startY: 400, windowHeight: window, translation: CGSize(width: 3, height: 12), isScrolledToTop: true))
    }

    @Test func upwardAndSidewaysDragsNeverBegin() {
        #expect(!policy.shouldBegin(startY: 400, windowHeight: window, translation: CGSize(width: 0, height: -12), isScrolledToTop: true))
        #expect(!policy.shouldBegin(startY: 400, windowHeight: window, translation: CGSize(width: 14, height: 6), isScrolledToTop: true),
                "a page swipe stays a page swipe")
        #expect(!policy.shouldBegin(startY: 400, windowHeight: window, translation: CGSize(width: -10, height: 10), isScrolledToTop: true))
    }

    /// Down from the top edge opens Control Center or talks to the assistant,
    /// and up from the bottom goes Home. Those bands never start a close.
    @Test func edgeSwipesAreLeftToTheShell() {
        #expect(policy.startsInEdgeZone(startY: 0, windowHeight: window))
        #expect(policy.startsInEdgeZone(startY: 20, windowHeight: window))
        #expect(policy.startsInEdgeZone(startY: 43, windowHeight: window))
        #expect(!policy.startsInEdgeZone(startY: 44, windowHeight: window))
        #expect(!policy.startsInEdgeZone(startY: window - 44, windowHeight: window))
        #expect(policy.startsInEdgeZone(startY: window - 10, windowHeight: window))
        #expect(!policy.shouldBegin(startY: 8, windowHeight: window, translation: CGSize(width: 0, height: 30), isScrolledToTop: true))
        #expect(!policy.shouldBegin(startY: window - 8, windowHeight: window, translation: CGSize(width: 0, height: 4), isScrolledToTop: true))
    }

    /// As in an iPadOS sheet: a pull down in a list that is scrolled down
    /// scrolls it back up, and only at the top does the pull close.
    @Test func scrolledContentScrollsUntilItIsAtItsTop() {
        #expect(!policy.shouldBegin(startY: 400, windowHeight: window, translation: CGSize(width: 0, height: 12), isScrolledToTop: false))
        #expect(policy.shouldBegin(startY: 400, windowHeight: window, translation: CGSize(width: 0, height: 12), isScrolledToTop: true))
    }

    // MARK: Following the finger

    @Test func theSurfaceFollowsDownAndResistsUp() {
        #expect(policy.offset(for: 120) == 120)
        #expect(policy.offset(for: -100) == -15, "above the start it gives only a little")
        #expect(policy.progress(for: 0) == 0)
        #expect(policy.progress(for: 210) == 0.5)
        #expect(policy.progress(for: 2000) == 1)
        #expect(policy.progress(for: -50) == 0)
    }

    @Test func itShrinksSlightlyAndTheBackdropFades() {
        #expect(policy.scale(for: 0) == 1)
        #expect(abs(policy.scale(for: 420) - 0.9) < 0.0001)
        #expect(policy.scale(for: 5000) >= 0.9, "never smaller than the minimum")
        #expect(policy.backdropOpacity(for: 0) == 1)
        #expect(policy.backdropOpacity(for: 210) == 0.5)
        #expect(policy.backdropOpacity(for: 420) == 0)
    }

    @Test func reduceMotionFadesInsteadOfMoving() {
        #expect(policy.reducedMotionOpacity(for: 0) == 1)
        #expect(policy.reducedMotionOpacity(for: 140) == 0.5)
        #expect(policy.reducedMotionOpacity(for: 400) == 0.5)
    }

    // MARK: Letting go

    @Test func aLongPullClosesAndAShortOneSpringsBack() {
        #expect(policy.shouldClose(translation: 140, velocity: 0), "Music's distance")
        #expect(policy.shouldClose(translation: 300, velocity: 200))
        #expect(!policy.shouldClose(translation: 139, velocity: 0))
        #expect(!policy.shouldClose(translation: 60, velocity: 100))
    }

    @Test func aQuickFlickClosesFromAShortPull() {
        #expect(policy.shouldClose(translation: 40, velocity: 900))
        #expect(!policy.shouldClose(translation: 10, velocity: 2000), "a tap's jitter never closes")
        #expect(!policy.shouldClose(translation: 60, velocity: 600))
    }

    @Test func flickingBackUpKeepsItOpen() {
        #expect(!policy.shouldClose(translation: 300, velocity: -800))
        #expect(policy.shouldClose(translation: 300, velocity: -300), "a slow drift back up still closes past the distance")
    }

    @Test func releaseSpeedCarriesIntoTheSpring() {
        #expect(SwipeDismissPolicy.relativeVelocity(800, from: 200, to: 1000) == 1)
        #expect(SwipeDismissPolicy.relativeVelocity(-300, from: 100, to: 0) == 3)
        #expect(SwipeDismissPolicy.relativeVelocity(500, from: 0, to: 0) == 0, "nothing left to travel")
        #expect(SwipeDismissPolicy.relativeVelocity(100_000, from: 0, to: 100) == 20, "capped")
    }
}
