import HomePadCore
import HomePadUI
import SwiftUI

/// Sensors and other accessories with nothing to control, as one row of small
/// glass chips, a symbol and a value each ("72°", "41%", "Closed", "Motion").
/// Apple Home shows a room's readings like this in its header instead of
/// giving each sensor a tile. Tapping a chip opens the sensor's details.
struct SensorStrip: View {
    let sensors: [HomeAccessory]
    /// Adds each sensor's name, where the room around it does not say which one it is (Favorites).
    var showsNames = false
    let onOpen: (HomeAccessory.ID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(sensors) { sensor in
                    SensorChip(accessory: sensor, showsName: showsNames) { onOpen(sensor.id) }
                }
            }
        }
        .scrollClipDisabled()
    }
}

/// One reading in a `SensorStrip`.
struct SensorChip: View {
    let accessory: HomeAccessory
    let showsName: Bool
    let onOpen: () -> Void

    var body: some View {
        let reading = AccessoryPresentation.reading(for: accessory)
        Button(action: onOpen) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: reading.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(reading.isAlert ? Color.orange : Color.secondary)
                if showsName {
                    Text(accessory.name).foregroundStyle(.secondary)
                }
                Text(reading.value)
                    .foregroundStyle(reading.isAlert ? Color.orange : Color.primary)
                    .contentTransition(.numericText())
            }
            .homeChip(isInteractive: true)
        }
        .buttonStyle(.plain)
        .opacity(accessory.state.isReachable ? 1 : 0.55)
        .contextMenu { AccessoryMenuItems(accessory: accessory, onOpen: onOpen) }
        .accessibilityLabel("\(accessory.name), \(reading.value)")
        .accessibilityHint("Shows details")
        .animation(Theme.Motion.standard, value: reading)
    }
}
