import Foundation
import HomePadCore

/// Turns a backend-neutral `AccessoryCommand` into a Home Assistant service call.
/// Pure, so every domain's mapping is covered by tests.
enum HACommandMapper {
    /// - Parameter state: The entity's current state, used for toggles and thermostat ranges.
    static func serviceCall(for command: AccessoryCommand, entityID: String, state: HAState?) throws -> HAServiceCall {
        let domain = HAState.domain(of: entityID)
        let call: (String, [String: JSONValue]) -> HAServiceCall = { service, data in
            HAServiceCall(domain: domain, service: service, data: data, entityID: entityID)
        }
        let mapped: HAServiceCall?
        switch domain {
        case "light": mapped = light(command, call)
        case "switch", "input_boolean": mapped = power(command, call)
        case "fan": mapped = fan(command, call)
        case "climate": mapped = climate(command, state: state, call)
        case "lock": mapped = lock(command, state: state, call)
        case "cover": mapped = cover(command, state: state, call)
        case "media_player": mapped = mediaPlayer(command, call)
        case "alarm_control_panel": mapped = alarm(command, state: state, call)
        case "vacuum": mapped = vacuum(command, state: state, call)
        default: mapped = nil
        }
        guard let mapped else {
            throw SmartHomeError.unsupported("\(String(describing: command)) on \(entityID)")
        }
        return mapped
    }

    /// `scene.turn_on` or `script.turn_on`.
    static func sceneCall(entityID: String) -> HAServiceCall {
        HAServiceCall(domain: HAState.domain(of: entityID), service: "turn_on", entityID: entityID)
    }

    private typealias Make = (String, [String: JSONValue]) -> HAServiceCall

    private static func power(_ command: AccessoryCommand, _ call: Make) -> HAServiceCall? {
        switch command {
        case .setPower(let on): call(on ? "turn_on" : "turn_off", [:])
        case .toggle: call("toggle", [:])
        default: nil
        }
    }

    private static func light(_ command: AccessoryCommand, _ call: Make) -> HAServiceCall? {
        switch command {
        case .setBrightness(let level):
            level <= 0 ? call("turn_off", [:]) : call("turn_on", ["brightness_pct": .number(percent(level, minimum: 1))])
        case .setColorTemperature(let kelvin):
            call("turn_on", ["color_temp_kelvin": .number(Double(kelvin))])
        case .setHueSaturation(let hue, let saturation):
            call("turn_on", ["hs_color": [.number(hue.rounded()), .number(percent(saturation, minimum: 0))]])
        default:
            power(command, call)
        }
    }

    private static func fan(_ command: AccessoryCommand, _ call: Make) -> HAServiceCall? {
        if case .setBrightness(let level) = command {
            return level <= 0 ? call("turn_off", [:]) : call("set_percentage", ["percentage": .number(percent(level, minimum: 1))])
        }
        return power(command, call)
    }

    private static func climate(_ command: AccessoryCommand, state: HAState?, _ call: Make) -> HAServiceCall? {
        switch command {
        case .setTargetTemperature(let target):
            // Range thermostats (heat_cool with low and high) keep their spread around the new middle.
            if state?["temperature"]?.doubleValue == nil,
               let low = state?["target_temp_low"]?.doubleValue, let high = state?["target_temp_high"]?.doubleValue {
                let shift = target - (low + high) / 2
                return call("set_temperature", ["target_temp_low": .number(low + shift), "target_temp_high": .number(high + shift)])
            }
            return call("set_temperature", ["temperature": .number(target)])
        case .setHVACMode(let mode):
            let available = state?["hvac_modes"]?.stringArray ?? []
            return call("set_hvac_mode", ["hvac_mode": .string(mode.homeAssistantValue(available: available))])
        default:
            return power(command, call)
        }
    }

    private static func lock(_ command: AccessoryCommand, state: HAState?, _ call: Make) -> HAServiceCall? {
        switch command {
        case .lock: call("lock", [:])
        case .unlock: call("unlock", [:])
        case .open: state?.supports(HAFeature.lockOpen) == true ? call("open", [:]) : call("unlock", [:])
        case .toggle: call(state?.state == "locked" ? "unlock" : "lock", [:])
        default: nil
        }
    }

    private static func cover(_ command: AccessoryCommand, state: HAState?, _ call: Make) -> HAServiceCall? {
        switch command {
        case .open, .setPower(true): call("open_cover", [:])
        case .close, .setPower(false): call("close_cover", [:])
        case .stop: call("stop_cover", [:])
        case .toggle: call("toggle", [:])
        case .setPosition(let position):
            if let state, HAStateMapper.coverTiltsOnly(state) {
                call("set_cover_tilt_position", ["tilt_position": .number(percent(position, minimum: 0))])
            } else {
                call("set_cover_position", ["position": .number(percent(position, minimum: 0))])
            }
        default: nil
        }
    }

    private static func mediaPlayer(_ command: AccessoryCommand, _ call: Make) -> HAServiceCall? {
        switch command {
        case .play: call("media_play", [:])
        case .pause: call("media_pause", [:])
        case .nextTrack: call("media_next_track", [:])
        case .previousTrack: call("media_previous_track", [:])
        case .setVolume(let volume): call("volume_set", ["volume_level": .number(min(max(volume, 0), 1))])
        default: power(command, call)
        }
    }

    private static func alarm(_ command: AccessoryCommand, state: HAState?, _ call: Make) -> HAServiceCall? {
        let arm = call("alarm_arm_away", [:])
        let disarm = call("alarm_disarm", [:])
        switch command {
        case .setPower(let on): return on ? arm : disarm
        case .lock: return arm
        case .unlock: return disarm
        case .toggle: return state?.state == "disarmed" ? arm : disarm
        default: return nil
        }
    }

    private static func vacuum(_ command: AccessoryCommand, state: HAState?, _ call: Make) -> HAServiceCall? {
        switch command {
        case .setPower(true), .play: call("start", [:])
        case .setPower(false): call("return_to_base", [:])
        case .pause: call("pause", [:])
        case .stop: call("stop", [:])
        case .toggle: call(state?.state == "cleaning" ? "return_to_base" : "start", [:])
        default: nil
        }
    }

    /// 0...1 to a whole percentage.
    private static func percent(_ level: Double, minimum: Double) -> Double {
        min(max((level * 100).rounded(), minimum), 100)
    }
}
