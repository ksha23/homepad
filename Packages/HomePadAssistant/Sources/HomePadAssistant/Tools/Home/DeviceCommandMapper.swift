import Foundation
import HomePadCore

/// A spoken verb for a device, as the model sends it to `control_device`.
enum DeviceAction: String, CaseIterable, Sendable {
    case turnOn = "turn_on", turnOff = "turn_off", toggle
    case setBrightness = "set_brightness", dim, brighten
    case setColor = "set_color", setColorTemperature = "set_color_temperature"
    case setTemperature = "set_temperature", setMode = "set_mode"
    case lock, unlock, open, close, stop
    case setPosition = "set_position", setVolume = "set_volume"
    case play, pause, nextTrack = "next_track", previousTrack = "previous_track"
    case arm, disarm
}

/// One requested change, before it is matched to a device.
struct DeviceInstruction: Equatable, Sendable {
    var action: DeviceAction
    /// Percent (0 to 100, or 0 to 1), degrees, or kelvin depending on the action.
    var value: Double?
    var color: String?
    var mode: String?
}

/// Maps a spoken instruction to the right `AccessoryCommand` for each kind of
/// device, so one request can mix lights, fans, thermostats, shades and
/// speakers. "Turn off" means power off for a light, mode off for a
/// thermostat and pause for a speaker.
enum DeviceCommandMapper {
    static func command(for instruction: DeviceInstruction, on accessory: HomeAccessory) -> Result<AccessoryCommand, MappingError> {
        let kind = accessory.kind
        let caps = accessory.capabilities
        let unsupported = Result<AccessoryCommand, MappingError>.failure(.unsupported(accessory.name, instruction.action))

        switch instruction.action {
        case .turnOn, .turnOff, .toggle:
            let on = instruction.action == .turnOn
            switch kind {
            case .thermostat:
                return instruction.action == .toggle ? unsupported : .success(.setHVACMode(on ? .auto : .off))
            case .mediaPlayer:
                return instruction.action == .toggle ? unsupported : .success(on ? .play : .pause)
            case .lock, .garageDoor, .cover, .sensor, .camera, .doorbell:
                return unsupported
            default:
                guard isPowerable(accessory) else { return unsupported }
                return .success(instruction.action == .toggle ? .toggle : .setPower(on))
            }
        case .setBrightness:
            guard supportsBrightness(accessory) else { return unsupported }
            guard let value = instruction.value else { return .failure(.missingValue(instruction.action)) }
            let level = percent(value)
            return .success(level <= 0 ? .setPower(false) : .setBrightness(level))
        case .dim, .brighten:
            guard supportsBrightness(accessory) else { return unsupported }
            let step = percent(instruction.value ?? 25)
            let current = accessory.state.brightness ?? (accessory.state.isOn == true ? 1 : 0)
            let target = instruction.action == .dim ? current - step : current + step
            return .success(.setBrightness(min(1, max(0.01, target))))
        case .setColor:
            guard let name = instruction.color, let color = NamedColor(name) else { return .failure(.unknownColor(instruction.color ?? "")) }
            switch color {
            case .hue(let hue, let saturation):
                return caps.contains(.color) ? .success(.setHueSaturation(hue: hue, saturation: saturation)) : unsupported
            case .white(let kelvin):
                if caps.contains(.colorTemperature) { return .success(.setColorTemperature(kelvin: kelvin)) }
                return caps.contains(.color) ? .success(.setHueSaturation(hue: 0, saturation: 0)) : unsupported
            }
        case .setColorTemperature:
            guard caps.contains(.colorTemperature) else { return unsupported }
            guard let value = instruction.value, value > 0 else { return .failure(.missingValue(instruction.action)) }
            return .success(.setColorTemperature(kelvin: Int(value < 1000 ? 1_000_000 / value : value)))
        case .setTemperature:
            guard kind == .thermostat || caps.contains(.targetTemperature) else { return unsupported }
            guard let value = instruction.value else { return .failure(.missingValue(instruction.action)) }
            return .success(.setTargetTemperature(value))
        case .setMode:
            guard kind == .thermostat || caps.contains(.hvacMode) else { return unsupported }
            guard let mode = instruction.mode.flatMap(hvacMode) else { return .failure(.unknownMode(instruction.mode ?? "")) }
            return .success(.setHVACMode(mode))
        case .lock, .unlock:
            guard kind == .lock || caps.contains(.lock) else { return unsupported }
            return .success(instruction.action == .lock ? .lock : .unlock)
        case .open, .close:
            let open = instruction.action == .open
            if kind == .lock || caps.contains(.lock) { return .success(open ? .unlock : .lock) }
            guard kind == .cover || kind == .garageDoor || caps.contains(.position) else { return unsupported }
            return .success(open ? .open : .close)
        case .stop:
            if kind == .cover || kind == .garageDoor { return .success(.stop) }
            return kind == .mediaPlayer ? .success(.pause) : unsupported
        case .setPosition:
            guard kind == .cover || kind == .garageDoor || caps.contains(.position) else { return unsupported }
            guard let value = instruction.value else { return .failure(.missingValue(instruction.action)) }
            return .success(.setPosition(percent(value)))
        case .setVolume:
            guard kind == .mediaPlayer || caps.contains(.volume) else { return unsupported }
            guard let value = instruction.value else { return .failure(.missingValue(instruction.action)) }
            return .success(.setVolume(percent(value)))
        case .play, .pause, .nextTrack, .previousTrack:
            guard kind == .mediaPlayer || caps.contains(.playback) else { return unsupported }
            let commands: [DeviceAction: AccessoryCommand] = [.play: .play, .pause: .pause, .nextTrack: .nextTrack, .previousTrack: .previousTrack]
            return .success(commands[instruction.action] ?? .pause)
        case .arm, .disarm:
            guard kind == .securitySystem else { return unsupported }
            return .success(.setPower(instruction.action == .arm))
        }
    }

