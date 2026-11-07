import HomePadCore
import HomePadUI
import SwiftUI

/// "2 minutes ago", redrawn once a minute and never more often.
struct LastSeenText: View {
    let date: Date

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(FindMyWording.lastSeen(date, now: context.date))
        }
    }
}

/// A battery symbol filled to the level, with the percentage.
struct FindMyBatteryLabel: View {
    let device: TrackedDevice

    var body: some View {
        if let level = device.batteryLevel {
            Label {
                Text(level.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
            } icon: {
                Image(systemName: symbol(for: level))
                    .foregroundStyle(level <= 0.2 && device.isCharging != true ? .red : .secondary)
            }
            .accessibilityLabel(FindMyWording.battery(device).map { "Battery \($0)" } ?? "")
        }
    }

    private func symbol(for level: Double) -> String {
        if device.isCharging == true { return "battery.100percent.bolt" }
        switch level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
