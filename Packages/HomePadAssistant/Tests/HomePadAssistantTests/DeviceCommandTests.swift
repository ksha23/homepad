import Foundation
import HomePadCore
import Testing
@testable import HomePadAssistant

@MainActor
@Suite struct DeviceCommandTests {
    let home = DemoSmartHomeService()

    func accessory(_ id: String) throws -> HomeAccessory {
        try #require(home.accessories.first { $0.id == id })
    }

    func map(_ action: DeviceAction, value: Double? = nil, color: String? = nil, mode: String? = nil, on id: String) throws -> Result<AccessoryCommand, DeviceCommandMapper.MappingError> {
        DeviceCommandMapper.command(for: DeviceInstruction(action: action, value: value, color: color, mode: mode), on: try accessory(id))
    }

    // MARK: Mapping

    @Test func turnOffMeansDifferentThingsPerKind() throws {
        #expect(try map(.turnOff, on: "demo:light.kitchen") == .success(.setPower(false)))
        #expect(try map(.turnOff, on: "demo:climate.living") == .success(.setHVACMode(.off)))
        #expect(try map(.turnOff, on: "demo:fan.office") == .success(.setPower(false)))
        #expect(try map(.turnOff, on: "demo:lock.front") == .failure(.unsupported("Front Door", .turnOff)))
    }

    @Test func brightnessAcceptsPercentOrFraction() throws {
        #expect(try map(.setBrightness, value: 40, on: "demo:light.kitchen") == .success(.setBrightness(0.4)))
        #expect(try map(.setBrightness, value: 0.25, on: "demo:light.kitchen") == .success(.setBrightness(0.25)))
        #expect(try map(.setBrightness, value: 0, on: "demo:light.kitchen") == .success(.setPower(false)))
        // The entryway light only switches on and off.
        #expect(try map(.setBrightness, value: 50, on: "demo:light.entry") == .failure(.unsupported("Entryway Lights", .setBrightness)))
        #expect(try map(.setBrightness, on: "demo:light.kitchen") == .failure(.missingValue(.setBrightness)))
    }

    @Test func dimIsRelativeToCurrentBrightness() throws {
        // Kitchen lights start at 70%.
        guard case .success(.setBrightness(let dimmed)) = try map(.dim, on: "demo:light.kitchen") else {
            Issue.record("Expected a brightness command")
            return
        }
        #expect(abs(dimmed - 0.45) < 0.0001)
        #expect(try map(.brighten, value: 50, on: "demo:light.kitchen") == .success(.setBrightness(1)))
    }

    @Test func colorsAndWhites() throws {
        let color = HomeAccessory(id: "x", name: "Strip", kind: .light, backend: .demo, capabilities: [.power, .color])
        #expect(DeviceCommandMapper.command(for: DeviceInstruction(action: .setColor, color: "Blue"), on: color) == .success(.setHueSaturation(hue: 230, saturation: 1)))
        #expect(DeviceCommandMapper.command(for: DeviceInstruction(action: .setColor, color: "plaid"), on: color) == .failure(.unknownColor("plaid")))
        #expect(try map(.setColor, color: "warm white", on: "demo:light.kitchen") == .success(.setColorTemperature(kelvin: 2700)))
        #expect(try map(.setColorTemperature, value: 250, on: "demo:light.kitchen") == .success(.setColorTemperature(kelvin: 4000)))
    }

    @Test func thermostatTemperatureAndModes() throws {
        #expect(try map(.setTemperature, value: 68, on: "demo:climate.living") == .success(.setTargetTemperature(68)))
        #expect(try map(.setMode, mode: "heating", on: "demo:climate.living") == .success(.setHVACMode(.heat)))
        #expect(try map(.setMode, mode: "fan_only", on: "demo:climate.living") == .success(.setHVACMode(.fanOnly)))
        #expect(try map(.turnOn, on: "demo:climate.living") == .success(.setHVACMode(.auto)))
        #expect(try map(.setTemperature, value: 68, on: "demo:light.kitchen") == .failure(.unsupported("Kitchen Lights", .setTemperature)))
    }

    @Test func openingALockUnlocksIt() throws {
        #expect(try map(.open, on: "demo:lock.front") == .success(.unlock))
        #expect(try map(.close, on: "demo:lock.front") == .success(.lock))
        #expect(try map(.open, on: "demo:cover.living") == .success(.open))
        #expect(try map(.setPosition, value: 30, on: "demo:cover.living") == .success(.setPosition(0.3)))
    }

    @Test func mediaPlayersPauseOnTurnOff() {
        let speaker = HomeAccessory(id: "s", name: "Kitchen HomePod", kind: .mediaPlayer, backend: .demo, capabilities: [.volume, .playback])
        #expect(DeviceCommandMapper.command(for: DeviceInstruction(action: .turnOff), on: speaker) == .success(.pause))
        #expect(DeviceCommandMapper.command(for: DeviceInstruction(action: .setVolume, value: 30), on: speaker) == .success(.setVolume(0.3)))
        #expect(DeviceCommandMapper.command(for: DeviceInstruction(action: .nextTrack), on: speaker) == .success(.nextTrack))
    }

    // MARK: Target resolution

