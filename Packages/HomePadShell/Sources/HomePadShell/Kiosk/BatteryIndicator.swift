import HomePadUI
import SwiftUI

/// The battery's charge in the top right corner, where the iPadOS status bar
/// shows it, since HomePad hides the status bar. Small and above the people
/// button, on every screen but the sleeping one. Hidden where the battery
/// level is unknown (the simulator).
struct BatteryIndicator: View {
    let health: DeviceHealthMonitor

    var body: some View {
        if let level = health.batteryLevel {
            let reading = BatteryReading(level: level, power: health.power)
            HStack(spacing: 3) {
                Text(reading.percentText)
                    .monospacedDigit()
                Image(systemName: reading.symbolName)
                    .foregroundStyle(reading.isLow ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .topPillBackground()
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.accessibilityLabel)
        }
    }
}

/// What the battery indicator shows for a charge and power state.
struct BatteryReading: Equatable {
    var level: Double
    var power: DeviceHealthMonitor.Power

    /// "82%".
    var percentText: String { "\(percent)%" }

    var percent: Int { Int((min(max(level, 0), 1) * 100).rounded()) }

    var isCharging: Bool { power == .charging || power == .full }

    /// Low enough to need a charger soon, and not on one.
    var isLow: Bool { !isCharging && percent <= 20 }

    /// The battery glyph closest to the charge, with a bolt while plugged in.
    var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    var accessibilityLabel: String {
        "Battery \(percent) percent" + (isCharging ? ", charging" : "")
    }
}
