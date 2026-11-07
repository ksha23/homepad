import HomePadCore
import HomePadUI
import SwiftUI

/// The color behind a detail screen. Thermostats follow their mode, as on HomeView.
enum DetailTint {
    static func color(for accessory: HomeAccessory) -> Color {
        guard accessory.kind == .thermostat else { return Theme.tint(for: accessory.kind) }
        switch accessory.state.hvacMode {
        case .cool: return .blue
        case .heat: return .orange
        case .auto: return .teal
        default: return .gray
        }
    }

    /// How strongly a detail's color covers its screen. A thermostat fills the
    /// whole screen with its mode's color, as HomeView's does, except when it
    /// is off. Everything else glows from the top over the page. At night the fill
    /// stays dim, so the red numerals still stand out on it.
    static func fillOpacity(for accessory: HomeAccessory, isNight: Bool) -> Double? {
        guard accessory.kind == .thermostat else { return nil }
        guard let mode = accessory.state.hvacMode, mode != .off else { return 0.25 }
        return isNight ? 0.3 : 1
    }
}
