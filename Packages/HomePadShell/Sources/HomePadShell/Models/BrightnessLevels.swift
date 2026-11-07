import Foundation
import HomePadCore

/// Screen brightness (0 to 1) for each display condition.
struct BrightnessLevels: Codable, Equatable, Sendable {
    var active: Double = 0.8
    var ambient: Double = 0.55
    var dimmed: Double = 0.2
    var night: Double = 0.03
    var sleeping: Double = 0

    static let standard = BrightnessLevels()

    subscript(condition: DisplayCondition) -> Double {
        get {
            switch condition {
            case .active: active
            case .ambient: ambient
            case .dimmed: dimmed
            case .night: night
            case .sleeping: sleeping
            }
        }
        set {
            switch condition {
            case .active: active = newValue
            case .ambient: ambient = newValue
            case .dimmed: dimmed = newValue
            case .night: night = newValue
            case .sleeping: sleeping = newValue
            }
        }
    }

    /// The brightness to ramp to for a kiosk state.
    /// - Parameters:
    ///   - state: Current kiosk state.
    ///   - ambientLight: Room light from the presence sensors, if known.
    ///   - adaptToRoomLight: Scale with room light (darker rooms get a dimmer screen).
    ///   - cap: Upper limit, lowered when the iPad runs hot.
    ///   - ambientLux: Smoothed room light in lux, if a camera can measure it.
    func target(for state: KioskState, ambientLight: AmbientLight?, ambientLux: Double? = nil,
                adaptToRoomLight: Bool, cap: Double = 1) -> Double {
        var level = self[state.condition]
        if adaptToRoomLight, let ambientLux, state.condition != .night, state.condition != .sleeping {
            // Continuous auto-brightness like iOS: follow the room on a log curve,
            // keeping each condition's level relative to Active (ambient a bit
            // dimmer, dimmed much dimmer).
            let relative = active > 0 ? self[state.condition] / active : 1
            level = Self.autoBrightness(lux: ambientLux) * relative
        } else if adaptToRoomLight, state.condition != .sleeping, let ambientLight {
            level *= Self.roomLightFactor(ambientLight)
        }
        if state.condition == .night && state.isInteracting {
            // Someone is using the screen at night: a little brighter, still gentle.
            level = min(1, level + 0.12)
        }
        return min(max(level, 0), cap, 1)
    }

    /// Screen brightness for a room's light on a log curve, close to iOS
    /// auto-brightness: about 6 percent in the dark, 30 at 10 lux (a dim lamp),
    /// 53 at 100 lux (a lit living room), 77 at 1,000 lux and full in daylight.
    static func autoBrightness(lux: Double) -> Double {
        let x = log10(max(lux, 0) + 1)
        return min(1, max(0.06, 0.06 + 0.235 * x))
    }

    static func roomLightFactor(_ light: AmbientLight) -> Double {
        switch light {
        case .dark: 0.6
        case .dim: 0.8
        case .normal: 1
        case .bright: 1.25
        }
    }
}
