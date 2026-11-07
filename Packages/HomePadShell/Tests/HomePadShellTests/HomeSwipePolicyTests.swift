import CoreGraphics
import Testing
@testable import HomePadShell

@Suite struct HomeSwipePolicyTests {
    private let policy = HomeSwipePolicy.standard

    @Test func aLongPullGoesHome() {
        #expect(policy.shouldGoHome(translation: -60, predicted: -60))
    }

    @Test func aShortSlowPullSpringsBack() {
        #expect(!policy.shouldGoHome(translation: -30, predicted: -50))
    }

    @Test func aShortFlickGoesHome() {
        #expect(policy.shouldGoHome(translation: -30, predicted: -300))
    }

    @Test func aTinyFlickAndADownPullDoNot() {
        #expect(!policy.shouldGoHome(translation: -5, predicted: -400))
        #expect(!policy.shouldGoHome(translation: 80, predicted: 200))
    }

    @Test func aFastFlickGoesHomeFromAShortPull() {
        #expect(policy.shouldGoHome(translation: -20, predicted: -40, velocity: -900))
        #expect(!policy.shouldGoHome(translation: -20, predicted: -40, velocity: -300))
        #expect(!policy.shouldGoHome(translation: -5, predicted: -40, velocity: -900))
    }
}
