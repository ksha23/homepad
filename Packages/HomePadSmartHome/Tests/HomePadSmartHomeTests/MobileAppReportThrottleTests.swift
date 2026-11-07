import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// How often sensor changes go to Home Assistant, with explicit times.
@Suite("Home Assistant device rate limit")
struct MobileAppReportThrottleTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func reported(_ states: [MobileAppSensorState], at date: Date) -> MobileAppReportThrottle {
        var throttle = MobileAppReportThrottle()
        throttle.noteSending(at: date)
        throttle.noteReported(states)
        return throttle
    }

    @Test func theFirstChangeGoesAtOnceAndTheNextWaits() {
        let throttle = MobileAppReportThrottle()
        #expect(throttle.changes(in: MobileAppSensorInputs.sample.states).count == MobileAppSensor.allCases.count)
        #expect(throttle.earliestSend(now: start) == start)

        let after = reported(MobileAppSensorInputs.sample.states, at: start)
        #expect(after.changes(in: MobileAppSensorInputs.sample.states).isEmpty)
        var walkedUp = MobileAppSensorInputs.sample
        walkedUp.presence.proximity = .near
        #expect(after.changes(in: walkedUp.states).map(\.sensor) == [.proximity])
        #expect(after.earliestSend(now: start + 1) == start + 5)
        #expect(after.earliestSend(now: start + 7) == start + 7)
    }

    @Test func flickerBackToWhatWasSentSendsNothing() {
        let throttle = reported(MobileAppSensorInputs.sample.states, at: start)
        var stepped = MobileAppSensorInputs.sample
        stepped.presence.isSomeonePresent = false
        #expect(Set(throttle.changes(in: stepped.states).map(\.sensor)) == [.presence, .proximity])
        // Back in view before the next send: nothing to tell.
        #expect(throttle.changes(in: MobileAppSensorInputs.sample.states).isEmpty)
    }

    @Test func onlyWhatHomeAssistantTookCounts() {
        let sample = MobileAppSensorInputs.sample
        var throttle = reported([sample.state(of: .presence)], at: start)
        #expect(throttle.changes(in: sample.states).count == MobileAppSensor.allCases.count - 1)
        throttle.reset()
        #expect(throttle.changes(in: sample.states).count == MobileAppSensor.allCases.count)
        #expect(throttle.earliestSend(now: start + 1) == start + 1)
    }
}
