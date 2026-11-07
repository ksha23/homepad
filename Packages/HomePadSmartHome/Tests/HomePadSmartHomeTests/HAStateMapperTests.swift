import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

@Suite("Home Assistant state mapping")
struct HAStateMapperTests {
    let output: HAStateMapper.Output

    init() throws {
        output = HAStateMapper.map(try Fixtures.states(), context: Fixtures.context())
    }

    private func accessory(_ entityID: String) throws -> HomeAccessory {
        try #require(output.accessories.first { $0.id == "ha:\(entityID)" })
    }

    @Test func keepsSupportedDomainsAndDropsTheRest() {
        let ids = Set(output.accessories.map(\.id))
        #expect(output.accessories.count == 20)
        #expect(!ids.contains("ha:automation.lights_on"))
        #expect(!ids.contains("ha:sun.sun"))
        #expect(!ids.contains("ha:sensor.weather_summary"), "text sensors have no tile")
        #expect(!ids.contains("ha:event.hallway_button"), "only doorbell events are accessories")
        #expect(!ids.contains("ha:light.hidden_strip"), "hidden in the entity registry")
        #expect(!ids.contains("ha:sensor.cpu_temp"), "diagnostic entities are hidden")
        #expect(output.cameras.count == 2)
        #expect(Set(output.scenes.map(\.id)) == ["ha:scene.movie_time", "ha:script.good_night"])
    }

    @Test func idsAreBackendPrefixed() {
        for accessory in output.accessories {
            #expect(accessory.id.hasPrefix("ha:"))
            #expect(accessory.backend == .homeAssistant)
        }
    }

    @Test func lightWithColorTemperatureAndHue() throws {
        let light = try accessory("light.kitchen")
        #expect(light.kind == .light)
        #expect(light.name == "Kitchen Ceiling")
        #expect(light.room == "Kitchen")
        #expect(light.capabilities == [.power, .brightness, .colorTemperature, .color])
        #expect(light.state.isOn == true)
        #expect(abs((light.state.brightness ?? 0) - 178.0 / 255) < 0.0001)
        #expect(light.state.colorTemperatureKelvin == 3000)
        #expect(light.state.hue == 30)
        #expect(light.state.saturation == 0.4)
    }

    @Test func unavailableOnOffLightUsesDeviceArea() throws {
        let porch = try accessory("light.porch")
        #expect(porch.state.isReachable == false)
        #expect(porch.capabilities == [.power])
        #expect(porch.room == "Entryway", "the entity has no area, so its device's area is used")
        #expect(AccessoryPresentation.status(for: porch) == "No Response")
    }

    @Test func switchesAndInputBooleans() throws {
        #expect(try accessory("switch.coffee").kind == .switchOutlet)
        #expect(try accessory("switch.coffee").state.isOn == false)
        let guest = try accessory("input_boolean.guest_mode")
        #expect(guest.kind == .switchOutlet)
        #expect(guest.state.isOn == true)
        #expect(guest.room == nil)
    }

    @Test func fanSpeedIsTheLevel() throws {
        let fan = try accessory("fan.bedroom")
        #expect(fan.kind == .fan)
        #expect(fan.capabilities.contains(.brightness))
        #expect(fan.state.brightness == 0.5)
    }

    @Test func climateSingleTarget() throws {
        let climate = try accessory("climate.hallway")
        #expect(climate.kind == .thermostat)
        #expect(climate.state.hvacMode == .cool)
        #expect(climate.state.targetTemperature == 22)
        #expect(climate.state.currentTemperature == 23.5)
        #expect(climate.state.humidity == 41)
        #expect(climate.state.temperatureUnit == .celsius)
        #expect(climate.room == "Living Room")
    }

    @Test func climateRangeUsesTheMiddle() throws {
        let climate = try accessory("climate.upstairs")
        #expect(climate.state.hvacMode == .auto, "heat_cool maps to auto")
        #expect(climate.state.targetTemperature == 22)
    }

    @Test func lockAndCovers() throws {
        let lock = try accessory("lock.front_door")
        #expect(lock.kind == .lock)
        #expect(lock.state.lockState == .locked)
        let blinds = try accessory("cover.living_blinds")
        #expect(blinds.kind == .cover)
        #expect(blinds.capabilities == [.position])
        #expect(blinds.state.position == 0.6)
        #expect(blinds.state.doorState == .open)
        let garage = try accessory("cover.garage_door")
        #expect(garage.kind == .garageDoor, "device class garage is a door, not a blind")
        #expect(garage.capabilities.isEmpty)
        #expect(garage.state.position == 0)
        #expect(garage.room == "Garage")
    }

    @Test func mediaPlayer() throws {
        let player = try accessory("media_player.living_room")
        #expect(player.kind == .mediaPlayer)
        #expect(player.name == "Sonos One", "the registry name wins over the friendly name")
        #expect(player.capabilities.contains(.volume))
        #expect(player.state.isActive == true)
        #expect(player.state.mediaTitle == "Clair de Lune")
        #expect(player.state.mediaArtist == "Claude Debussy")
        #expect(player.state.volume == 0.3)
    }

