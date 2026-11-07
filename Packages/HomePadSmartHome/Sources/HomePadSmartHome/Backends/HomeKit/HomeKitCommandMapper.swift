import Foundation
@preconcurrency import HomeKit
import HomePadCore

/// One characteristic write HomeKit should perform.
struct HomeKitWrite: Equatable {
    var characteristicType: String
    var value: NSNumber
}

/// Turns an `AccessoryCommand` into HomeKit characteristic writes. Pure and tested.
enum HomeKitCommandMapper {
    struct Target {
        var serviceType: String
        var kind: AccessoryKind
        var state: AccessoryState
        var characteristicTypes: Set<String>
        var unit: TemperatureUnit
    }

    static func writes(for command: AccessoryCommand, target: Target) throws -> [HomeKitWrite] {
        let writes = map(command, target)
        guard let writes, !writes.isEmpty else {
            throw SmartHomeError.unsupported("\(String(describing: command)) on this Apple Home accessory")
        }
        return writes
    }

    private static func write(_ type: String, _ value: NSNumber) -> HomeKitWrite {
        HomeKitWrite(characteristicType: type, value: value)
    }

    private static func map(_ command: AccessoryCommand, _ target: Target) -> [HomeKitWrite]? {
        let state = target.state
        switch command {
        case .toggle:
            return map(toggled(target), target)
        case .setPower(let on):
            return power(on, target)
        case .setBrightness(let level):
            let percent = NSNumber(value: Int((min(max(level, 0), 1) * 100).rounded()))
            switch target.kind {
            case .light: return [write(HMCharacteristicTypePowerState, NSNumber(value: level > 0)), write(HMCharacteristicTypeBrightness, percent)]
            // A fan that is off stays off when only its speed changes, so turn it on too.
            case .fan: return level > 0 ? (power(true, target) ?? []) + [write(HMCharacteristicTypeRotationSpeed, percent)] : power(false, target)
            default: return nil
            }
        case .setColorTemperature(let kelvin):
            guard target.kind == .light, kelvin > 0 else { return nil }
            let mireds = min(max(1_000_000 / kelvin, 140), 500)
            return [write(HMCharacteristicTypeColorTemperature, NSNumber(value: mireds))]
        case .setHueSaturation(let hue, let saturation):
            guard target.kind == .light else { return nil }
            return [write(HMCharacteristicTypeHue, NSNumber(value: Float(hue))), write(HMCharacteristicTypeSaturation, NSNumber(value: Float(saturation * 100)))]
        case .setTargetTemperature(let value):
            guard target.kind == .thermostat else { return nil }
            let celsius = NSNumber(value: Float(HomeKitServiceMapper.celsius(from: value, unit: target.unit)))
            if target.serviceType == HMServiceTypeHeaterCooler {
                return [write(state.hvacMode == .cool ? HMCharacteristicTypeCoolingThreshold : HMCharacteristicTypeHeatingThreshold, celsius)]
            }
            return [write(HMCharacteristicTypeTargetTemperature, celsius)]
        case .setHVACMode(let mode):
            return hvac(mode, target)
        case .lock, .unlock:
            let locking = command == .lock
            switch target.kind {
            case .lock: return [write(HMCharacteristicTypeTargetLockMechanismState, NSNumber(value: locking ? 1 : 0))]
            case .securitySystem: return power(locking, target)
            default: return nil
            }
        case .open, .close:
            let opening = command == .open
            switch target.kind {
            case .lock: return opening ? map(.unlock, target) : nil
            case .garageDoor, .cover: return power(opening, target)
            default: return nil
            }
        case .setPosition(let position):
            if target.serviceType == HMServiceTypeGarageDoorOpener { return power(position > 0, target) }
            guard target.characteristicTypes.contains(HMCharacteristicTypeTargetPosition) else { return nil }
            return [write(HMCharacteristicTypeTargetPosition, NSNumber(value: Int((min(max(position, 0), 1) * 100).rounded())))]
        case .stop:
            guard target.characteristicTypes.contains(HMCharacteristicTypeHoldPosition) else { return nil }
            return [write(HMCharacteristicTypeHoldPosition, NSNumber(value: true))]
        case .setVolume, .play, .pause, .nextTrack, .previousTrack:
            return nil
        }
    }

    /// What "toggle" means for each kind, based on the current state.
    private static func toggled(_ target: Target) -> AccessoryCommand {
        let state = target.state
        switch target.kind {
        case .lock: return state.lockState == .locked ? .unlock : .lock
        case .garageDoor, .cover:
            let isOpen = state.doorState.map { $0 == .open || $0 == .opening } ?? ((state.position ?? 0) > 0.01)
            return isOpen ? .close : .open
        default: return .setPower(!(state.isOn ?? false))
        }
    }

    private static func power(_ on: Bool, _ target: Target) -> [HomeKitWrite]? {
        let types = target.characteristicTypes
        switch target.kind {
        case .light, .switchOutlet:
            return [write(HMCharacteristicTypePowerState, NSNumber(value: on))]
        case .fan, .airPurifier:
            if types.contains(HMCharacteristicTypePowerState) { return [write(HMCharacteristicTypePowerState, NSNumber(value: on))] }
            return [write(HMCharacteristicTypeActive, NSNumber(value: on ? 1 : 0))]
        case .thermostat:
            return hvac(on ? .auto : .off, target)
        case .securitySystem:
            // 1 is away arm, 3 is disarm.
            return [write(HMCharacteristicTypeTargetSecuritySystemState, NSNumber(value: on ? 1 : 3))]
        case .garageDoor where target.serviceType == HMServiceTypeGarageDoorOpener:
            // 0 is open, 1 is closed.
            return [write(HMCharacteristicTypeTargetDoorState, NSNumber(value: on ? 0 : 1))]
        case .garageDoor, .cover:
            return [write(HMCharacteristicTypeTargetPosition, NSNumber(value: on ? 100 : 0))]
        default:
            return nil
        }
    }

    private static func hvac(_ mode: HVACMode, _ target: Target) -> [HomeKitWrite]? {
        guard target.kind == .thermostat else { return nil }
        if target.serviceType == HMServiceTypeHeaterCooler {
            guard let value = [HVACMode.auto: 0, .heat: 1, .cool: 2][mode] else {
                return mode == .off ? [write(HMCharacteristicTypeActive, NSNumber(value: 0))] : nil
            }
            return [write(HMCharacteristicTypeActive, NSNumber(value: 1)), write(HMCharacteristicTypeTargetHeaterCoolerState, NSNumber(value: value))]
        }
        guard let value = [HVACMode.off: 0, .heat: 1, .cool: 2, .auto: 3][mode] else { return nil }
        return [write(HMCharacteristicTypeTargetHeatingCooling, NSNumber(value: value))]
    }
}
