import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

/// The Find My service on a stand-in smart home: who sees what, live updates,
/// setup states, Play Sound and the demo.
@MainActor
@Suite struct FindMyServiceTests {
    @Test func guestsSeeNothing() {
        let fixture = FindMyFixture()
        #expect(fixture.findMy.visibleDevices.isEmpty)
        fixture.services.household.select(fixture.kyle.id)
        #expect(fixture.findMy.visibleDevices.isEmpty)
        #expect(fixture.findMy.setup == .nothingForViewer)
    }

    @Test func adminSeesEverythingWithTheirOwnFirst() {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.kyle)
        #expect(fixture.titles() == [
            "Kyle\u{2019}s iPad", "Kyle\u{2019}s iPhone", "Jordan's Phone", "Sam's iPhone", "Living Room iPad",
        ])
        #expect(fixture.findMy.setup == .ready)
    }

    @Test func membersSeeTheirOwnUntilSharingIsOn() {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.sam)
        #expect(fixture.titles() == ["Sam's iPhone"])
        fixture.services.settings[PersonalSettings.findMyShareWithEveryone] = true
        #expect(fixture.titles() == ["Sam's iPhone", "Jordan's Phone", "Kyle\u{2019}s iPad", "Kyle\u{2019}s iPhone"])
    }

    @Test func ownerChoicesMoveAndHideDevices() {
        let fixture = FindMyFixture()
        fixture.findMy.setOwnerChoice(.member(fixture.sam.id), for: "ha:device_tracker.living_room_ipad")
        fixture.findMy.setOwnerChoice(.hidden, for: "ha:device_tracker.jordans_phone")
        fixture.recognize(fixture.sam)
        #expect(fixture.titles() == ["Sam's iPhone", "Sam's Living Room iPad"])
        fixture.recognize(fixture.kyle)
        #expect(!fixture.titles().contains("Jordan's Phone"))
        fixture.findMy.setOwnerChoice(nil, for: "ha:device_tracker.jordans_phone")
        #expect(fixture.titles().contains("Jordan's Phone"))
    }

    @Test func trackerUpdatesShowWithoutRefreshing() {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.kyle)
        var moved = FindMyFixture.devices
        moved[0].place = .zone("Work")
        moved[0].latitude = 43.0766
        fixture.smartHome.trackedDevices = moved
        #expect(fixture.findMy.device("ha:device_tracker.kyles_iphone")?.tracked.place == .zone("Work"))
    }

    @Test func setupSaysWhatIsMissing() {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.kyle)
        fixture.smartHome.trackedDevices = []
        #expect(fixture.findMy.setup == .noTrackers)
        fixture.smartHome.connectedBackends = [.homeKit]
        #expect(fixture.findMy.setup == .noHomeAssistant)
    }

    @Test func playSoundRecordsWhatHappened() async throws {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.kyle)
        let iPad = try #require(fixture.findMy.device("ha:device_tracker.kyles_ipad"))
        try await fixture.findMy.playSound(iPad)
        #expect(fixture.smartHome.rung == ["ha:device_tracker.kyles_ipad"])
        guard case .sent(_, .companionApp) = fixture.findMy.soundStates[iPad.id] else {
            Issue.record("Expected a sent state")
            return
        }
        fixture.smartHome.failure = .backend("Action notify.mobile_app_kyle_s_ipad not found")
        await #expect(throws: SmartHomeError.self) { try await fixture.findMy.playSound(iPad) }
        #expect(fixture.findMy.soundStates[iPad.id] == .failed("Action notify.mobile_app_kyle_s_ipad not found."))
        #expect(fixture.findMy.soundStates[iPad.id]?.message.hasPrefix("Could not play a sound.") == true)
    }

    @Test func nobodyRingsADeviceTheyCannotSee() async throws {
        let fixture = FindMyFixture()
        fixture.recognize(fixture.kyle)
        let kylesPhone = try #require(fixture.findMy.device("ha:device_tracker.kyles_iphone"))
        fixture.recognize(fixture.sam)
        await #expect(throws: SmartHomeError.self) { try await fixture.findMy.playSound(kylesPhone) }
        #expect(fixture.smartHome.rung.isEmpty)
    }

    @Test func addressesAreLookedUpOncePerSpot() async {
        var lookups = 0
        let book = FindMyAddressBook { _, _ in
            lookups += 1
            return "120 State St, Madison"
        }
        #expect(await book.address(latitude: 43.07451, longitude: -89.39251) == "120 State St, Madison")
        #expect(await book.address(latitude: 43.07452, longitude: -89.39249) == "120 State St, Madison")
        #expect(lookups == 1)
        #expect(book.cached(latitude: 43.0745, longitude: -89.3925) == "120 State St, Madison")
    }

    @Test func demoShowsDevicesOwnedByTheHousehold() {
        let fixture = FindMyFixture()
        fixture.services.settings[PersonalSettings.demoData] = true
        fixture.recognize(fixture.kyle)
        let titles = fixture.titles()
        #expect(titles.count == 6)
        #expect(titles.first == "Kyle's Apple Watch" || titles.first == "Kyle's iPhone")
        #expect(titles.contains("Sam's iPhone"))
        #expect(fixture.findMy.zones.contains { $0.isHome })
        #expect(fixture.findMy.cachedAddress(for: FindMyDemoData.devices(members: [], now: Date())[1]) == "State St, Madison")
    }
}