    @Test func groupStandsInForItsMembers() {
        let members = ["Floor Lamp", "Reading Lamp"].map { name in
            HomeAccessory(id: "hk:\(name)", name: name, room: "Living Room", kind: .light, backend: .homeKit, groupID: "hk:lamps")
        }
        let group = HomeAccessory(id: "hk:lamps", name: "Living Room Lamps", room: "Living Room", kind: .light,
                                  backend: .homeKit, memberIDs: members.map(\.id))
        let all = members + [group]
        let names = { (device: String?, room: String?) in
            DeviceTargetResolver.resolve(device: device, room: room, in: all).map(\.name).sorted()
        }
        #expect(names("lights", "Living Room") == ["Living Room Lamps"])
        #expect(names("living room lamps", nil) == ["Living Room Lamps"])
        #expect(names("reading lamp", nil) == ["Reading Lamp"])
    }

    @Test func resolvesNamesRoomsAndKinds() {
        let all = home.accessories
        let names = { (device: String?, room: String?) in
            DeviceTargetResolver.resolve(device: device, room: room, in: all).map(\.name).sorted()
        }
        #expect(names("kitchen lights", nil) == ["Kitchen Lights"])
        #expect(names("living room lights", nil) == ["Living Room Lamp"])
        #expect(names("lights", nil) == ["Entryway Lights", "Kitchen Lights", "Living Room Lamp"])
        #expect(names("the fan", nil) == ["Ceiling Fan"])
        #expect(names("Front Door", nil) == ["Front Door"])
        #expect(names("everything", "office") == ["Ceiling Fan"])
        #expect(names(nil, "Living Room") == ["Living Room Lamp", "Shades", "Thermostat"])
        #expect(names("blinds", nil) == ["Shades"])
        #expect(names("garage", nil) == [])
    }

    // MARK: Execution

    @Test func runsMixedMultiDeviceRequestInOneCall() async {
        var asked: [String] = []
        let executor = DeviceControlExecutor(smartHome: home) { question in
            asked.append(question)
            return true
        }
        let report = await executor.run([
            .init(device: "lights", room: nil, instruction: DeviceInstruction(action: .turnOff)),
            .init(device: "thermostat", room: nil, instruction: DeviceInstruction(action: .setTemperature, value: 68)),
            .init(device: "shades", room: "living room", instruction: DeviceInstruction(action: .setPosition, value: 50)),
        ])
        #expect(asked.isEmpty)
        #expect(report.done.count == 5)
        #expect(report.skipped.isEmpty)
        #expect(home.accessories.filter { $0.kind == .light }.allSatisfy { $0.state.isOn == false })
        #expect(home.accessory("demo:climate.living")?.state.targetTemperature == 68)
        #expect(home.accessory("demo:cover.living")?.state.position == 0.5)
    }

    @Test func asksBeforeUnlockingAndRespectsNo() async {
        var asked: [String] = []
        let executor = DeviceControlExecutor(smartHome: home) { question in
            asked.append(question)
            return false
        }
        let report = await executor.run([
            .init(device: "front door", room: nil, instruction: DeviceInstruction(action: .unlock)),
            .init(device: "kitchen lights", room: nil, instruction: DeviceInstruction(action: .turnOn)),
        ])
        #expect(asked == ["Unlock the Front Door?"])
        #expect(report.declined == ["Front Door"])
        #expect(home.accessory("demo:lock.front")?.state.lockState == .locked)
        #expect(report.done == ["Kitchen Lights turned on"])
    }

    @Test func reportsUnknownDevicesAndUnsupportedActions() async {
        let executor = DeviceControlExecutor(smartHome: home) { _ in true }
        let report = await executor.run([
            .init(device: "hot tub", room: nil, instruction: DeviceInstruction(action: .turnOn)),
            .init(device: "front door", room: nil, instruction: DeviceInstruction(action: .setBrightness, value: 50)),
        ])
        #expect(report.done.isEmpty)
        #expect(report.skipped == ["No device matches \"hot tub\".", "Front Door cannot set brightness."])
    }

    @Test func entrancesNeedConfirmationButBlindsDoNot() throws {
        let garage = HomeAccessory(id: "g", name: "Garage", kind: .garageDoor, backend: .demo)
        let gate = HomeAccessory(id: "c", name: "Driveway Gate", kind: .cover, backend: .demo)
        let alarm = HomeAccessory(id: "a", name: "Alarm", kind: .securitySystem, backend: .demo)
        #expect(SensitiveActionPolicy.requiresConfirmation(.open, on: garage))
        #expect(SensitiveActionPolicy.requiresConfirmation(.setPosition(0.5), on: gate))
        #expect(SensitiveActionPolicy.requiresConfirmation(.setPower(false), on: alarm))
        #expect(!SensitiveActionPolicy.requiresConfirmation(.open, on: try accessory("demo:cover.living")))
        #expect(!SensitiveActionPolicy.requiresConfirmation(.lock, on: try accessory("demo:lock.front")))
        #expect(SensitiveActionPolicy.question(forToolNamed: "ha_unlock_door") == "Allow ha unlock door?")
        #expect(SensitiveActionPolicy.question(forToolNamed: "get_recipe") == nil)
    }
}
