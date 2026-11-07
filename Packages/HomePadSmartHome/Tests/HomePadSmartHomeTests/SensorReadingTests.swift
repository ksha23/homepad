import Foundation
import HomeKit
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// Which accessories the Home app shows as tiles and which as compact sensor
/// readings, and what each reading says.
@Suite("Sensor readings")
struct SensorReadingTests {
    private func sensor(_ state: AccessoryState, deviceClass: String? = nil) -> HomeAccessory {
        HomeAccessory(id: "demo:sensor", name: "Sensor", kind: .sensor, backend: .demo, state: state, deviceClass: deviceClass)
    }

    private func accessory(_ kind: AccessoryKind, _ capabilities: Set<AccessoryCapability>, state: AccessoryState = AccessoryState()) -> HomeAccessory {
        HomeAccessory(id: "demo:\(kind.rawValue)", name: kind.rawValue, kind: kind, backend: .demo, capabilities: capabilities, state: state)
    }

    @Test func sensorsAndDoorbellsAreReadOnly() {
        #expect(!AccessoryPresentation.isControllable(sensor(AccessoryState(sensorValue: 21, sensorUnit: "°C"), deviceClass: "temperature")))
        #expect(!AccessoryPresentation.isControllable(sensor(AccessoryState(isActive: false), deviceClass: "motion")))
        #expect(!AccessoryPresentation.isControllable(sensor(AccessoryState(batteryLevel: 0.5))))
        #expect(!AccessoryPresentation.isControllable(accessory(.doorbell, [])))
    }

    @Test func everythingWithACommandIsATile() {
        #expect(AccessoryPresentation.isControllable(accessory(.light, [.power])))
        #expect(AccessoryPresentation.isControllable(accessory(.thermostat, [.targetTemperature, .hvacMode])))
        #expect(AccessoryPresentation.isControllable(accessory(.lock, [.lock])))
        #expect(AccessoryPresentation.isControllable(accessory(.securitySystem, [.power])))
        #expect(AccessoryPresentation.isControllable(accessory(.vacuum, [.power])))
        #expect(AccessoryPresentation.isControllable(accessory(.mediaPlayer, [.power, .playback])))
        // A garage door without a position still opens and closes.
        #expect(AccessoryPresentation.isControllable(accessory(.garageDoor, [], state: AccessoryState(doorState: .closed))))
    }

    @Test func numericReadingsAreShortAndRounded() {
        #expect(AccessoryPresentation.reading(for: sensor(AccessoryState(currentTemperature: 71.6, sensorValue: 71.6, sensorUnit: "°F"))).value == "72°")
        // Some sensors report only a value in degrees.
        #expect(AccessoryPresentation.reading(for: sensor(AccessoryState(sensorValue: 72.4, sensorUnit: "°"))).value == "72°")
        let humidity = AccessoryPresentation.reading(for: sensor(AccessoryState(humidity: 41.4, sensorValue: 41.4, sensorUnit: "%"), deviceClass: "humidity"))
        #expect(humidity.value == "41%")
        #expect(humidity.symbol == "humidity.fill")
        let carbonDioxide = AccessoryPresentation.reading(for: sensor(AccessoryState(sensorValue: 612, sensorUnit: "ppm"), deviceClass: "carbon_dioxide"))
        #expect(carbonDioxide.value == "612 ppm")
        #expect(!carbonDioxide.isAlert)
    }

    @Test func contactSensorsSayOpenOrClosed() {
        let closed = AccessoryPresentation.reading(for: sensor(AccessoryState(doorState: .closed, isActive: false), deviceClass: "door"))
        #expect(closed == SensorReading(symbol: "door.left.hand.closed", value: "Closed", isAlert: false))
        let open = AccessoryPresentation.reading(for: sensor(AccessoryState(doorState: .open, isActive: true), deviceClass: "window"))
        #expect(open == SensorReading(symbol: "window.vertical.open", value: "Open", isAlert: true))
    }

    @Test func binarySensorsUseTheirOwnWords() {
        #expect(AccessoryPresentation.reading(for: sensor(AccessoryState(isActive: true), deviceClass: "motion")).value == "Motion")
        #expect(AccessoryPresentation.reading(for: sensor(AccessoryState(isActive: false), deviceClass: "motion")).value == "Clear")
        #expect(AccessoryPresentation.reading(for: sensor(AccessoryState(isActive: true), deviceClass: "moisture")).value == "Leak")
        #expect(AccessoryPresentation.reading(for: sensor(AccessoryState(isActive: false), deviceClass: "moisture")).value == "Dry")
        #expect(AccessoryPresentation.reading(for: sensor(AccessoryState(isActive: true))).value == "Detected")
        // A smoke alarm's battery is not its reading.
        let smoke = AccessoryPresentation.reading(for: sensor(AccessoryState(isActive: false, batteryLevel: 0.9), deviceClass: "smoke"))
        #expect(smoke == SensorReading(symbol: "smoke.fill", value: "Clear", isAlert: false))
    }

    @Test func batteryOnlyAccessoriesShowTheirLevel() {
        let battery = AccessoryPresentation.reading(for: sensor(AccessoryState(batteryLevel: 0.82)))
        #expect(battery.value == "82%")
        #expect(battery.symbol == "battery.75percent")
        #expect(AccessoryPresentation.reading(for: sensor(AccessoryState(batteryLevel: 0.1))).isAlert)
    }

    @Test func unreachableAndDoorbells() {
        #expect(AccessoryPresentation.reading(for: sensor(AccessoryState(isActive: true, isReachable: false))).value == "No Response")
        #expect(AccessoryPresentation.reading(for: accessory(.doorbell, [], state: AccessoryState(isActive: false))).value == "Doorbell")
        let ringing = AccessoryPresentation.reading(for: accessory(.doorbell, [], state: AccessoryState(isActive: true)))
        #expect(ringing == SensorReading(symbol: "bell.fill", value: "Ringing", isAlert: true))
    }

    @Test func statusMatchesTheReading() {
        let motion = sensor(AccessoryState(isActive: true), deviceClass: "motion")
        #expect(AccessoryPresentation.status(for: motion) == "Motion")
        #expect(AccessoryPresentation.symbol(for: motion) == "figure.walk.motion")
    }

    @Test func summaryTemperatureCountsSensorsThatReportDegrees() {
        let degrees = sensor(AccessoryState(sensorValue: 72.4, sensorUnit: "°"))
        let thermostat = accessory(.thermostat, [.targetTemperature], state: AccessoryState(currentTemperature: 68))
        let chips = HomeSummaryChips.chips(for: [degrees, thermostat])
        #expect(chips.first { $0.id == "temperature" }?.text == "68–72°")
    }

    @Test func homeKitSensorsGetDeviceClasses() {
        #expect(HomeKitServiceMapper.deviceClass(forServiceType: HMServiceTypeMotionSensor) == "motion")
        #expect(HomeKitServiceMapper.deviceClass(forServiceType: HMServiceTypeLeakSensor) == "moisture")
        #expect(HomeKitServiceMapper.deviceClass(forServiceType: HMServiceTypeContactSensor) == "opening")
        #expect(HomeKitServiceMapper.deviceClass(forServiceType: HMServiceTypeLightbulb) == nil)
    }

    @Test func demoHomeHasReadingsInEveryRoomWithSensors() {
        let sensors = DemoSeedData.accessories.filter { !AccessoryPresentation.isControllable($0) }
        #expect(Set(sensors.compactMap(\.room)).isSuperset(of: ["Living Room", "Entryway", "Hallway", "Kitchen", "Bedroom", "Office"]))
    }
}
