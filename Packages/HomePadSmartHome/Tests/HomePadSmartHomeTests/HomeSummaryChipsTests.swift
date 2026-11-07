import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// Turning on the first light or off the last one added or removed the whole
/// chip row, which moved the Home app's content each time.
@Suite struct HomeSummaryChipsTests {
    private func light(_ id: String, on: Bool) -> HomeAccessory {
        HomeAccessory(id: id, name: id, kind: .light, backend: .demo, capabilities: [.power], state: AccessoryState(isOn: on))
    }

    @Test func chipsStayWhenEverythingIsOff() {
        let off = HomeSummaryChips.chips(for: [light("demo:a", on: false), light("demo:b", on: false)])
        let on = HomeSummaryChips.chips(for: [light("demo:a", on: true), light("demo:b", on: false)])
        #expect(off.map(\.id) == ["lights"])
        #expect(on.map(\.id) == off.map(\.id))
        #expect(off[0].text == "Off" && off[0].isActive == false)
        #expect(on[0].text == "1" && on[0].isActive)
    }

    @Test func noChipForKindsTheHomeDoesNotHave() {
        let fan = HomeAccessory(id: "demo:f", name: "Fan", kind: .fan, backend: .demo, capabilities: [.power], state: AccessoryState(isOn: true))
        #expect(HomeSummaryChips.chips(for: [fan]).isEmpty)
    }
}