    @Test func sensors() throws {
        let temperature = try accessory("sensor.living_temperature")
        #expect(temperature.kind == .sensor)
        #expect(temperature.state.sensorValue == 21.6)
        #expect(temperature.state.sensorUnit == "°C")
        #expect(temperature.state.currentTemperature == 21.6)
        #expect(try accessory("sensor.living_humidity").state.humidity == 44)
        #expect(try accessory("sensor.phone_battery").state.batteryLevel == 0.87)
    }

    @Test func binarySensorsAndDoorbells() throws {
        let contact = try accessory("binary_sensor.front_door_contact")
        #expect(contact.state.doorState == .open)
        #expect(AccessoryPresentation.status(for: contact) == "Open")
        #expect(try accessory("binary_sensor.hall_motion").state.isActive == false)
        #expect(try accessory("binary_sensor.side_doorbell").kind == .doorbell)
        #expect(try accessory("event.front_doorbell").kind == .doorbell)
    }

    @Test func alarmAndVacuum() throws {
        let alarm = try accessory("alarm_control_panel.home")
        #expect(alarm.kind == .securitySystem)
        #expect(alarm.state.isOn == true)
        #expect(AccessoryPresentation.status(for: alarm) == "Armed")
        let vacuum = try accessory("vacuum.roomba")
        #expect(vacuum.state.isOn == false)
        #expect(vacuum.state.batteryLevel == 0.92)
    }

    @Test func scenesGetSymbols() throws {
        let movie = try #require(output.scenes.first { $0.id == "ha:scene.movie_time" })
        #expect(movie.systemImage == "tv.fill")
        let night = try #require(output.scenes.first { $0.id == "ha:script.good_night" })
        #expect(night.systemImage == "moon.stars.fill")
    }

    @Test func camerasCarryTokenURLsAndDoorbellFlag() throws {
        let front = try #require(output.cameras.first { $0.id == "ha:camera.front_door" })
        #expect(front.isDoorbell, "shares a device with a doorbell event entity")
        #expect(front.room == "Entryway")
        #expect(front.streamURL?.absoluteString == "http://ha.test:8123/api/camera_proxy_stream/camera.front_door?token=abc123")
        #expect(front.snapshotURL?.absoluteString == "http://ha.test:8123/api/camera_proxy/camera.front_door?token=abc123")
        let backyard = try #require(output.cameras.first { $0.id == "ha:camera.backyard" })
        #expect(!backyard.isDoorbell)
        #expect(backyard.room == nil)
    }

    @Test func fahrenheitInstancesKeepTheirUnit() throws {
        var context = Fixtures.context()
        context.temperatureUnit = .fahrenheit
        let mapped = HAStateMapper.map(try Fixtures.states(), context: context)
        #expect(mapped.accessories.first { $0.id == "ha:climate.hallway" }?.state.temperatureUnit == .fahrenheit)
    }

    @Test func configuredTriggerBecomesADoorbell() throws {
        var context = Fixtures.context()
        context.doorbellTriggerID = "binary_sensor.hall_motion"
        let mapped = HAStateMapper.map(try Fixtures.states(), context: context)
        #expect(mapped.accessories.first { $0.id == "ha:binary_sensor.hall_motion" }?.kind == .doorbell)
    }

    @Test func humanizedNames() {
        #expect(HAStateMapper.humanized("light.kitchen_ceiling") == "Kitchen Ceiling")
    }

    @Test func musicAssistantPlayerCarriesIntegrationAndGroup() throws {
        var registry = Fixtures.registry()
        registry.devices["dev_kitchen_pod"] = HARegistry.Device(id: "dev_kitchen_pod", name: "Kitchen", model: "HomePod mini")
        registry.entities["media_player.kitchen_homepod"] = HARegistry.Entity(
            entityID: "media_player.kitchen_homepod", deviceID: "dev_kitchen_pod", platform: "music_assistant", isHidden: false
        )
        let state = HAState(entityID: "media_player.kitchen_homepod", state: "playing", attributes: [
            "friendly_name": "Kitchen HomePod", "device_class": "speaker", "media_title": "Anti-Hero",
            "media_artist": "Taylor Swift", "media_album_name": "Midnights",
            "group_members": ["media_player.kitchen_homepod", "media_player.office_sonos"],
            "mass_player_type": "player",
            "media_position_updated_at": "2026-10-20T14:03:11.123456+00:00",
        ])
        var context = Fixtures.context()
        context.registry = registry
        let player = try #require(HAStateMapper.accessory(from: state, context: context))
        #expect(player.integration == "music_assistant")
        #expect(player.deviceClass == "speaker")
        #expect(player.deviceModel == "HomePod mini")
        #expect(player.state.mediaAlbum == "Midnights")
        #expect(player.state.mediaGroupMemberIDs == ["ha:media_player.kitchen_homepod", "ha:media_player.office_sonos"])
        let updatedAt = try #require(player.state.mediaPositionUpdatedAt)
        #expect(abs(updatedAt.timeIntervalSince(HAResponses.parseDate("2026-10-20T14:03:11+00:00")!) - 0.123) < 0.001)
    }

    @Test func registryReadsThePlatform() throws {
        let light = try accessory("light.kitchen")
        #expect(light.integration == "demo")
        #expect(light.state.mediaGroupMemberIDs == nil)
    }
}
