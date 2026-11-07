import Foundation
@preconcurrency import HomeKit
import HomePadCore

/// Maps HomeKit services to HomePad kinds, capabilities and state.
/// Pure, so it is tested with plain dictionaries instead of real accessories.
enum HomeKitServiceMapper {
    static func kind(forServiceType type: String) -> AccessoryKind? {
        switch type {
        case HMServiceTypeLightbulb: .light
        case HMServiceTypeSwitch, HMServiceTypeOutlet: .switchOutlet
        // HomeKit calls Fan v2 (Matter fans, most newer fans) a ventilation fan.
        case HMServiceTypeFan, HMServiceTypeVentilationFan: .fan
        case HMServiceTypeThermostat, HMServiceTypeHeaterCooler: .thermostat
        case HMServiceTypeLockMechanism: .lock
        case HMServiceTypeGarageDoorOpener, HMServiceTypeDoor: .garageDoor
        case HMServiceTypeWindowCovering, HMServiceTypeWindow: .cover
        case HMServiceTypeSecuritySystem: .securitySystem
        case HMServiceTypeAirPurifier: .airPurifier
        case HMServiceTypeDoorbell: .doorbell
        case HMServiceTypeTemperatureSensor, HMServiceTypeHumiditySensor, HMServiceTypeMotionSensor,
             HMServiceTypeContactSensor, HMServiceTypeOccupancySensor, HMServiceTypeLeakSensor,
             HMServiceTypeSmokeSensor, HMServiceTypeCarbonMonoxideSensor, HMServiceTypeLightSensor: .sensor
        default: nil
        }
    }

    /// What a sensor measures, named like Home Assistant's device classes so both
    /// backends read the same way ("Motion", "Leak", "Smoke"). Nil for other services.
    static func deviceClass(forServiceType type: String) -> String? {
        switch type {
        case HMServiceTypeTemperatureSensor: "temperature"
        case HMServiceTypeHumiditySensor: "humidity"
        case HMServiceTypeLightSensor: "illuminance"
        case HMServiceTypeMotionSensor: "motion"
        case HMServiceTypeOccupancySensor: "occupancy"
        case HMServiceTypeContactSensor: "opening"
        case HMServiceTypeLeakSensor: "moisture"
        case HMServiceTypeSmokeSensor: "smoke"
        case HMServiceTypeCarbonMonoxideSensor: "carbon_monoxide"
        default: nil
        }
    }

    static func capabilities(kind: AccessoryKind, characteristicTypes types: Set<String>) -> Set<AccessoryCapability> {
        switch kind {
        case .light:
            var result: Set<AccessoryCapability> = [.power]
            if types.contains(HMCharacteristicTypeBrightness) { result.insert(.brightness) }
            if types.contains(HMCharacteristicTypeColorTemperature) { result.insert(.colorTemperature) }
            if types.contains(HMCharacteristicTypeHue), types.contains(HMCharacteristicTypeSaturation) { result.insert(.color) }
            return result
        case .fan:
            return types.contains(HMCharacteristicTypeRotationSpeed) ? [.power, .brightness] : [.power]
        case .switchOutlet, .airPurifier, .securitySystem: return [.power]
        case .thermostat: return [.targetTemperature, .hvacMode]
        case .lock: return [.lock]
        case .cover, .garageDoor: return types.contains(HMCharacteristicTypeTargetPosition) ? [.position] : []
        default: return []
        }
    }

