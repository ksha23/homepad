import Foundation
import HomePadCore
import Testing
@testable import HomePadShell

@Suite struct BrightnessStabilizerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func smallWobblesNeverMoveTheScreen() {
        var stabilizer = BrightnessStabilizer()
        _ = stabilizer.update(target: 0.5, condition: .active, now: start)
        for second in 1...30 {
            let wobble = second.isMultiple(of: 2) ? 0.55 : 0.46
            #expect(stabilizer.update(target: wobble, condition: .active, now: start + Double(second)) == .none)
        }
    }

    @Test func sustainedChangeIsAdoptedAfterTheHold() {
        var stabilizer = BrightnessStabilizer()
        _ = stabilizer.update(target: 0.5, condition: .active, now: start)
        #expect(stabilizer.update(target: 0.62, condition: .active, now: start + 1) == .none)
        #expect(stabilizer.update(target: 0.62, condition: .active, now: start + 3) == .none)
        #expect(stabilizer.update(target: 0.62, condition: .active, now: start + 5.5) == .roomLight(0.62))
    }

    @Test func lightsSwitchingOnSettleFaster() {
        var stabilizer = BrightnessStabilizer()
        _ = stabilizer.update(target: 0.2, condition: .ambient, now: start)
        #expect(stabilizer.update(target: 0.75, condition: .ambient, now: start + 1) == .none)
        #expect(stabilizer.update(target: 0.75, condition: .ambient, now: start + 2.6) == .roomLight(0.75))
    }

    @Test func conditionChangesApplyImmediately() {
        var stabilizer = BrightnessStabilizer()
        _ = stabilizer.update(target: 0.6, condition: .ambient, now: start)
        #expect(stabilizer.update(target: 0.8, condition: .active, now: start + 0.1) == .condition(0.8))
    }
}
