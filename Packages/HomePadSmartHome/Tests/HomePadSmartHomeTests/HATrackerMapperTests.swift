import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// Device trackers and zones from the `*_trackers` fixtures: two iCloud accounts,
/// a Companion app iPad, a Life360 phone, a router tracker and a hidden iPad.
@Suite struct HATrackerMapperTests {
    let output: HATrackerMapper.Output

    init() throws {
        output = HATrackerMapper.map(try Fixtures.states("rest_states_trackers"), registry: Fixtures.trackerRegistry())
    }

    func device(_ entityID: String) throws -> TrackedDevice {
        try #require(output.devices.first { $0.id == "ha:\(entityID)" })
    }

    @Test func keepsGPSTrackersOnly() {
        #expect(output.devices.map(\.id) == [
            "ha:device_tracker.jordans_phone", "ha:device_tracker.kyles_watch", "ha:device_tracker.kyles_ipad",
            "ha:device_tracker.kyles_iphone", "ha:device_tracker.sams_iphone",
        ])
        // The router tracker says only home or away, and the person hid the old iPad.
        #expect(!output.devices.contains { $0.id.contains("living_room_tv") || $0.id.contains("old_ipad") })
    }

    @Test func iCloudTrackerCarriesLocationBatteryAndOwner() throws {
        let iPhone = try device("device_tracker.kyles_iphone")
        #expect(iPhone.name == "Kyle\u{2019}s iPhone")
        #expect(iPhone.source == .iCloud)
        #expect(iPhone.integration == "icloud")
        #expect(iPhone.model == "iPhone 17 Pro")
        #expect(iPhone.place == .home)
        #expect(iPhone.latitude == 43.0748)
        #expect(iPhone.longitude == -89.3841)
        #expect(iPhone.accuracy == 12)
        #expect(iPhone.batteryLevel == 0.82)
        #expect(iPhone.isCharging == false)
        #expect(iPhone.canPlaySound)
        // last_updated, not last_changed: the location moved without the state changing.
        #expect(iPhone.lastUpdated == HAResponses.parseDate("2026-10-20T14:01:30.000000+00:00"))
        // The Home Assistant person that lists it wins over iCloud's owner name.
        #expect(iPhone.ownerName == "Kyle")
    }

    @Test func familyMemberInAnotherZone() throws {
        let iPhone = try device("device_tracker.sams_iphone")
        #expect(iPhone.place == .zone("Work"))
        #expect(iPhone.ownerName == "Sam Rivera")
        #expect(iPhone.isCharging == true)
        #expect(iPhone.batteryLevel == 0.34)
        #expect(iPhone.model == "iPhone 16")
    }

    @Test func iCloudModelComesFromItsDeviceNameAttributeWithoutARegistry() throws {
        let states = try Fixtures.states("rest_states_trackers")
        let iPhone = try #require(HATrackerMapper.map(states, registry: HARegistry()).devices.first { $0.id == "ha:device_tracker.kyles_iphone" })
        #expect(iPhone.model == "iPhone 17 Pro")
        #expect(iPhone.name == "Kyle\u{2019}s iPhone")
    }

    @Test func companionTrackerReadsTheBatterySensorsOnItsDevice() throws {
        let iPad = try device("device_tracker.kyles_ipad")
        #expect(iPad.source == .companionApp)
        #expect(iPad.place == .away)
        #expect(iPad.batteryLevel == 0.62)
        #expect(iPad.isCharging == true)
        #expect(iPad.ownerName == "Kyle")
    }

    @Test func otherIntegrationsShowButCannotRing() throws {
        let phone = try device("device_tracker.jordans_phone")
        #expect(phone.source == .other)
        #expect(phone.integration == "life360")
        #expect(phone.batteryLevel == 0.51)
        #expect(!phone.canPlaySound)
    }

    @Test func unavailableTrackerHasNoLocation() throws {
        let watch = try device("device_tracker.kyles_watch")
        #expect(watch.place == .unknown)
        #expect(!watch.hasLocation)
    }

    @Test func zonesPutHomeFirst() {
        #expect(output.zones.map(\.name) == ["Maple Street", "Work"])
        #expect(output.zones.first?.isHome == true)
        #expect(output.zones.first?.radius == 100)
        #expect(output.zones.last?.id == "ha:zone.work")
    }

    @Test func placeFollowsTheTrackerState() {
        #expect(HATrackerMapper.place(for: "home") == .home)
        #expect(HATrackerMapper.place(for: "not_home") == .away)
        #expect(HATrackerMapper.place(for: "Gym") == .zone("Gym"))
        #expect(HATrackerMapper.place(for: "unavailable") == .unknown)
    }

    @Test func iCloudIsRecognizedBeforeTheRegistryLoads() throws {
        let states = try Fixtures.states("rest_states_trackers")
        let iPhone = try #require(HATrackerMapper.map(states, registry: HARegistry()).devices.first { $0.id == "ha:device_tracker.kyles_iphone" })
        #expect(iPhone.source == .iCloud)
        #expect(iPhone.ownerName == "Kyle")
    }
}
