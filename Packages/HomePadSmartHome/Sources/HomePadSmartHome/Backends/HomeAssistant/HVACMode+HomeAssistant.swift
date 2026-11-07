import Foundation
import HomePadCore

extension HVACMode {
    /// Maps Home Assistant's `hvac_mode` values. `heat_cool` and `auto` both become `.auto`.
    init?(homeAssistant value: String) {
        switch value {
        case "off": self = .off
        case "heat": self = .heat
        case "cool": self = .cool
        case "heat_cool", "auto": self = .auto
        case "fan_only": self = .fanOnly
        case "dry": self = .dry
        default: return nil
        }
    }

    /// The Home Assistant value, preferring `heat_cool` for `.auto` when the device offers it.
    func homeAssistantValue(available: [String]) -> String {
        switch self {
        case .off: "off"
        case .heat: "heat"
        case .cool: "cool"
        case .auto: available.contains("heat_cool") || !available.contains("auto") ? "heat_cool" : "auto"
        case .fanOnly: "fan_only"
        case .dry: "dry"
        }
    }
}
