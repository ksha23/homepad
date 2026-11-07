import Foundation
import HomeKit
import HomePadCore
import Testing
@testable import HomePadSmartHome

@Suite("HomeKit mapping")
struct HomeKitMappingTests {
    private func state(_ serviceType: String, _ values: [String: Any], unit: TemperatureUnit = .celsius) -> AccessoryState {
        let kind = HomeKitServiceMapper.kind(forServiceType: serviceType)!
        return HomeKitServiceMapper.state(serviceType: serviceType, kind: kind, values: HomeKitValues(values), unit: unit)
    }

    private func writes(_ command: AccessoryCommand, _ serviceType: String, state: AccessoryState = AccessoryState(),
                        types: [String], unit: TemperatureUnit = .celsius) throws -> [HomeKitWrite] {
        let kind = HomeKitServiceMapper.kind(forServiceType: serviceType)!
        return try HomeKitCommandMapper.writes(for: command, target: .init(
            serviceType: serviceType, kind: kind, state: state, characteristicTypes: Set(types), unit: unit))
    }

    @Test func serviceKinds() {
        #expect(HomeKitServiceMapper.kind(forServiceType: HMServiceTypeLightbulb) == .light)
        #expect(HomeKitServiceMapper.kind(forServiceType: HMServiceTypeOutlet) == .switchOutlet)
        #expect(HomeKitServiceMapper.kind(forServiceType: HMServiceTypeHeaterCooler) == .thermostat)
        #expect(HomeKitServiceMapper.kind(forServiceType: HMServiceTypeGarageDoorOpener) == .garageDoor)
        #expect(HomeKitServiceMapper.kind(forServiceType: HMServiceTypeWindowCovering) == .cover)
        #expect(HomeKitServiceMapper.kind(forServiceType: HMServiceTypeDoorbell) == .doorbell)
        #expect(HomeKitServiceMapper.kind(forServiceType: HMServiceTypeContactSensor) == .sensor)
        #expect(HomeKitServiceMapper.kind(forServiceType: HMServiceTypeAccessoryInformation) == nil)
    }

    @Test func lightState() {
        let light = state(HMServiceTypeLightbulb, [
            HMCharacteristicTypePowerState: NSNumber(value: true), HMCharacteristicTypeBrightness: NSNumber(value: 64),
            HMCharacteristicTypeColorTemperature: NSNumber(value: 370), HMCharacteristicTypeHue: NSNumber(value: 120),
            HMCharacteristicTypeSaturation: NSNumber(value: 50),
        ])
        #expect(light.isOn == true)
        #expect(light.brightness == 0.64)
        #expect(light.colorTemperatureKelvin == 2703)
        #expect(light.hue == 120)
        #expect(light.saturation == 0.5)
        let capabilities = HomeKitServiceMapper.capabilities(kind: .light, characteristicTypes: [HMCharacteristicTypePowerState, HMCharacteristicTypeBrightness])
        #expect(capabilities == [.power, .brightness])
    }

    @Test func thermostatConvertsToFahrenheit() {
        let thermostat = state(HMServiceTypeThermostat, [
            HMCharacteristicTypeCurrentTemperature: NSNumber(value: 22.0), HMCharacteristicTypeTargetTemperature: NSNumber(value: 21.0),
            HMCharacteristicTypeTargetHeatingCooling: NSNumber(value: 2), HMCharacteristicTypeCurrentRelativeHumidity: NSNumber(value: 38),
        ], unit: .fahrenheit)
        #expect(abs((thermostat.currentTemperature ?? 0) - 71.6) < 0.001)
        #expect(abs((thermostat.targetTemperature ?? 0) - 69.8) < 0.001)
        #expect(thermostat.hvacMode == .cool)
        #expect(thermostat.humidity == 38)
        #expect(thermostat.isOn == true)
    }

