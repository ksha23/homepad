import Foundation
import HomePadCore
import SwiftUI
import Testing
@testable import HomePadFaces

/// Behind the Home Screen a face keeps its picture, shows no clock and slows
/// down. Dimmed, at night and asleep, motion stops.
@Suite struct FaceCadenceTests {
    @Test func thumbnailsRedrawOnceAMinute() {
        #expect(FaceCadence.frames(30).effective(isThumbnail: true) == .minute)
        #expect(FaceCadence.second.effective(isThumbnail: true, isFrosted: true) == .minute)
    }

    @Test func frostedFacesCapMotionAndDropSeconds() {
        #expect(FaceCadence.frames(30).effective(isThumbnail: false, isFrosted: true) == .frames(FaceCadence.frostedFrameRate))
        #expect(FaceCadence.frames(1).effective(isThumbnail: false, isFrosted: true) == .frames(1))
        #expect(FaceCadence.second.effective(isThumbnail: false, isFrosted: true) == .minute, "no clock shows there")
        #expect(FaceCadence.minute.effective(isThumbnail: false, isFrosted: true) == .minute)
    }

    @Test func liveFacesAreUnchanged() {
        #expect(FaceCadence.frames(30).effective(isThumbnail: false) == .frames(30))
        #expect(FaceCadence.frames(30).effective(isThumbnail: false, condition: .active) == .frames(30))
        #expect(FaceCadence.second.effective(isThumbnail: false, condition: .ambient) == .second)
    }

    @Test func motionStopsWhenTheDisplayIsDimmedAtNightOrAsleep() {
        for condition in [DisplayCondition.dimmed, .night, .sleeping] {
            #expect(FaceCadence.frames(15).effective(isThumbnail: false, condition: condition) == .still)
            #expect(FaceCadence.frames(15).effective(isThumbnail: false, isFrosted: true, condition: condition) == .still)
            #expect(FaceCadence.minute.effective(isThumbnail: false, condition: condition) == .minute)
        }
    }

    @Test func clocksKeepSecondsUnlessAsleep() {
        #expect(FaceCadence.second.effective(isThumbnail: false, condition: .dimmed) == .second)
        #expect(FaceCadence.second.effective(isThumbnail: false, condition: .night) == .second)
        #expect(FaceCadence.second.effective(isThumbnail: false, condition: .sleeping) == .minute)
    }

    @Test func schedulesStartNowThenFollowTheClock() {
        // 10:09:37.5 on some day.
        let start = Date(timeIntervalSinceReferenceDate: 60 * 60 * 24 * 1000 + 10 * 3600 + 9 * 60 + 37.5)
        func firstThree(_ cadence: FaceCadence) -> [TimeInterval] {
            Array(FaceSchedule(cadence: cadence).entries(from: start, mode: .normal).prefix(3))
                .map { $0.timeIntervalSince(start) }
        }
        // The first entry is now, so a clock slowing to minutes keeps its hands where they are.
        #expect(firstThree(.minute) == [0, 22.5, 82.5])
        #expect(firstThree(.second) == [0, 0.5, 1.5])
        #expect(firstThree(.frames(2)) == [0, 0.5, 1])
        #expect(firstThree(.still) == [0, 86_400, 172_800])
    }

    @Test func motionIsAllowedOnlyAtNormalBrightness() {
        #expect(DisplayCondition.active.allowsMotion)
        #expect(DisplayCondition.ambient.allowsMotion)
        #expect(!DisplayCondition.dimmed.allowsMotion)
        #expect(!DisplayCondition.night.allowsMotion)
        #expect(!DisplayCondition.sleeping.allowsMotion)
    }
}
