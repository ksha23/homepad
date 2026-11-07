import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// The sensors a HomePad sends Home Assistant: their values from what HomePad
/// already knows, and the `register_sensor` and `update_sensor_states` payloads.
@MainActor
@Suite("Home Assistant device sensors")
struct MobileAppSensorTests {
    private func states(_ inputs: MobileAppSensorInputs) -> [MobileAppSensor: MobileAppSensorState] {
        Dictionary(uniqueKeysWithValues: inputs.states.map { ($0.sensor, $0) })
    }

    @Test func everySensorFromWhatHomePadKnows() {
        let sample = states(.sample)
        #expect(MobileAppSensorInputs.sample.states.map(\.sensor) == MobileAppSensor.allCases)
        #expect(sample[.presence]?.state == true)
        #expect(sample[.proximity]?.state == "mid")
        #expect(sample[.recognized]?.state == "Kyle")
        #expect(sample[.roomLight]?.state == 212)
        #expect(sample[.roomLight]?.attributes["level"] == "normal")
        #expect(sample[.screen]?.state == "face")
        #expect(sample[.screen]?.attributes["display"] == "ambient")
        #expect(sample[.face]?.state == "Modular")
        #expect(sample[.face]?.attributes["id"] == "faces.modular")
        #expect(sample[.app]?.state == "None")
        #expect(sample[.brightness]?.state == 62)
        #expect(sample[.battery]?.state == 80)
        #expect(sample[.battery]?.icon == "mdi:battery-charging-80")
        #expect(sample[.charging]?.state == true)
        #expect(sample[.charging]?.attributes["battery_state"] == "charging")
    }

    @Test func aGuestAndWhatHomePadCannotTell() {
        var inputs = MobileAppSensorInputs.sample
        inputs.recognizedName = nil
        inputs.presence = PresenceSnapshot()
        inputs.kiosk.batteryLevel = nil
        inputs.kiosk.power = nil
        let values = states(inputs)
        #expect(values[.recognized]?.state == "Guest")
        #expect(values[.presence]?.state == false)
        #expect(values[.proximity]?.state == "nobody")
        #expect(values[.roomLight]?.state == "unavailable")
        #expect(values[.roomLight]?.attributes.isEmpty == true)
        #expect(values[.battery]?.state == "unavailable")
        #expect(values[.charging]?.state == "unavailable")
    }

    @Test func nightAndSleepCoverWhatIsOnScreen() {
        var inputs = MobileAppSensorInputs.sample
        inputs.kiosk.surface = .app
        inputs.appID = "recipes"
        inputs.appTitle = "Recipes"
        #expect(states(inputs)[.screen]?.state == "app")
        #expect(states(inputs)[.app]?.state == "Recipes")
        #expect(states(inputs)[.app]?.attributes["id"] == "recipes")
        inputs.display = .night
        #expect(states(inputs)[.screen]?.state == "night")
        inputs.display = .sleeping
        #expect(states(inputs)[.screen]?.state == "asleep")
        #expect(states(inputs)[.screen]?.attributes["display"] == "sleeping")
        inputs.kiosk.surface = .homeScreen
        inputs.display = .dimmed
        #expect(states(inputs)[.screen]?.state == "home_screen")
    }

    @Test func registeringCarriesTheSensorsKind() throws {
        let light = MobileAppSensorInputs.sample.state(of: .roomLight).registerMessage
        #expect(light["type"] == "register_sensor")
        let data = try #require(light["data"])
        #expect(data["type"] == "sensor")
        #expect(data["unique_id"] == "room_light")
        #expect(data["name"] == "Room Light")
        #expect(data["device_class"] == "illuminance")
        #expect(data["unit_of_measurement"] == "lx")
        #expect(data["state_class"] == "measurement")
        #expect(data["state"] == 212)
        #expect(data["icon"] == "mdi:brightness-5")
        #expect(data["attributes"]?["level"] == "normal")
        #expect(data["entity_category"] == nil)

        let charging = try #require(MobileAppSensorInputs.sample.state(of: .charging).registerMessage["data"])
        #expect(charging["type"] == "binary_sensor")
        #expect(charging["device_class"] == "battery_charging")
        #expect(charging["entity_category"] == "diagnostic")
        #expect(charging["unit_of_measurement"] == nil)
        #expect(charging["state_class"] == nil)
    }

    @Test func updatesAndTheirAnswer() throws {
        let sample = MobileAppSensorInputs.sample
        let message = MobileAppSensorState.updateMessage([sample.state(of: .presence), sample.state(of: .proximity)])
        #expect(message["type"] == "update_sensor_states")
        let entries = try #require(message["data"]?.arrayValue)
        #expect(entries.map { $0["unique_id"] } == ["presence", "proximity"])
        #expect(entries.first?["type"] == "binary_sensor")
        #expect(entries.first?["state"] == true)
        #expect(entries.first?["icon"] == "mdi:account")
        // Only what an update may carry: no name or device class.
        #expect(entries.first?["name"] == nil)
        #expect(entries.first?["device_class"] == nil)

        let answer = Fixtures.json("webhook_update_sensor_states")
        #expect(MobileAppSensorState.accepted(in: answer) == [.presence, .battery])
        #expect(MobileAppSensorState.unregistered(in: answer) == [.proximity])
    }

    @Test func roomLightCountsOnlyARealChange() {
        let reported = MobileAppSensorInputs.sample.state(of: .roomLight)
        var inputs = MobileAppSensorInputs.sample
        inputs.presence.ambientLux = 230
        #expect(!inputs.state(of: .roomLight).differs(from: reported))
        inputs.presence.ambientLux = 300
        #expect(inputs.state(of: .roomLight).differs(from: reported))
        inputs.presence.ambientLux = 230
        inputs.presence.ambientLight = .bright
        #expect(inputs.state(of: .roomLight).differs(from: reported))
        inputs.presence.ambientLux = nil
        #expect(inputs.state(of: .roomLight).differs(from: reported))
    }

    @Test func namesFollowTheRoom() {
        #expect(MobileAppNaming.deviceName(room: "Kitchen") == "Kitchen HomePad")
        #expect(MobileAppNaming.deviceName(room: "  ") == "HomePad")
        #expect(MobileAppNaming.notifyService(deviceName: "Kids' Room HomePad") == "mobile_app_kids_room_homepad")
        #expect(HomeAssistantDeviceSection.entityID(of: .presence, deviceName: "Kitchen HomePad")
            == "binary_sensor.kitchen_homepad_someone_present")
    }
}