    @Test func heaterCoolerUsesThresholds() {
        let unit = state(HMServiceTypeHeaterCooler, [
            HMCharacteristicTypeActive: NSNumber(value: 1), HMCharacteristicTypeTargetHeaterCoolerState: NSNumber(value: 1),
            HMCharacteristicTypeHeatingThreshold: NSNumber(value: 20), HMCharacteristicTypeCoolingThreshold: NSNumber(value: 25),
        ])
        #expect(unit.hvacMode == .heat)
        #expect(unit.targetTemperature == 20)
        #expect(state(HMServiceTypeHeaterCooler, [HMCharacteristicTypeActive: NSNumber(value: 0)]).hvacMode == .off)
    }

    @Test func locksDoorsAndSensors() {
        #expect(state(HMServiceTypeLockMechanism, [HMCharacteristicTypeCurrentLockMechanismState: NSNumber(value: 1)]).lockState == .locked)
        #expect(state(HMServiceTypeLockMechanism, [HMCharacteristicTypeCurrentLockMechanismState: NSNumber(value: 0)]).lockState == .unlocked)
        #expect(state(HMServiceTypeLockMechanism, [:]).lockState == .unknown)
        // Locked by hand after HomeKit last unlocked it: the target still says unlocked.
        #expect(state(HMServiceTypeLockMechanism, [HMCharacteristicTypeCurrentLockMechanismState: NSNumber(value: 1),
                                                   HMCharacteristicTypeTargetLockMechanismState: NSNumber(value: 0)]).lockState == .locked)
        #expect(state(HMServiceTypeLockMechanism, [HMCharacteristicTypeTargetLockMechanismState: NSNumber(value: 0)]).lockState == .unknown)
        let garage = state(HMServiceTypeGarageDoorOpener, [HMCharacteristicTypeCurrentDoorState: NSNumber(value: 0)])
        #expect(garage.doorState == .open)
        #expect(garage.position == 1)
        let blinds = state(HMServiceTypeWindowCovering, [HMCharacteristicTypeCurrentPosition: NSNumber(value: 30)])
        #expect(blinds.position == 0.3)
        let contact = state(HMServiceTypeContactSensor, [HMCharacteristicTypeContactState: NSNumber(value: 1)])
        #expect(contact.doorState == .open)
        #expect(state(HMServiceTypeMotionSensor, [HMCharacteristicTypeMotionDetected: NSNumber(value: true)]).isActive == true)
        let security = state(HMServiceTypeSecuritySystem, [HMCharacteristicTypeCurrentSecuritySystemState: NSNumber(value: 4)])
        #expect(security.isOn == true)
        #expect(security.isActive == true)
    }

    @Test func lightCommands() throws {
        let types = [HMCharacteristicTypePowerState, HMCharacteristicTypeBrightness, HMCharacteristicTypeColorTemperature]
        #expect(try writes(.setPower(true), HMServiceTypeLightbulb, types: types) == [HomeKitWrite(characteristicType: HMCharacteristicTypePowerState, value: true)])
        #expect(try writes(.setBrightness(0.42), HMServiceTypeLightbulb, types: types) == [
            HomeKitWrite(characteristicType: HMCharacteristicTypePowerState, value: true),
            HomeKitWrite(characteristicType: HMCharacteristicTypeBrightness, value: 42),
        ])
        #expect(try writes(.setColorTemperature(kelvin: 2700), HMServiceTypeLightbulb, types: types)
            == [HomeKitWrite(characteristicType: HMCharacteristicTypeColorTemperature, value: 370)])
        #expect(try writes(.toggle, HMServiceTypeLightbulb, state: AccessoryState(isOn: true), types: types)
            == [HomeKitWrite(characteristicType: HMCharacteristicTypePowerState, value: false)])
    }

    @Test func matterFansAreFans() throws {
        // Fan v2, which HomeKit calls a ventilation fan: Matter fans such as Dreo.
        #expect(HomeKitServiceMapper.kind(forServiceType: HMServiceTypeVentilationFan) == .fan)
        let types = [HMCharacteristicTypeActive, HMCharacteristicTypeRotationSpeed]
        #expect(try writes(.setPower(true), HMServiceTypeVentilationFan, types: types)
            == [HomeKitWrite(characteristicType: HMCharacteristicTypeActive, value: 1)])
        #expect(try writes(.toggle, HMServiceTypeVentilationFan, state: AccessoryState(isOn: true), types: types)
            == [HomeKitWrite(characteristicType: HMCharacteristicTypeActive, value: 0)])
        // Setting a speed turns the fan on as well.
        #expect(try writes(.setBrightness(0.5), HMServiceTypeVentilationFan, types: types) == [
            HomeKitWrite(characteristicType: HMCharacteristicTypeActive, value: 1),
            HomeKitWrite(characteristicType: HMCharacteristicTypeRotationSpeed, value: 50),
        ])
        let on = state(HMServiceTypeVentilationFan, [HMCharacteristicTypeActive: NSNumber(value: 1), HMCharacteristicTypeRotationSpeed: NSNumber(value: 40)])
        #expect(on.isOn == true)
        #expect(on.brightness == 0.4)
    }

    @Test func thermostatCommandsWriteCelsius() throws {
        let types = [HMCharacteristicTypeTargetTemperature, HMCharacteristicTypeTargetHeatingCooling]
        let target = try writes(.setTargetTemperature(68), HMServiceTypeThermostat, types: types, unit: .fahrenheit)
        #expect(target.first?.characteristicType == HMCharacteristicTypeTargetTemperature)
        #expect(abs((target.first?.value.doubleValue ?? 0) - 20) < 0.001)
        #expect(try writes(.setHVACMode(.heat), HMServiceTypeThermostat, types: types)
            == [HomeKitWrite(characteristicType: HMCharacteristicTypeTargetHeatingCooling, value: 1)])
        #expect(throws: SmartHomeError.self) { try writes(.setHVACMode(.dry), HMServiceTypeThermostat, types: types) }
    }

    @Test func lockAndGarageCommands() throws {
        let lockTypes = [HMCharacteristicTypeTargetLockMechanismState]
        #expect(try writes(.unlock, HMServiceTypeLockMechanism, types: lockTypes)
            == [HomeKitWrite(characteristicType: HMCharacteristicTypeTargetLockMechanismState, value: 0)])
        #expect(try writes(.toggle, HMServiceTypeLockMechanism, state: AccessoryState(lockState: .unlocked), types: lockTypes)
            == [HomeKitWrite(characteristicType: HMCharacteristicTypeTargetLockMechanismState, value: 1)])
        let garageTypes = [HMCharacteristicTypeTargetDoorState]
        #expect(try writes(.open, HMServiceTypeGarageDoorOpener, types: garageTypes)
            == [HomeKitWrite(characteristicType: HMCharacteristicTypeTargetDoorState, value: 0)])
        #expect(try writes(.toggle, HMServiceTypeGarageDoorOpener, state: AccessoryState(doorState: .open), types: garageTypes)
            == [HomeKitWrite(characteristicType: HMCharacteristicTypeTargetDoorState, value: 1)])
    }

    @Test func coverAndUnsupportedCommands() throws {
        let types = [HMCharacteristicTypeTargetPosition, HMCharacteristicTypeCurrentPosition]
        #expect(try writes(.setPosition(0.75), HMServiceTypeWindowCovering, types: types)
            == [HomeKitWrite(characteristicType: HMCharacteristicTypeTargetPosition, value: 75)])
        #expect(throws: SmartHomeError.self) { try writes(.stop, HMServiceTypeWindowCovering, types: types) }
        #expect(throws: SmartHomeError.self) { try writes(.play, HMServiceTypeLightbulb, types: [HMCharacteristicTypePowerState]) }
    }
}
