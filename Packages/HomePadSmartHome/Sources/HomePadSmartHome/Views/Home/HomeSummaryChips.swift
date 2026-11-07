import HomePadCore
import HomePadUI
import SwiftUI

/// The status chips under the title, as in the Home app on HomeView:
/// temperature range, lights on, unlocked doors and open doors. They hug their
/// content, and `HomeOverviewRow` places them beside the room picker.
///
/// A chip stays while the home has that kind of accessory and says "Off",
/// "Locked" or "Closed" when there is nothing to count. Chips that came and went
/// added and removed the whole row, which moved everything below it each time
/// the first light went on or the last one off.
struct HomeSummaryChips: View {
    let accessories: [HomeAccessory]

    var body: some View {
        let chips = Self.chips(for: accessories)
        HStack(spacing: Theme.Spacing.s) {
            ForEach(chips) { chip in
                Label {
                    Text(chip.text).contentTransition(.numericText())
                } icon: {
                    // The bulb fills as the first light goes on, the shackle opens.
                    Image(systemName: chip.symbol).contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
                }
                    .foregroundStyle(chip.isActive ? Theme.tint(for: chip.kind) : Color.secondary)
                    .homeChip()
                    .accessibilityLabel(chip.accessibilityText)
            }
        }
        .animation(Theme.Motion.standard, value: chips)
    }

    struct Chip: Identifiable, Equatable {
        var id: String
        var symbol: String
        var text: String
        var kind: AccessoryKind
        /// Something to notice (lights on, a door open). Inactive chips are gray.
        var isActive: Bool
        var accessibilityText: String
    }

    static func chips(for accessories: [HomeAccessory]) -> [Chip] {
        var chips: [Chip] = []
        let temperatures = accessories.compactMap { accessory -> Double? in
            switch accessory.kind {
            case .thermostat: accessory.state.currentTemperature
            case .sensor: AccessoryPresentation.temperature(of: accessory)
            default: nil
            }
        }
        if let low = temperatures.min(), let high = temperatures.max() {
            let text = Int(low.rounded()) == Int(high.rounded()) ? "\(Int(low.rounded()))°" : "\(Int(low.rounded()))–\(Int(high.rounded()))°"
            chips.append(Chip(id: "temperature", symbol: "thermometer.medium", text: text, kind: .thermostat, isActive: true,
                              accessibilityText: "Temperature \(text)"))
        }
        let lights = accessories.filter { $0.kind == .light }
        if !lights.isEmpty {
            let on = lights.filter { $0.state.isOn == true }.count
            chips.append(Chip(id: "lights", symbol: on > 0 ? "lightbulb.fill" : "lightbulb", text: on > 0 ? "\(on)" : "Off",
                              kind: .light, isActive: on > 0, accessibilityText: on > 0 ? "\(on) lights on" : "Lights off"))
        }
        let locks = accessories.filter { $0.kind == .lock }
        if !locks.isEmpty {
            let unlocked = locks.filter { $0.state.lockState == .unlocked }.count
            chips.append(Chip(id: "locks", symbol: unlocked > 0 ? "lock.open.fill" : "lock.fill", text: unlocked > 0 ? "\(unlocked)" : "Locked",
                              kind: .lock, isActive: unlocked > 0, accessibilityText: unlocked > 0 ? "\(unlocked) unlocked" : "All locked"))
        }
        let doors = accessories.filter { $0.kind == .garageDoor }
        if !doors.isEmpty {
            let open = doors.filter { AccessoryPresentation.isOpen($0.state) }.count
            chips.append(Chip(id: "doors", symbol: open > 0 ? "door.garage.open" : "door.garage.closed", text: open > 0 ? "\(open)" : "Closed",
                              kind: .garageDoor, isActive: open > 0, accessibilityText: open > 0 ? "\(open) doors open" : "Doors closed"))
        }
        return chips
    }
}
