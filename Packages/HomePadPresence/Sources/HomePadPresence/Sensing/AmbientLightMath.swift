import Foundation
import HomePadCore

/// Turns camera exposure metadata into an approximate lux value and a room
/// lighting bucket for night mode and brightness.
enum AmbientLightMath {
    /// Approximate scene illuminance from the EXIF APEX BrightnessValue (Bv).
    ///
    /// An incident light meter reads lux = 2.5 * 2^EV, with EV at ISO 100.
    /// APEX defines EV = Bv + Sv, and Sv is 5 at ISO 100, so lux is
    /// 2.5 * 2^(Bv + 5), about 80 * 2^Bv. Reading Bv as if it were EV made
    /// every room 32 times darker than it was: in weeks of traces neither iPad
    /// ever read a room as normally lit.
    static func lux(brightnessValue: Double) -> Double {
        2.5 * pow(2, brightnessValue + 5)
    }

    /// Rough lux from ARKit's `ambientIntensity` (1000 means neutral indoor light).
    static func lux(arkitAmbientIntensity intensity: Double) -> Double {
        max(0, intensity) / 4
    }

    /// The room's light from one frame, or nil when this frame cannot tell.
    ///
    /// Two kinds of frame cannot:
    /// - Every depth scan frame. The TrueDepth capture session's brightness
    ///   value stays at the camera's starting value, which reads as 283 lux in
    ///   a dark room as well as a lit one. Taken as a reading, it sent a dark
    ///   room's scan back to the front camera, which read the dark and sent
    ///   it back to depth, so neither stayed long enough to see anyone.
    /// - The first frame of each session. It carries the exposure the camera
    ///   started with, before auto exposure settles: 283 lux in a dim room
    ///   whose next frames read 37.
    static func roomLux(
        brightnessValue: Double?, arkitAmbientIntensity: Double?,
        backend: BackendKind, isFirstFrame: Bool
    ) -> Double? {
        guard backend != .depthScan, !isFirstFrame else { return nil }
        return brightnessValue.map(lux(brightnessValue:)) ?? arkitAmbientIntensity.map(lux(arkitAmbientIntensity:))
    }

    /// Bucket boundaries in lux: dark, dim, normal, bright.
    static let darkBelow = 5.0
    static let dimBelow = 50.0
    static let brightAbove = 1000.0

    static func level(lux: Double) -> AmbientLight {
        switch lux {
        case ..<darkBelow: .dark
        case ..<dimBelow: .dim
        case ..<brightAbove: .normal
        default: .bright
        }
    }

    /// Like `level(lux:)` but only leaves `current` once lux is clearly past the
    /// boundary (a factor of `ratio`), so a lamp flicker does not toggle night mode.
    static func level(lux: Double, current: AmbientLight?, ratio: Double = 1.4) -> AmbientLight {
        let candidate = level(lux: lux)
        guard let current, candidate != current else { return candidate }
        let brighter = rank(candidate) > rank(current)
        let check = brighter ? lux / ratio : lux * ratio
        return level(lux: check) == candidate ? candidate : current
    }

    private static func rank(_ light: AmbientLight) -> Int {
        switch light {
        case .dark: 0
        case .dim: 1
        case .normal: 2
        case .bright: 3
        }
    }

    /// Exponential smoothing in the log domain over time. `timeConstant` is how
    /// many seconds the estimate takes to move about two thirds of the way to a
    /// new light level, so one noisy frame barely moves it.
    static func smoothed(lux: Double, previous: Double?, elapsed: TimeInterval, timeConstant: TimeInterval) -> Double {
        guard let previous, previous >= 0 else { return max(lux, 0) }
        let alpha = 1 - exp(-max(elapsed, 0) / max(timeConstant, 0.001))
        let current = log10(max(lux, 0) + 1)
        let last = log10(previous + 1)
        return pow(10, last + (current - last) * alpha) - 1
    }

    /// Seconds to settle on a new light level. A face close to the camera fills
    /// the frame and reflects the screen's own light, so its readings say more
    /// about the screen than the room and move the estimate only slowly.
    static func timeConstant(for proximity: ProximityLevel) -> TimeInterval {
        switch proximity {
        case .near: 45
        case .mid: 20
        case .far, .nobody: 8
        }
    }
}