    /// Accepts 0 to 1 or 0 to 100 and returns 0 to 1.
    static func percent(_ value: Double) -> Double {
        min(1, max(0, value > 1 ? value / 100 : value))
    }

    static func isPowerable(_ accessory: HomeAccessory) -> Bool {
        accessory.capabilities.contains(.power)
            || [.light, .switchOutlet, .fan, .airPurifier, .vacuum, .securitySystem].contains(accessory.kind)
    }

    static func supportsBrightness(_ accessory: HomeAccessory) -> Bool {
        accessory.capabilities.contains(.brightness)
    }

    static func hvacMode(_ text: String) -> HVACMode? {
        switch DeviceTargetResolver.normalize(text).replacingOccurrences(of: "_", with: " ") {
        case "heat", "heating", "warm": .heat
        case "cool", "cooling", "ac", "air conditioning": .cool
        case "auto", "automatic", "heat cool", "heatcool": .auto
        case "off": .off
        case "fan", "fan only", "fanonly": .fanOnly
        case "dry", "dehumidify": .dry
        default: nil
        }
    }

    /// Why an instruction did not fit a device. The text is relayed to the person.
    enum MappingError: Error, Equatable, CustomStringConvertible {
        case unsupported(String, DeviceAction)
        case missingValue(DeviceAction)
        case unknownColor(String)
        case unknownMode(String)

        var description: String {
            switch self {
            case .unsupported(let name, let action): "\(name) cannot \(action.rawValue.replacingOccurrences(of: "_", with: " "))."
            case .missingValue(let action): "\(action.rawValue.replacingOccurrences(of: "_", with: " ")) needs a value."
            case .unknownColor(let color): "\(color) is not a color HomePad knows."
            case .unknownMode(let mode): "\(mode) is not a thermostat mode."
            }
        }
    }
}
