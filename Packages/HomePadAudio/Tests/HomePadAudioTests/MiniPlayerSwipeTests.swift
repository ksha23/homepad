import CoreGraphics
import Testing
@testable import HomePadAudio

@Suite struct MiniPlayerSwipeTests {
    private let swipe = MiniPlayerSwipe.standard

    @Test func leftPlaysTheNextSongAndRightTheOneBefore() {
        #expect(swipe.skip(translation: -swipe.skipDistance, velocity: 0) == .next)
        #expect(swipe.skip(translation: swipe.skipDistance, velocity: 0) == .previous)
    }

    @Test func aShortSlowDragSkipsNothing() {
        #expect(swipe.skip(translation: -(swipe.skipDistance - 1), velocity: -100) == nil)
        #expect(swipe.skip(translation: 30, velocity: 50) == nil)
        #expect(swipe.skip(translation: 0, velocity: 0) == nil)
    }

    @Test func aQuickFlickSkipsFromAShorterDrag() {
        #expect(swipe.skip(translation: -swipe.minimumFlickDistance, velocity: -swipe.flickVelocity) == .next)
        #expect(swipe.skip(translation: swipe.minimumFlickDistance, velocity: swipe.flickVelocity) == .previous)
        // The jitter of a tap, however fast, is not a flick.
        #expect(swipe.skip(translation: -8, velocity: -2000) == nil)
    }

    @Test func aFlickBackTheWayItCameSkipsNothing() {
        #expect(swipe.skip(translation: -200, velocity: swipe.flickVelocity) == nil)
        #expect(swipe.skip(translation: 200, velocity: -swipe.flickVelocity) == nil)
    }

    @Test func theContentFollowsALittleAndNeverPastItsTravel() {
        #expect(swipe.offset(for: 0) == 0)
        // At first it moves at half the finger's speed.
        #expect(abs(swipe.offset(for: 2) - 1) < 0.1)
        // The same each way.
        #expect(swipe.offset(for: -120) == -swipe.offset(for: 120))
        // Less than the finger, more the farther it goes, never as far as its travel.
        #expect(swipe.offset(for: 120) < 60)
        #expect(swipe.offset(for: 400) > swipe.offset(for: 120))
        #expect(swipe.offset(for: 10_000) < swipe.travel)
    }

    @Test func theContentFadesAsItMoves() {
        #expect(swipe.opacity(for: 0) == 1)
        #expect(swipe.opacity(for: -200) < 1)
        #expect(swipe.opacity(for: 10_000) >= swipe.minimumOpacity)
    }

    @Test func theContentsSpeedIsTheFingersSlowedByTheStretch() {
        // Half the finger's speed at rest, slower once stretched.
        #expect(swipe.offsetVelocity(1000, at: 0) == 500)
        #expect(swipe.offsetVelocity(1000, at: 200) < 500)
        #expect(swipe.offsetVelocity(-1000, at: -200) < 0)
    }
}
