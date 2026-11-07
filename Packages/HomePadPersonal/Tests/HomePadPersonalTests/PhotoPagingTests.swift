import CoreGraphics
import Testing
@testable import HomePadPersonal

/// The full-screen Photos viewer pages like the Photos app: the page follows
/// the finger, a flick or a drag past half a page turns it, the ends give a
/// little and no more, and the pages next to the one on screen are drawn ahead.
struct PhotoPagingTests {
    /// An 11-inch iPad in landscape.
    let width: CGFloat = 1210

    @Test func thePageFollowsTheFinger() {
        let step = width + PhotoPaging.gap
        #expect(PhotoPaging.position(from: 3, translation: 0, pageWidth: width, count: 10) == 3)
        #expect(PhotoPaging.position(from: 3, translation: -step / 2, pageWidth: width, count: 10) == 3.5, "left, toward the next photo")
        #expect(PhotoPaging.position(from: 3, translation: step, pageWidth: width, count: 10) == 2)
    }

    @Test func theEndsGiveOnlyALittle() {
        let step = width + PhotoPaging.gap
        #expect(abs(PhotoPaging.position(from: 0, translation: step, pageWidth: width, count: 10) - (-0.3)) < 0.0001)
        #expect(abs(PhotoPaging.position(from: 9, translation: -step, pageWidth: width, count: 10) - 9.3) < 0.0001)
    }

    @Test func aDragPastHalfAPageTurnsIt() {
        #expect(PhotoPaging.target(from: 3, translation: -650, velocity: 0, pageWidth: width, count: 10) == 4)
        #expect(PhotoPaging.target(from: 3, translation: 650, velocity: 0, pageWidth: width, count: 10) == 2)
        #expect(PhotoPaging.target(from: 3, translation: -500, velocity: 0, pageWidth: width, count: 10) == 3, "short of half springs back")
    }

    @Test func aFlickTurnsItFromAShortDrag() {
        #expect(PhotoPaging.target(from: 3, translation: -60, velocity: -900, pageWidth: width, count: 10) == 4)
        #expect(PhotoPaging.target(from: 3, translation: 60, velocity: 900, pageWidth: width, count: 10) == 2)
        #expect(PhotoPaging.target(from: 3, translation: -5, velocity: -900, pageWidth: width, count: 10) == 3, "a tap's jitter is no flick")
    }

    @Test func aFlickBackAgainstTheDragGoesBack() {
        #expect(PhotoPaging.target(from: 3, translation: -800, velocity: 900, pageWidth: width, count: 10) == 2)
        #expect(PhotoPaging.target(from: 3, translation: -800, velocity: 300, pageWidth: width, count: 10) == 4,
                "a slow drift back still turns past half a page")
    }

    @Test func neverMoreThanOnePageOrPastTheEnds() {
        #expect(PhotoPaging.target(from: 3, translation: -3000, velocity: -5000, pageWidth: width, count: 10) == 4)
        #expect(PhotoPaging.target(from: 0, translation: 900, velocity: 900, pageWidth: width, count: 10) == 0)
        #expect(PhotoPaging.target(from: 9, translation: -900, velocity: -900, pageWidth: width, count: 10) == 9)
        #expect(PhotoPaging.target(from: 0, translation: -900, velocity: 0, pageWidth: width, count: 1) == 0)
    }

    /// The pages next to the one on screen are drawn, so they have loaded
    /// before a swipe shows them.
    @Test func neighboursAreDrawnAhead() {
        #expect(PhotoPaging.window(around: 3, count: 10) == 2...4)
        #expect(PhotoPaging.window(around: 3.4, count: 10) == 2...5, "mid-swipe both pages on screen keep a neighbour")
        #expect(PhotoPaging.window(around: 0, count: 10) == 0...1)
        #expect(PhotoPaging.window(around: 9, count: 10) == 8...9)
        #expect(PhotoPaging.window(around: 0, count: 1) == 0...0)
        #expect(PhotoPaging.window(around: -0.2, count: 10) == 0...1, "pulled past the first photo")
        #expect(PhotoPaging.prefetch(around: 3, count: 10) == [1, 5])
        #expect(PhotoPaging.prefetch(around: 0, count: 2) == [])
    }

    @Test func pagesSitSideBySideWithAGap() {
        #expect(PhotoPaging.offset(of: 3, at: 3, pageWidth: width) == 0)
        #expect(PhotoPaging.offset(of: 4, at: 3, pageWidth: width) == width + PhotoPaging.gap)
        #expect(PhotoPaging.offset(of: 2, at: 2.5, pageWidth: width) == -(width + PhotoPaging.gap) / 2)
    }

    @Test func aPhotoFitsTheScreenWhole() {
        let screen = CGSize(width: 1200, height: 800)
        #expect(PhotoPaging.fittedRect(aspectRatio: 1.5, in: screen) == CGRect(x: 0, y: 0, width: 1200, height: 800))
        #expect(PhotoPaging.fittedRect(aspectRatio: 0.75, in: screen) == CGRect(x: 300, y: 0, width: 600, height: 800), "upright, with bars at the sides")
        #expect(PhotoPaging.fittedRect(aspectRatio: 3, in: screen) == CGRect(x: 0, y: 200, width: 1200, height: 400), "a panorama, with bars above and below")
    }

    @Test func aSlideshowStartsOverAfterTheLastPhoto() {
        #expect(PhotoPaging.nextInSlideshow(after: 3, count: 10) == 4)
        #expect(PhotoPaging.nextInSlideshow(after: 9, count: 10) == 0)
    }
}
