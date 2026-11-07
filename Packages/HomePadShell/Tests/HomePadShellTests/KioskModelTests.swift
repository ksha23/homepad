import CoreGraphics
import Foundation
import HomePadCore
import Testing
@testable import HomePadShell

@Suite struct NightScheduleTests {
    private let schedule = NightSchedule(startMinute: 22 * 60, endMinute: 7 * 60)

    @Test(arguments: [(22, 0, true), (23, 59, true), (0, 0, true), (6, 59, true), (7, 0, false), (12, 0, false), (21, 59, false)])
    func wrapsPastMidnight(hour: Int, minute: Int, expected: Bool) {
        #expect(schedule.contains(TestDates.date(hour: hour, minute: minute)) == expected)
    }

    @Test func sameDayWindow() {
        let nap = NightSchedule(startMinute: 13 * 60, endMinute: 15 * 60)
        #expect(nap.contains(TestDates.date(hour: 14)))
        #expect(!nap.contains(TestDates.date(hour: 16)))
    }

    @Test func emptyScheduleNeverMatches() {
        #expect(!NightSchedule(startMinute: 600, endMinute: 600).contains(TestDates.date(hour: 10)))
    }

    @Test func minuteRoundTripsThroughDate() {
        #expect(NightSchedule.minute(for: NightSchedule.date(forMinute: 22 * 60 + 15)) == 22 * 60 + 15)
    }
}

@Suite struct DisplayConditionPolicyTests {
    @Test func darknessAloneNeverStartsNightOutsideTheSchedule() {
        // A hand over the front camera reads as a dark room.
        let tuning = KioskTuning()
        #expect(!DisplayConditionPolicy.isNight(now: TestDates.date(hour: 12), ambientLight: .dark, tuning: tuning))
        #expect(DisplayConditionPolicy.isNight(now: TestDates.date(hour: 23), ambientLight: .dark, tuning: tuning))
    }

    @Test func dimRoomFollowsTheSchedule() {
        let tuning = KioskTuning()
        #expect(DisplayConditionPolicy.isNight(now: TestDates.date(hour: 23), ambientLight: .dim, tuning: tuning))
        #expect(!DisplayConditionPolicy.isNight(now: TestDates.date(hour: 12), ambientLight: .dim, tuning: tuning))
    }

    @Test func brightRoomIsNeverAutomaticNight() {
        let tuning = KioskTuning()
        #expect(!DisplayConditionPolicy.isNight(now: TestDates.date(hour: 23), ambientLight: .bright, tuning: tuning))
    }

    @Test func dimmedNeedsNobodyPresent() {
        let now = TestDates.date(hour: 12)
        var inputs = KioskInputs(
            now: now, lastInteraction: now.addingTimeInterval(-300), lastEngagement: now.addingTimeInterval(-300),
            presence: .empty, tuning: KioskTuning()
        )
        #expect(DisplayConditionPolicy.evaluate(inputs).condition == .dimmed)
        inputs.presence = PresenceSnapshot(isSomeonePresent: true, proximity: .far)
        #expect(DisplayConditionPolicy.evaluate(inputs).condition == .ambient)
    }
}

@Suite struct BrightnessLevelsTests {
    @Test func roomLightScalesExceptWhileSleeping() {
        let levels = BrightnessLevels.standard
        let ambient = KioskState(condition: .ambient, isInteracting: false, isNight: false)
        #expect(levels.target(for: ambient, ambientLight: .dark, adaptToRoomLight: true) < levels.ambient)
        #expect(levels.target(for: ambient, ambientLight: .bright, adaptToRoomLight: true) > levels.ambient)
        #expect(levels.target(for: ambient, ambientLight: .dark, adaptToRoomLight: false) == levels.ambient)
    }

    @Test func nightIsBrighterWhileSomeoneUsesTheScreen() {
        let levels = BrightnessLevels.standard
        let resting = KioskState(condition: .night, isInteracting: false, isNight: true)
        let using = KioskState(condition: .night, isInteracting: true, isNight: true)
        #expect(levels.target(for: using, ambientLight: nil, adaptToRoomLight: true)
                > levels.target(for: resting, ambientLight: nil, adaptToRoomLight: true))
    }

    @Test func capLimitsTheTarget() {
        let active = KioskState(condition: .active, isInteracting: true, isNight: false)
        #expect(BrightnessLevels.standard.target(for: active, ambientLight: .bright, adaptToRoomLight: true, cap: 0.3) == 0.3)
    }
}

@Suite struct BurnInShiftTests {
    @Test func zeroAmplitudeDoesNotMove() {
        #expect(BurnInShift.offset(at: Date(), amplitude: 0) == .zero)
    }

    @Test func staysWithinAmplitudeAndMovesEachPeriod() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var offsets: Set<String> = []
        for step in 0..<BurnInShift.steps {
            let offset = BurnInShift.offset(at: start.addingTimeInterval(Double(step) * 90), amplitude: 8)
            #expect(abs(offset.width) <= 8 && abs(offset.height) <= 8)
            #expect(offset != .zero)
            offsets.insert("\(offset.width),\(offset.height)")
        }
        #expect(offsets.count == BurnInShift.steps)
    }
}

/// Local dates for schedule tests.
enum TestDates {
    static func date(hour: Int, minute: Int = 0) -> Date {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day], from: Date())
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }
}
