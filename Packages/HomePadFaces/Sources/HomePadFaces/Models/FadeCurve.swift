import Foundation
import HomePadUI

/// Sundial math for the Fade face: which numerals are lit, how bright the
/// day is, and where the light comes from.
enum FadeCurve {
    static let sunrise = 6.0
    static let sunset = 19.0

    /// Daylight from 0 (night) to 1 (midday), as a smooth arc between sunrise and sunset.
    static func daylight(hour: Double) -> Double {
        guard hour > sunrise, hour < sunset else { return 0 }
        let progress = (hour - sunrise) / (sunset - sunrise)
        return sin(progress * .pi)
    }

    /// Opacity of a numeral. Numerals near the hour hand are lit like the
    /// shadow on a sundial, and the rest fade away. Brighter in daylight.
    static func opacity(numeral: Int, hourPosition: Double, daylight: Double) -> Double {
        let distance = ClockMath.hourDistance(numeral, to: hourPosition)
        let window = smoothstep(from: 4.5, to: 1.5, distance)
        let level = 0.4 + 0.6 * daylight
        return max(0.07, window * level)
    }

    /// Light direction in radians counterclockwise from the right: from the
    /// left at sunrise, overhead at midday, from the right at sunset, and from
    /// above at night.
    static func lightAngle(hour: Double) -> Double {
        guard hour >= sunrise, hour <= sunset else { return .pi / 2 }
        let progress = (hour - sunrise) / (sunset - sunrise)
        return .pi * (1 - progress)
    }

    /// Hours since midnight as a fraction, for example 13.5 at 1:30 PM.
    static func hourOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    /// Hermite smoothstep that also works when `from` is greater than `to`.
    static func smoothstep(from edge0: Double, to edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