    static func state(serviceType: String, kind: AccessoryKind, values: HomeKitValues, unit: TemperatureUnit) -> AccessoryState {
        let temperature: (String) -> Double? = { values.double($0).map { convert($0, to: unit) } }
        var state = AccessoryState()
        switch kind {
        case .light:
            state.isOn = values.bool(HMCharacteristicTypePowerState)
            state.brightness = values.double(HMCharacteristicTypeBrightness).map { $0 / 100 }
            state.colorTemperatureKelvin = values.double(HMCharacteristicTypeColorTemperature).flatMap { $0 > 0 ? Int((1_000_000 / $0).rounded()) : nil }
            state.hue = values.double(HMCharacteristicTypeHue)
            state.saturation = values.double(HMCharacteristicTypeSaturation).map { $0 / 100 }
        case .switchOutlet:
            state.isOn = values.bool(HMCharacteristicTypePowerState)
        case .fan, .airPurifier:
            state.isOn = values.bool(HMCharacteristicTypePowerState) ?? values.int(HMCharacteristicTypeActive).map { $0 == 1 }
            if state.isOn == true { state.brightness = values.double(HMCharacteristicTypeRotationSpeed).map { $0 / 100 } }
        case .thermostat:
            state.currentTemperature = temperature(HMCharacteristicTypeCurrentTemperature)
            state.humidity = values.double(HMCharacteristicTypeCurrentRelativeHumidity)
            state.temperatureUnit = unit
            if serviceType == HMServiceTypeHeaterCooler {
                let active = values.int(HMCharacteristicTypeActive) == 1
                let mode: HVACMode = !active ? .off : [0: .auto, 1: .heat, 2: .cool][values.int(HMCharacteristicTypeTargetHeaterCoolerState) ?? 0] ?? .auto
                state.hvacMode = mode
                state.targetTemperature = mode == .cool ? temperature(HMCharacteristicTypeCoolingThreshold) : temperature(HMCharacteristicTypeHeatingThreshold)
            } else {
                state.hvacMode = [0: .off, 1: .heat, 2: .cool, 3: .auto][values.int(HMCharacteristicTypeTargetHeatingCooling) ?? 0]
                state.targetTemperature = temperature(HMCharacteristicTypeTargetTemperature)
            }
            state.isOn = state.hvacMode.map { $0 != .off }
        case .lock:
            // Only what the lock reports. Its target is the last command sent through HomeKit, which still
            // says unlock after the door is locked by hand or locks itself.
            let raw = values.int(HMCharacteristicTypeCurrentLockMechanismState)
            state.lockState = [0: .unlocked, 1: .locked, 2: .jammed][raw ?? 3] ?? .unknown
        case .garageDoor where serviceType == HMServiceTypeGarageDoorOpener:
            let door: DoorState = [0: .open, 1: .closed, 2: .opening, 3: .closing, 4: .stopped][values.int(HMCharacteristicTypeCurrentDoorState) ?? -1] ?? .unknown
            state.doorState = door
            state.position = door == .closed ? 0 : (door == .unknown ? nil : 1)
        case .garageDoor, .cover:
            state.position = values.double(HMCharacteristicTypeCurrentPosition).map { $0 / 100 }
            state.doorState = state.position.map { $0 > 0.01 ? .open : .closed }
        case .securitySystem:
            let raw = values.int(HMCharacteristicTypeCurrentSecuritySystemState) ?? 3
            state.isOn = raw != 3
            state.isActive = raw == 4
        case .sensor:
            sensorState(serviceType: serviceType, values: values, unit: unit, into: &state)
        case .doorbell:
            state.isActive = false
        default:
            break
        }
        return state
    }

    private static func sensorState(serviceType: String, values: HomeKitValues, unit: TemperatureUnit, into state: inout AccessoryState) {
        let detected: (String) -> Bool? = { values.int($0).map { $0 != 0 } }
        switch serviceType {
        case HMServiceTypeTemperatureSensor:
            state.currentTemperature = values.double(HMCharacteristicTypeCurrentTemperature).map { convert($0, to: unit) }
            state.sensorValue = state.currentTemperature
            state.sensorUnit = "°"
        case HMServiceTypeHumiditySensor:
            state.humidity = values.double(HMCharacteristicTypeCurrentRelativeHumidity)
            state.sensorValue = state.humidity
            state.sensorUnit = "%"
        case HMServiceTypeLightSensor:
            state.sensorValue = values.double(HMCharacteristicTypeCurrentLightLevel)
            state.sensorUnit = " lx"
        case HMServiceTypeContactSensor:
            // 0 means contact (closed), 1 means no contact (open).
            state.isActive = detected(HMCharacteristicTypeContactState)
            state.doorState = state.isActive.map { $0 ? .open : .closed }
        case HMServiceTypeMotionSensor:
            state.isActive = values.bool(HMCharacteristicTypeMotionDetected)
        case HMServiceTypeOccupancySensor:
            state.isActive = detected(HMCharacteristicTypeOccupancyDetected)
        case HMServiceTypeLeakSensor:
            state.isActive = detected(HMCharacteristicTypeLeakDetected)
        case HMServiceTypeSmokeSensor:
            state.isActive = detected(HMCharacteristicTypeSmokeDetected)
        case HMServiceTypeCarbonMonoxideSensor:
            state.isActive = detected(HMCharacteristicTypeCarbonMonoxideDetected)
        default:
            break
        }
    }

    /// HomeKit reports Celsius. Display in the unit the person chose.
    static func convert(_ celsius: Double, to unit: TemperatureUnit) -> Double {
        unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    static func celsius(from value: Double, unit: TemperatureUnit) -> Double {
        unit == .fahrenheit ? (value - 32) * 5 / 9 : value
    }
}
