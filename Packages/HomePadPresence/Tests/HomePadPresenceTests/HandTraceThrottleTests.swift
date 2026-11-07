import Foundation
import Testing
@testable import HomePadPresence

/// Hand lines filled most of a day's presence trace. Now one a second, plus
/// one whenever a hand comes or goes.
@Suite struct HandTraceThrottleTests {
    @Test func aHandInViewGetsOneLineASecond() {
        var throttle = HandTraceThrottle()
        let due = (0..<30).filter { throttle.isDue(hasHand: true, at: Double($0) * 0.1) }
        #expect(due == [0, 10, 20])
    }

    @Test func aHandComingOrGoingIsTracedAtOnce() {
        var throttle = HandTraceThrottle()
        let first = throttle.isDue(hasHand: false, at: 0)
        let arrives = throttle.isDue(hasHand: true, at: 0.1)
        let stays = throttle.isDue(hasHand: true, at: 0.2)
        let leaves = throttle.isDue(hasHand: false, at: 0.3)
        #expect(first && arrives && leaves)
        #expect(stays == false)
    }
}
