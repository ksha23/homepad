import Foundation
import Testing
@testable import HomePadCore

@Suite struct JSONValueTests {
    @Test func roundTripsToolArguments() throws {
        let value = try JSONValue.parse(#"{"name":"Kitchen","brightness":0.5,"on":true,"tags":["a","b"]}"#)
        #expect(value["name"]?.stringValue == "Kitchen")
        #expect(value["brightness"]?.doubleValue == 0.5)
        #expect(value["on"]?.boolValue == true)
        #expect(value["tags"]?.arrayValue?.count == 2)
        #expect(try JSONValue.parse(value.jsonString()) == value)
    }
}

@MainActor @Suite struct HouseholdTests {
    @Test func limitsMembersAndGatesPersonalContent() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test.\(UUID())")!)
        let household = Household(store: store)
        for i in 0..<7 { household.add(HouseholdMember(name: "P\(i)")) }
        #expect(household.members.count == Household.maxMembers)
        let first = household.members[0].id
        household.select(first)
        #expect(household.isPersonalContentUnlocked == false)
        household.recognize(first)
        #expect(household.isPersonalContentUnlocked)
        household.expireIfNeeded(now: Date().addingTimeInterval(household.unlockWindow + 1))
        #expect(household.isPersonalContentUnlocked == false)
    }

    @Test func touchesKeepPersonalContentUnlockedButNeverUnlockIt() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test.\(UUID())")!)
        let household = Household(store: store)
        let kyle = HouseholdMember(name: "Kyle", isAdmin: true)
        household.add(kyle)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let window = household.unlockWindow
        // Verified once (Face ID), then keeps using the screen past the window.
        household.recognize(kyle.id, now: start)
        household.noteActivity(now: start.addingTimeInterval(window - 10))
        household.expireIfNeeded(now: start.addingTimeInterval(window + 10))
        #expect(household.isPersonalContentUnlocked)
        // Stops touching: locks one window after the last touch.
        household.expireIfNeeded(now: start.addingTimeInterval(2 * window))
        #expect(household.isPersonalContentUnlocked == false)
        // A touch while locked, or by someone picked by hand, unlocks nothing.
        household.noteActivity(now: start.addingTimeInterval(2 * window + 1))
        #expect(household.isPersonalContentUnlocked == false)
        household.select(kyle.id)
        household.noteActivity()
        #expect(household.isPersonalContentUnlocked == false)
    }
}

@MainActor @Suite struct ServiceTests {
    @Test func demoSmartHomeHandlesCommands() async throws {
        let home = DemoSmartHomeService()
        try await home.perform(.unlock, on: "demo:lock.front")
        #expect(home.accessory("demo:lock.front")?.state.lockState == .unlocked)
        #expect(home.findAccessories(matching: "kitchen").isEmpty == false)
        #expect(home.rooms.contains("Kitchen"))
    }

    @Test func timersPauseAndResume() {
        let timers = InMemoryTimerService()
        let t = timers.start(duration: 60, label: "Pasta")
        timers.pause(t.id)
        #expect(timers.timers.first?.status == .paused)
        timers.resume(t.id)
        #expect(timers.timers.first?.status == .running)
        #expect((timers.timers.first?.remaining() ?? 0) > 50)
    }

    @Test func settingsRoundTrip() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test.\(UUID())")!)
        let key = SettingKey<Int>("test.value", default: 3)
        #expect(store[key] == 3)
        store[key] = 9
        #expect(store[key] == 9)
    }
}

@MainActor @Suite struct CaptureCoordinatorTests {
    @Test func claimWaitsForBackgroundSensorToRelease() async {
        let capture = CaptureCoordinator()
        capture.setBackgroundSensorUsingCamera(true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            capture.setBackgroundSensorUsingCamera(false)
        }
        let start = ContinuousClock.now
        let claimed = await capture.claimWhenReady("test", camera: .front)
        #expect(claimed)
        #expect(ContinuousClock.now - start >= .milliseconds(150))
        #expect(capture.foregroundClaim?.owner == "test")
    }

    @Test func nestedClaimsStackAndUnwind() {
        let capture = CaptureCoordinator()
        capture.claim("lab", camera: .back)
        capture.claim("scanner", camera: .back)
        #expect(capture.foregroundClaim?.owner == "scanner")
        capture.release("scanner")
        #expect(capture.foregroundClaim?.owner == "lab")
        capture.camerasAllowed = false
        #expect(capture.claim("other", camera: .front) == false)
    }
}

/// Kyle dragged the volume of AirPlay HomePods: the HomePods changed, but the
/// slider went back to the old level, because the system never reported it.
@Suite struct HeldVolumeTests {
    let start = Date(timeIntervalSince1970: 1_792_537_200)

    @Test func theChosenLevelStaysWhenTheSystemNeverReports() {
        var volume = HeldVolume(reported: 0.3)
        volume.choose(0.7, at: start)
        #expect(volume.level == 0.7)
        #expect(volume.reported == 0.3)
    }

    @Test func echoesOfTheDragDoNotMoveTheSlider() {
        var volume = HeldVolume(reported: 0.3)
        volume.choose(0.7, at: start)
        volume.report(0.45, at: start.addingTimeInterval(0.5))
        volume.report(0.6, at: start.addingTimeInterval(1))
        #expect(volume.level == 0.7)
    }

    @Test func aMatchingReportHandsBackToTheSystem() {
        var volume = HeldVolume(reported: 0.3)
        volume.choose(0.7, at: start)
        // The system rounds to its steps: 11 of 16.
        volume.report(0.6875, at: start.addingTimeInterval(0.4))
        #expect(volume.level == 0.6875)
        volume.report(0.25, at: start.addingTimeInterval(0.6))
        #expect(volume.level == 0.25)
    }

    @Test func aReportAfterTheHoldIsAChangeFromElsewhere() {
        var volume = HeldVolume(reported: 0.3)
        volume.choose(0.7, at: start)
        volume.report(0.5, at: start.addingTimeInterval(5))
        #expect(volume.level == 0.5)
    }

    @Test func eachMoveOfTheDragRestartsTheHold() {
        var volume = HeldVolume(reported: 0.3)
        volume.choose(0.5, at: start)
        volume.choose(0.8, at: start.addingTimeInterval(1.9))
        volume.report(0.4, at: start.addingTimeInterval(3))
        #expect(volume.level == 0.8)
    }
}
