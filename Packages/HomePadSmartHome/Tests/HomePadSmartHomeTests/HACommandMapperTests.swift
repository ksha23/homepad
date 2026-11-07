import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

@Suite("Home Assistant command mapping")
struct HACommandMapperTests {
    let states: [String: HAState]

    init() throws {
        states = Dictionary(uniqueKeysWithValues: try Fixtures.states().map { ($0.entityID, $0) })
    }

    private func call(_ command: AccessoryCommand, _ entityID: String) throws -> HAServiceCall {
        try HACommandMapper.serviceCall(for: command, entityID: entityID, state: states[entityID])
    }

    private func expectCall(_ command: AccessoryCommand, _ entityID: String, service: String,
                            data: [String: JSONValue] = [:], sourceLocation: SourceLocation = #_sourceLocation) throws {
        let result = try call(command, entityID)
        #expect(result.domain == HAState.domain(of: entityID), sourceLocation: sourceLocation)
        #expect(result.service == service, sourceLocation: sourceLocation)
        #expect(result.data == data, sourceLocation: sourceLocation)
        #expect(result.entityID == entityID, sourceLocation: sourceLocation)
    }

    @Test func lights() throws {
        try expectCall(.setPower(true), "light.kitchen", service: "turn_on")
        try expectCall(.setPower(false), "light.kitchen", service: "turn_off")
        try expectCall(.toggle, "light.kitchen", service: "toggle")
        try expectCall(.setBrightness(0.72), "light.kitchen", service: "turn_on", data: ["brightness_pct": 72])
        try expectCall(.setBrightness(0.001), "light.kitchen", service: "turn_on", data: ["brightness_pct": 1])
        try expectCall(.setBrightness(0), "light.kitchen", service: "turn_off")
        try expectCall(.setColorTemperature(kelvin: 2700), "light.kitchen", service: "turn_on", data: ["color_temp_kelvin": 2700])
        try expectCall(.setHueSaturation(hue: 210, saturation: 0.8), "light.kitchen", service: "turn_on", data: ["hs_color": [210, 80]])
    }

    @Test func switchesAndInputBooleans() throws {
        try expectCall(.setPower(true), "switch.coffee", service: "turn_on")
        try expectCall(.toggle, "input_boolean.guest_mode", service: "toggle")
    }

    @Test func fans() throws {
        try expectCall(.setBrightness(0.5), "fan.bedroom", service: "set_percentage", data: ["percentage": 50])
        try expectCall(.setBrightness(0), "fan.bedroom", service: "turn_off")
        try expectCall(.setPower(true), "fan.bedroom", service: "turn_on")
    }

    @Test func climate() throws {
        try expectCall(.setTargetTemperature(21.5), "climate.hallway", service: "set_temperature", data: ["temperature": 21.5])
        try expectCall(.setHVACMode(.auto), "climate.hallway", service: "set_hvac_mode", data: ["hvac_mode": "heat_cool"])
        try expectCall(.setHVACMode(.fanOnly), "climate.hallway", service: "set_hvac_mode", data: ["hvac_mode": "fan_only"])
        try expectCall(.setPower(false), "climate.hallway", service: "turn_off")
    }

    @Test func climateRangeKeepsItsSpread() throws {
        // 20 to 24 around 22. Moving the middle to 23 shifts both ends by one.
        try expectCall(.setTargetTemperature(23), "climate.upstairs", service: "set_temperature",
                       data: ["target_temp_low": 21, "target_temp_high": 25])
    }

    @Test func autoModeFallsBackToAuto() {
        #expect(HVACMode.auto.homeAssistantValue(available: ["off", "auto"]) == "auto")
        #expect(HVACMode.auto.homeAssistantValue(available: []) == "heat_cool")
    }

    @Test func locks() throws {
        try expectCall(.lock, "lock.front_door", service: "lock")
        try expectCall(.unlock, "lock.front_door", service: "unlock")
        try expectCall(.toggle, "lock.front_door", service: "unlock", data: [:])
        try expectCall(.open, "lock.front_door", service: "open", data: [:])
    }

    @Test func covers() throws {
        try expectCall(.open, "cover.living_blinds", service: "open_cover")
        try expectCall(.close, "cover.living_blinds", service: "close_cover")
        try expectCall(.stop, "cover.living_blinds", service: "stop_cover")
        try expectCall(.setPosition(0.25), "cover.living_blinds", service: "set_cover_position", data: ["position": 25])
        try expectCall(.setPower(true), "cover.garage_door", service: "open_cover")
        try expectCall(.toggle, "cover.garage_door", service: "toggle")
    }

    @Test func mediaPlayers() throws {
        try expectCall(.play, "media_player.living_room", service: "media_play")
        try expectCall(.pause, "media_player.living_room", service: "media_pause")
        try expectCall(.nextTrack, "media_player.living_room", service: "media_next_track")
        try expectCall(.previousTrack, "media_player.living_room", service: "media_previous_track")
        try expectCall(.setVolume(0.45), "media_player.living_room", service: "volume_set", data: ["volume_level": 0.45])
        try expectCall(.setVolume(1.4), "media_player.living_room", service: "volume_set", data: ["volume_level": 1])
        try expectCall(.setPower(false), "media_player.living_room", service: "turn_off")
    }

    @Test func alarmAndVacuum() throws {
        try expectCall(.setPower(true), "alarm_control_panel.home", service: "alarm_arm_away")
        try expectCall(.unlock, "alarm_control_panel.home", service: "alarm_disarm")
        try expectCall(.toggle, "alarm_control_panel.home", service: "alarm_disarm")
        try expectCall(.setPower(true), "vacuum.roomba", service: "start")
        try expectCall(.setPower(false), "vacuum.roomba", service: "return_to_base")
        try expectCall(.toggle, "vacuum.roomba", service: "start")
        try expectCall(.pause, "vacuum.roomba", service: "pause")
    }

    @Test func scenesAndScripts() {
        #expect(HACommandMapper.sceneCall(entityID: "scene.movie_time") == HAServiceCall(domain: "scene", service: "turn_on", entityID: "scene.movie_time"))
        #expect(HACommandMapper.sceneCall(entityID: "script.good_night").domain == "script")
    }

    @Test func unsupportedCommandsThrow() {
        #expect(throws: SmartHomeError.self) { try call(.setBrightness(0.5), "lock.front_door") }
        #expect(throws: SmartHomeError.self) { try call(.toggle, "sensor.living_temperature") }
        #expect(throws: SmartHomeError.self) { try call(.play, "light.kitchen") }
    }

    @Test func callServiceRequestPayload() {
        let call = HAServiceCall(domain: "light", service: "turn_on", data: ["brightness_pct": 40], entityID: "light.kitchen")
        let request = call.request
        #expect(request.type == .callService)
        #expect(request.data["domain"] as? String == "light")
        #expect(request.data["service"] as? String == "turn_on")
        #expect((request.data["service_data"] as? [String: Any])?["brightness_pct"] as? Double == 40)
        #expect((request.data["target"] as? [String: Any])?["entity_id"] as? String == "light.kitchen")
        #expect(JSONSerialization.isValidJSONObject(request.data))
    }

    @Test func rawCallTargetsComeFromData() {
        let single = HAServiceCall(domain: "lock", service: "unlock", data: ["entity_id": "lock.front_door"])
        #expect(single.targetEntityIDs == ["lock.front_door"])
        #expect(single.request.data["target"] == nil)
        let many = HAServiceCall(domain: "cover", service: "open_cover", data: ["entity_id": ["cover.a", "cover.b"]])
        #expect(many.targetEntityIDs == ["cover.a", "cover.b"])
    }
}
