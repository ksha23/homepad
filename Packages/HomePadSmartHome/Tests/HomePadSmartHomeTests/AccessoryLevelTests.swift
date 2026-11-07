import Foundation
import HomeKit
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// Brightness and blind position: which accessories get a level from each
/// backend, what pressing and dragging on a tile sets, and the command it sends.
@Suite("Accessory levels")
struct AccessoryLevelTests {
    let states: [String: HAState]
    let accessories: [String: HomeAccessory]

    init() throws {
        let loaded = try Fixtures.states("rest_states_levels")
        states = Dictionary(uniqueKeysWithValues: loaded.map { ($0.entityID, $0) })
        let mapped = HAStateMapper.map(loaded, context: HAStateMapper.Context())
        accessories = Dictionary(uniqueKeysWithValues: mapped.accessories.map { (BackendID.localID(of: $0.id), $0) })
    }

    private func accessory(_ entityID: String) throws -> HomeAccessory {
        try #require(accessories[entityID])
    }

    @Test func dimmableLightsKeepBrightnessWhileOff() throws {
        let hue = try accessory("light.hue_color_lamp_1")
        #expect(hue.capabilities == [.power, .brightness, .colorTemperature, .color])
        #expect(hue.state.brightness == nil, "Home Assistant sends no brightness while a light is off")
        #expect(AccessoryPresentation.level(of: hue) == 0)
        let desk = try accessory("light.desk_lamp")
        #expect(desk.capabilities == [.power, .brightness])
        #expect(AccessoryPresentation.level(of: desk) == 0)
    }

    @Test func dimmerOnShowsItsBrightness() throws {
        let ceiling = try accessory("light.bedroom_ceiling_light")
        #expect(ceiling.capabilities == [.power, .brightness])
        #expect(abs((AccessoryPresentation.level(of: ceiling) ?? 0) - 0.8) < 0.0001)
        #expect(AccessoryPresentation.levelCommand(0.5, for: ceiling) == .setBrightness(0.5))
    }

    @Test func onOffLightHasNoLevel() throws {
        let table = try accessory("light.table_lamp")
        #expect(table.capabilities == [.power])
        #expect(AccessoryPresentation.level(of: table) == nil)
    }

    @Test func blindsWithPosition() throws {
        let blinds = try accessory("cover.bedroom_blinds")
        #expect(blinds.kind == .cover)
        #expect(blinds.capabilities == [.position])
        #expect(AccessoryPresentation.level(of: blinds) == 0.35)
        #expect(AccessoryPresentation.levelCommand(0.8, for: blinds) == .setPosition(0.8))
        #expect(AccessoryPresentation.primaryCommand(for: blinds) == .close, "a tap closes open blinds")
        let call = try HACommandMapper.serviceCall(for: .setPosition(0.8), entityID: "cover.bedroom_blinds", state: states["cover.bedroom_blinds"])
        #expect(call.service == "set_cover_position")
        #expect(call.data == ["position": 80])
    }

    @Test func tiltOnlyBlindsUseTheirTilt() throws {
        let venetian = try accessory("cover.office_venetian")
        #expect(venetian.capabilities == [.position])
        #expect(venetian.state.position == 0.7)
        let call = try HACommandMapper.serviceCall(for: .setPosition(0.25), entityID: "cover.office_venetian", state: states["cover.office_venetian"])
        #expect(call.service == "set_cover_tilt_position")
        #expect(call.data == ["tilt_position": 25])
    }

    @Test func openCloseOnlyShadeHasNoLevel() throws {
        let shade = try accessory("cover.kitchen_shade")
        #expect(shade.capabilities.isEmpty)
        #expect(AccessoryPresentation.level(of: shade) == nil)
        #expect(AccessoryPresentation.primaryCommand(for: shade) == .open, "a tap opens closed blinds")
    }

    @Test func homeKitCapabilitiesComeFromCharacteristicTypes() {
        let light = HomeKitServiceMapper.capabilities(kind: .light, characteristicTypes: [
            HMCharacteristicTypePowerState, HMCharacteristicTypeBrightness, HMCharacteristicTypeHue, HMCharacteristicTypeSaturation,
        ])
        #expect(light == [.power, .brightness, .color])
        let blinds = HomeKitServiceMapper.capabilities(kind: .cover, characteristicTypes: [
            HMCharacteristicTypeCurrentPosition, HMCharacteristicTypeTargetPosition, HMCharacteristicTypePositionState,
        ])
        #expect(blinds == [.position])
        let speed = HomeKitServiceMapper.capabilities(kind: .fan, characteristicTypes: [HMCharacteristicTypeActive, HMCharacteristicTypeRotationSpeed])
        #expect(speed == [.power, .brightness])
    }

    @Test func groupsAndFansFollowTheirCapabilities() {
        let dimmable = HomeAccessory(id: "demo:a", name: "A", kind: .light, backend: .demo, capabilities: [.power, .brightness],
                                     state: AccessoryState(isOn: true, brightness: 0.6))
        let plain = HomeAccessory(id: "demo:b", name: "B", kind: .light, backend: .demo, capabilities: [.power],
                                  state: AccessoryState(isOn: true))
        let mixed = AccessoryGroups.group(id: "demo:g", name: "G", backend: .demo, members: [dimmable, plain])
        #expect(mixed.flatMap(AccessoryPresentation.level(of:)) == nil, "a group dims only when every member can")
        let lamps = AccessoryGroups.group(id: "demo:h", name: "H", backend: .demo, members: [dimmable, dimmable])
        #expect(lamps.flatMap(AccessoryPresentation.level(of:)) == 0.6)
        let fan = HomeAccessory(id: "demo:f", name: "Fan", kind: .fan, backend: .demo, capabilities: [.power, .brightness],
                                state: AccessoryState(isOn: false))
        #expect(AccessoryPresentation.level(of: fan) == 0)
        #expect(AccessoryPresentation.levelCommand(0.3, for: fan) == .setBrightness(0.3))
    }

    @Test func dragAcrossTheTileCoversTheRange() {
        #expect(LevelDragMath.level(from: 0.5, translation: 100, width: 400) == 0.75)
        #expect(LevelDragMath.level(from: 0.5, translation: -400, width: 400) == 0)
        #expect(LevelDragMath.level(from: 0.9, translation: 200, width: 400) == 1)
        #expect(LevelDragMath.level(from: 0, translation: 80, width: 40) == 0.5, "narrow tiles use the minimum track")
        #expect(LevelDragMath.percent(0.456) == 46)
    }
}
