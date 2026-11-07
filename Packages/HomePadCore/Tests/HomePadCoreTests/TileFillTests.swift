import Testing
@testable import HomePadCore

/// Home tiles (the app, its widgets and the Home face) fill to an accessory's level.
@Suite struct TileFillTests {
    private func accessory(_ kind: AccessoryKind, _ capabilities: Set<AccessoryCapability>, _ state: AccessoryState) -> HomeAccessory {
        HomeAccessory(id: "a", name: "A", kind: kind, backend: .demo, capabilities: capabilities, state: state)
    }

    @Test func dimmersFillToTheirBrightness() {
        let lamp = accessory(.light, [.power, .brightness], AccessoryState(isOn: true, brightness: 0.4))
        #expect(lamp.tileFill(isOn: true) == 0.4)
        #expect(lamp.tileFill(isOn: false) == 0)
    }

    @Test func lowLevelsKeepASliver() {
        let lamp = accessory(.light, [.power, .brightness], AccessoryState(isOn: true, brightness: 0.01))
        #expect(lamp.tileFill(isOn: true) == 0.08)
    }

    @Test func blindsFillToTheirPosition() {
        let blind = accessory(.cover, [.position], AccessoryState(position: 0.7))
        #expect(blind.tileFill(isOn: true) == 0.7)
    }

    @Test func accessoriesWithoutALevelFillWhenOn() {
        let plug = accessory(.switchOutlet, [.power], AccessoryState(isOn: true))
        #expect(plug.tileFill(isOn: true) == 1)
        let switchedLight = accessory(.light, [.power], AccessoryState(isOn: true, brightness: 0.3))
        #expect(switchedLight.tileFill(isOn: true) == 1)
    }
}
