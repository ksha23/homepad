import Foundation
import HomePadCore
import Testing
@testable import HomePadFaces

@Suite struct RotationEngineTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private let allFaces: Set<String> = ["faces.auto", "faces.modular", "faces.photos", "faces.night", "faces.cameras", "faces.flow"]

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: hour, minute: minute))!
    }

    private func context(hour: Int, condition: DisplayCondition = .ambient, activity: [FaceActivity: Date] = [:],
                         member: String? = nil, faces: Set<String>? = nil) -> RotationContext {
        RotationContext(now: date(hour: hour), calendar: calendar, displayCondition: condition,
                        lastActivity: activity, memberFaceID: member, availableFaceIDs: faces ?? allFaces)
    }

    @Test func nightModeShowsTheNightFace() {
        let decision = RotationEngine.decide(.defaults, context: context(hour: 23, condition: .night))
        #expect(decision.faceID == "faces.night")
        #expect(decision.ruleID != nil)
    }

    @Test func morningsShowModular() {
        #expect(RotationEngine.decide(.defaults, context: context(hour: 7)).faceID == "faces.modular")
        #expect(RotationEngine.decide(.defaults, context: context(hour: 9)).faceID == "faces.modular")
    }

    @Test func otherwiseTheFallbackShows() {
        let decision = RotationEngine.decide(.defaults, context: context(hour: 14))
        #expect(decision == RotationDecision(faceID: "faces.photos", ruleID: nil))
    }

    @Test func aRecentDoorbellWinsOverEverything() {
        let rang = date(hour: 23).addingTimeInterval(-30)
        let decision = RotationEngine.decide(.defaults, context: context(hour: 23, condition: .night, activity: [.doorbell: rang]))
        #expect(decision.faceID == "faces.cameras")
    }

    @Test func anOldDoorbellNoLongerCounts() {
        let rang = date(hour: 14).addingTimeInterval(-600)
        #expect(RotationEngine.decide(.defaults, context: context(hour: 14, activity: [.doorbell: rang])).faceID == "faces.photos")
    }

    @Test func aRecognizedMembersFaceBeatsMornings() {
        let decision = RotationEngine.decide(.defaults, context: context(hour: 8, member: "faces.flow"))
        #expect(decision.faceID == "faces.flow")
    }

    @Test func disabledRulesAndMissingFacesAreSkipped() {
        var settings = RotationSettings.defaults
        settings.rules[1].isEnabled = false
        #expect(RotationEngine.decide(settings, context: context(hour: 23, condition: .night)).faceID == "faces.photos")
        let withoutNight = allFaces.subtracting(["faces.night"])
        #expect(RotationEngine.decide(.defaults, context: context(hour: 23, condition: .night, faces: withoutNight)).faceID == "faces.photos")
    }

    @Test func neverPicksItself() {
        let settings = RotationSettings(rules: [RotationRule(trigger: .night, faceID: "faces.auto")], fallbackFaceID: "faces.auto")
        let decision = RotationEngine.decide(settings, context: context(hour: 23, condition: .night))
        #expect(decision.faceID == "faces.modular")
    }

    @Test func fallsBackToAnyFaceWhenModularIsMissing() {
        let settings = RotationSettings(rules: [], fallbackFaceID: "faces.gone")
        let decision = RotationEngine.decide(settings, context: context(hour: 12, faces: ["faces.auto", "faces.flow"]))
        #expect(decision.faceID == "faces.flow")
    }

    @Test func timeRangesWrapPastMidnight() {
        #expect(RotationEngine.isMinute(23 * 60, between: 22 * 60, and: 6 * 60))
        #expect(RotationEngine.isMinute(3 * 60, between: 22 * 60, and: 6 * 60))
        #expect(!RotationEngine.isMinute(12 * 60, between: 22 * 60, and: 6 * 60))
        #expect(RotationEngine.isMinute(6 * 60, between: 6 * 60, and: 10 * 60))
        #expect(!RotationEngine.isMinute(10 * 60, between: 6 * 60, and: 10 * 60))
    }

    @Test func rulesSurviveEncoding() throws {
        let data = try JSONEncoder().encode(RotationSettings.defaults)
        #expect(try JSONDecoder().decode(RotationSettings.self, from: data) == .defaults)
    }

    @MainActor @Test func activityMonitorRecordsEvents() {
        let monitor = FaceActivityMonitor()
        let now = Date()
        monitor.handle(.doorbellRang(cameraID: "front"), at: now)
        monitor.handle(.motionDetected(source: "camera"), at: now)
        monitor.handle(.timerFinished(id: UUID(), label: "Pasta"), at: now)
        #expect(monitor.happened(.doorbell, within: 60, now: now.addingTimeInterval(30)))
        #expect(!monitor.happened(.doorbell, within: 60, now: now.addingTimeInterval(90)))
        #expect(monitor.lastDoorbellCameraID == "front")
        #expect(monitor.motionPulse == 1)
        #expect(monitor.lastTimerLabel == "Pasta")
    }
}
