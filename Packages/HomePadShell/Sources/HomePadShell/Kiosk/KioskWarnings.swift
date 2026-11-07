import HomePadCore
import HomePadUI
import SwiftUI

/// Persistent notices about the iPad itself: running on battery, or running hot.
struct KioskWarnings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(KioskController.self) private var kiosk

    var body: some View {
        let health = kiosk.health
        VStack(spacing: Theme.Spacing.s) {
            if health.isNotCharging && settings[ShellSettings.chargingWarning] {
                StatusBanner(chargingMessage(health.batteryLevel), systemImage: "powerplug", tint: .orange)
            }
            if health.isOverheating {
                StatusBanner("HomePad is warm, so the screen is dimmer for now", systemImage: "thermometer.high", tint: .red)
            }
        }
        .transition(.opacity)
        .animation(Theme.Motion.standard, value: health.power)
        .animation(Theme.Motion.standard, value: health.isOverheating)
    }

    private func chargingMessage(_ level: Double?) -> String {
        guard let level else { return "Not charging. Plug in to stay always on" }
        return "Not charging, \(Int((level * 100).rounded()))% left. Plug in to stay always on"
    }
}
