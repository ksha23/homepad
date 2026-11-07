import Foundation
import HomePadCore
import Testing
@testable import HomePadShell

/// The kiosk state machine, driven with an injected clock and presence snapshots.
/// Defaults: back to face after 60 s, dim after 2 min, sleep after 10 min, night 22:00 to 07:00.
@MainActor
@Suite struct KioskControllerTests {
    @Test func startsActiveThenReturnsToAmbient() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        #expect(kiosk.condition == .active)
        kiosk.advance(59)
        #expect(kiosk.condition == .active)
        #expect(kiosk.interactionEndedCount == 0)
        kiosk.advance(2)
        #expect(kiosk.condition == .ambient)
        #expect(kiosk.interactionEndedCount == 1)
        kiosk.advance(10)
        #expect(kiosk.interactionEndedCount == 1)
    }

    @Test func dimsThenSleepsWhenNobodyIsAround() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        kiosk.advance(61)
        #expect(kiosk.condition == .ambient)
        kiosk.advance(60)
        #expect(kiosk.condition == .dimmed)
        kiosk.advance(480)
        #expect(kiosk.condition == .sleeping)
    }

    @Test func touchWakesFromSleep() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        kiosk.advance(700)
        #expect(kiosk.condition == .sleeping)
        kiosk.controller.noteTouch()
        #expect(kiosk.condition == .active)
        #expect(kiosk.controller.state.isInteracting)
    }

    /// Home Assistant's `kiosk_show_screensaver`: someone already there does not
    /// keep the screen awake, but someone arriving or a touch wakes it.
    @Test func askedToSleepItSleepsUntilSomeoneArrivesOrTouches() {
        let kiosk = KioskHarness()
        kiosk.presence = kiosk.someone(.near)
        kiosk.controller.start()
        kiosk.controller.sleepNow()
        #expect(kiosk.condition == .sleeping)
        kiosk.presence = kiosk.someone(.near)
        kiosk.advance(30)
        #expect(kiosk.condition == .sleeping)
        kiosk.presence = .empty
        kiosk.advance(5)
        kiosk.presence = kiosk.someone(.mid)
        kiosk.advance(1)
        #expect(kiosk.condition == .ambient)
        kiosk.controller.sleepNow()
        #expect(kiosk.condition == .sleeping)
        kiosk.controller.noteTouch()
        #expect(kiosk.condition == .active)
    }

    @Test(arguments: [ProximityLevel.near, .mid])
    func closePresenceWakesToTheFace(proximity: ProximityLevel) {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        kiosk.advance(700)
        #expect(kiosk.condition == .sleeping)
        kiosk.presence = kiosk.someone(proximity)
        kiosk.controller.tick()
        #expect(kiosk.condition == .ambient)
        #expect(!kiosk.controller.state.isInteracting)
    }

    @Test func lookingAtTheScreenWakes() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        kiosk.advance(700)
        kiosk.presence = kiosk.someone(.far, looking: true)
        kiosk.controller.tick()
        #expect(kiosk.condition == .ambient)
    }

    @Test func farPresenceWithoutActivityPreventsDimmingButNotSleep() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        var far = kiosk.someone(.far)
        far.lastActivity = .distantPast
        kiosk.presence = far
        kiosk.advance(200)
        #expect(kiosk.condition == .ambient)
        kiosk.advance(500)
        #expect(kiosk.condition == .sleeping)
    }

    @Test func presenceActivityKeepsTheScreenAwake() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        for _ in 0..<20 {
            kiosk.clock.now = kiosk.clock.now.addingTimeInterval(60)
            kiosk.presence = kiosk.someone(.far)
            kiosk.controller.tick()
        }
        #expect(kiosk.condition == .ambient)
    }

    @Test func sleepAfterZeroNeverSleeps() {
        let kiosk = KioskHarness()
        kiosk.services.settings[CoreSettings.sleepAfterMinutes] = 0
        kiosk.controller.start()
        kiosk.advance(24 * 3600)
        #expect(kiosk.condition == .dimmed)
    }

    @Test func returnToFaceAfterSettingIsHonored() {
        let kiosk = KioskHarness()
        kiosk.services.settings[CoreSettings.returnToFaceAfter] = 15
        kiosk.controller.start()
        kiosk.advance(16)
        #expect(kiosk.condition == .ambient)
    }

    // MARK: Night

    @Test func nightByScheduleWhenRoomLightIsUnknown() {
        let kiosk = KioskHarness(start: TestDates.date(hour: 23))
        kiosk.controller.start()
        #expect(kiosk.condition == .night)
        #expect(kiosk.controller.state.isInteracting)
        kiosk.advance(61)
        #expect(kiosk.condition == .night)
    }

    @Test func litRoomOverridesTheSchedule() {
        let kiosk = KioskHarness(start: TestDates.date(hour: 23))
        kiosk.presence = kiosk.someone(.mid, light: .normal)
        kiosk.controller.start()
        kiosk.advance(61)
        kiosk.presence = kiosk.someone(.mid, light: .normal)
        kiosk.controller.tick()
        #expect(kiosk.condition == .ambient)
    }

    @Test func coveredCameraIsNotNightAtNoon() {
        let kiosk = KioskHarness()
        kiosk.presence = kiosk.someone(.mid, light: .dark)
        kiosk.controller.start()
        #expect(kiosk.condition != .night)
    }

    @Test func forcedNightModeAppliesAtNoon() {
        let kiosk = KioskHarness()
        kiosk.services.settings[ShellSettings.nightModeForced] = true
        kiosk.controller.start()
        #expect(kiosk.condition == .night)
    }

    @Test func automaticNightModeOffIgnoresScheduleAndDarkness() {
        let kiosk = KioskHarness(start: TestDates.date(hour: 2))
        kiosk.services.settings[CoreSettings.nightModeAutomatic] = false
        kiosk.presence = kiosk.someone(.mid, light: .dark)
        kiosk.controller.start()
        #expect(kiosk.condition == .active)
    }

    @Test func sleepingBeatsNight() {
        let kiosk = KioskHarness(start: TestDates.date(hour: 23))
        kiosk.controller.start()
        kiosk.advance(700)
        #expect(kiosk.condition == .sleeping)
    }

    // MARK: Events

    @Test(arguments: [
        HomePadEvent.wake, .doorbellRang(cameraID: "front"), .timerFinished(id: UUID(), label: "Pasta"),
        .soundDetected(label: "smoke_alarm", confidence: 0.9), .intercomReceived(from: "Kitchen", text: nil),
        .invokeAssistant(prompt: nil),
    ])
    func alertsWakeTheScreen(event: HomePadEvent) {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        kiosk.advance(700)
        #expect(kiosk.condition == .sleeping)
        kiosk.controller.handle(event)
        #expect(kiosk.condition == .active)
    }

    @Test func goAmbientEndsInteraction() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        #expect(kiosk.controller.state.isInteracting)
        kiosk.controller.handle(.goAmbient)
        #expect(!kiosk.controller.state.isInteracting)
        #expect(kiosk.condition == .ambient)
        #expect(kiosk.interactionEndedCount == 1)
    }

    @Test func unrelatedEventsChangeNothing() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        kiosk.advance(700)
        kiosk.controller.handle(.motionDetected(source: "yard"))
        #expect(kiosk.condition == .sleeping)
    }

    // MARK: Holds

    @Test func cameraClaimHoldsInteraction() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        kiosk.services.capture.claim("mirror", camera: .front)
        kiosk.advance(300)
        #expect(kiosk.condition == .active)
        kiosk.services.capture.release("mirror")
        kiosk.advance(61)
        #expect(kiosk.condition != .active)
    }

    @Test func debugPinHoldsInteractionAndCondition() {
        let kiosk = KioskHarness()
        kiosk.controller.returnsToAmbient = false
        kiosk.controller.start()
        kiosk.advance(3600)
        #expect(kiosk.controller.state.isInteracting)
        kiosk.controller.pinnedCondition = .sleeping
        kiosk.controller.tick()
        #expect(kiosk.condition == .sleeping)
        #expect(kiosk.services.displayCondition == .sleeping)
    }

    // MARK: Outputs

    @Test func publishesConditionToServices() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        #expect(kiosk.services.displayCondition == .active)
        kiosk.advance(61)
        #expect(kiosk.services.displayCondition == .ambient)
    }

    @Test func proximityIsNearWhileTouchingAndFarWhenEmpty() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        #expect(kiosk.controller.proximity == .near)
        kiosk.advance(61)
        #expect(kiosk.controller.proximity == .far)
        kiosk.presence = kiosk.someone(.mid)
        kiosk.controller.tick()
        #expect(kiosk.controller.proximity == .mid)
    }

    /// The lights go off while someone uses the Home app: the camera loses the
    /// person at the iPad. Apps keep their up-close layout, the face does not.
    @Test func touchKeepsAppsNearWhenTheCameraLosesSomeone() {
        let kiosk = KioskHarness()
        kiosk.services.presence.start()
        kiosk.controller.start()
        kiosk.presence = kiosk.someone(.near)
        kiosk.controller.noteTouch()
        kiosk.advance(1)
        #expect(kiosk.controller.proximity == .near)
        #expect(kiosk.controller.faceProximity == .near)
        kiosk.presence = .empty
        kiosk.advance(4)
        #expect(kiosk.controller.proximity == .near)
        #expect(kiosk.controller.faceProximity == .far)
        // Lights back on: nothing changes for the app.
        kiosk.presence = kiosk.someone(.near)
        kiosk.advance(4)
        #expect(kiosk.controller.proximity == .near)
        // A minute after the last touch the camera decides again.
        kiosk.presence = .empty
        kiosk.advance(60)
        #expect(kiosk.controller.proximity == .far)
    }

    /// The face has two looks: up close within reach, and across the room anywhere past it. Someone in
    /// the middle of the room gets the far look, while apps keep their middle walk-up size.
    @Test func theFaceIsUpCloseOnlyWithinReach() {
        let kiosk = KioskHarness()
        kiosk.services.presence.start()
        kiosk.controller.start()
        kiosk.presence = kiosk.someone(.mid)
        kiosk.advance(61)
        #expect(kiosk.controller.faceProximity == .far)
        #expect(kiosk.controller.proximity == .mid)
        kiosk.presence = kiosk.someone(.far)
        kiosk.controller.tick()
        #expect(kiosk.controller.faceProximity == .far)
        kiosk.presence = kiosk.someone(.near)
        kiosk.controller.tick()
        #expect(kiosk.controller.faceProximity == .near)
    }

    /// Seeing someone keeps the screen in use, which must not hold the up close look for a person
    /// across the room: while the camera watches, the face goes by the distance it measures.
    @Test func aScreenInUseDoesNotMakeTheFaceNear() {
        let kiosk = KioskHarness()
        kiosk.services.presence.start()
        kiosk.controller.start()
        kiosk.presence = kiosk.someone(.mid)
        kiosk.controller.handle(.wake)
        kiosk.advance(1)
        #expect(kiosk.controller.state.isInteracting)
        #expect(kiosk.controller.faceProximity == .far)
        kiosk.presence = kiosk.someone(.near)
        kiosk.advance(1)
        #expect(kiosk.controller.faceProximity == .near)
    }

    /// A doorbell or the assistant is not a touch: with nobody in view, the
    /// alert is drawn for someone across the room.
    @Test func wakeWithoutATouchFollowsTheCamera() {
        let kiosk = KioskHarness()
        kiosk.services.presence.start()
        kiosk.controller.start()
        kiosk.controller.handle(.wake)
        #expect(kiosk.controller.state.isInteracting)
        #expect(kiosk.controller.proximity == .far)
        #expect(kiosk.controller.faceProximity == .far)
    }

    @Test func brightnessFollowsTheCondition() {
        let kiosk = KioskHarness()
        let levels = BrightnessLevels.standard
        kiosk.controller.start()
        #expect(kiosk.brightness.brightness == levels.active)
        kiosk.advance(61)
        #expect(kiosk.brightness.brightness == levels.ambient)
        kiosk.advance(60)
        #expect(kiosk.brightness.brightness == levels.dimmed)
        kiosk.advance(600)
        #expect(kiosk.brightness.brightness == levels.sleeping)
    }

    @Test func followingTheSystemOnlyDimsAndThenHandsBack() {
        let kiosk = KioskHarness(followsSystemBrightness: true)
        let levels = BrightnessLevels.standard
        kiosk.controller.start()
        // In use: iPadOS auto-brightness keeps its own level.
        #expect(kiosk.brightness.brightness == 0.42)
        kiosk.advance(61)
        #expect(kiosk.brightness.brightness == 0.42)
        // Nobody nearby: dimmed relative to the system's level.
        kiosk.advance(60)
        #expect(abs(kiosk.brightness.brightness - (0.42 * levels.dimmed / levels.active * 100).rounded() / 100) < 0.011)
        // Someone comes back: the system's level returns.
        kiosk.controller.handle(.wake)
        #expect(kiosk.brightness.brightness == 0.42)
    }

    @Test func restoresTheUsersBrightnessOnStop() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        #expect(kiosk.brightness.brightness != 0.42)
        kiosk.controller.stop()
        #expect(kiosk.brightness.brightness == 0.42)
    }

    @Test func manualBrightnessHoldsUntilTheConditionChanges() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        kiosk.controller.setManualBrightness(0.33)
        kiosk.advance(30)
        #expect(kiosk.brightness.brightness == 0.33)
        kiosk.advance(31)
        #expect(kiosk.brightness.brightness == BrightnessLevels.standard.ambient)
    }

    @Test func heatCapsBrightness() {
        let kiosk = KioskHarness()
        kiosk.health.update(power: .charging, batteryLevel: 1, thermalState: .serious)
        kiosk.controller.start()
        #expect(kiosk.brightness.brightness <= 0.5)
    }

    @Test func criticalHeatPausesPresenceUntilCool() {
        let kiosk = KioskHarness()
        kiosk.services.presence.start()
        kiosk.controller.start()
        kiosk.health.update(power: .charging, batteryLevel: 1, thermalState: .critical)
        kiosk.controller.tick()
        #expect(!kiosk.services.presence.isRunning)
        kiosk.health.update(power: .charging, batteryLevel: 1, thermalState: .nominal)
        kiosk.controller.tick()
        #expect(kiosk.services.presence.isRunning)
    }

    @Test func keepsAutoLockOffWhileRunning() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        #expect(kiosk.idleTimerDisabled == true)
        kiosk.controller.stop()
        #expect(kiosk.idleTimerDisabled == false)
    }

    @Test func keepScreenOnSettingReleasesAutoLock() {
        let kiosk = KioskHarness()
        kiosk.services.settings[ShellSettings.keepScreenOn] = false
        kiosk.controller.start()
        #expect(kiosk.idleTimerDisabled == false)
    }

    @Test func burnInShiftOnlyWhenNobodyIsUsingTheScreen() {
        let kiosk = KioskHarness()
        kiosk.controller.start()
        #expect(kiosk.controller.burnInOffset == .zero)
        kiosk.advance(61)
        #expect(kiosk.controller.burnInOffset != .zero)
        kiosk.services.settings[ShellSettings.burnInProtection] = false
        kiosk.controller.tick()
        #expect(kiosk.controller.burnInOffset == .zero)
    }

    @Test func relocksPersonalContentAfterTheUnlockWindow() {
        // Household stamps recognition with the real clock, so this test starts the kiosk clock now.
        let kiosk = KioskHarness(start: Date())
        let member = HouseholdMember(name: "Alex")
        kiosk.services.household.add(member)
        kiosk.services.household.recognize(member.id)
        kiosk.controller.start()
        #expect(kiosk.services.household.isPersonalContentUnlocked)
        kiosk.advance(kiosk.services.household.unlockWindow + 1)
        #expect(!kiosk.services.household.isPersonalContentUnlocked)
    }
}
