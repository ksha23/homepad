import CoreGraphics
import Foundation

/// Pure clock math shared by every analog clock in HomePad.
public enum ClockMath {
    /// Hand angles in degrees clockwise from 12 o'clock.
    public struct HandAngles: Equatable, Sendable {
        public var hour: Double
        public var minute: Double
        public var second: Double

        public init(hour: Double, minute: Double, second: Double) {
            self.hour = hour
            self.minute = minute
            self.second = second
        }
    }

    /// The hand angles for `date` on a clock that follows `calendar`'s time zone.
    /// The hour and minute hands sweep smoothly. The second hand ticks.
    public static func angles(for date: Date, calendar: Calendar = .current) -> HandAngles {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let second = Double(parts.second ?? 0) + Double(parts.nanosecond ?? 0) / 1_000_000_000
        let minute = Double(parts.minute ?? 0) + second / 60
        let hour = Double((parts.hour ?? 0) % 12) + minute / 60
        return HandAngles(hour: hour / 12 * 360, minute: minute / 60 * 360, second: second.rounded(.down) / 60 * 360)
    }

    /// The point for a numeral or tick at `fraction` of the way around a dial
    /// (0 is 12 o'clock), at `radius` from `center`.
    public static func point(fraction: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = fraction * 2 * .pi - .pi / 2
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }

    /// The point where the line from the center of `rect` toward `fraction`
    /// of the way around a dial (0 is 12 o'clock) meets the edge of `rect`
    /// with its corners rounded by `cornerRadius`. Numerals placed this way
    /// follow a rounded screen, like a full-screen Apple Watch or HomeView dial.
    public static func point(fraction: Double, onRoundedRect rect: CGRect, cornerRadius: CGFloat) -> CGPoint {
        let angle = fraction * 2 * .pi - .pi / 2
        let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
        let half = CGSize(width: rect.width / 2, height: rect.height / 2)
        let radius = min(max(cornerRadius, 0), half.width, half.height)
        // Where the line leaves the square-cornered rect.
        let alongX = abs(dx) > 1e-9 ? half.width / abs(dx) : .infinity
        let alongY = abs(dy) > 1e-9 ? half.height / abs(dy) : .infinity
        var distance = min(alongX, alongY)
        // In a corner it meets the corner's arc instead.
        let straight = CGSize(width: half.width - radius, height: half.height - radius)
        if abs(dx * distance) > straight.width, abs(dy * distance) > straight.height {
            let corner = CGPoint(x: dx < 0 ? -straight.width : straight.width, y: dy < 0 ? -straight.height : straight.height)
            // The far root of |distance * direction - corner| = radius.
            let along = dx * corner.x + dy * corner.y
            let offset = corner.x * corner.x + corner.y * corner.y - radius * radius
            distance = along + (max(along * along - offset, 0)).squareRoot()
        }
        return CGPoint(x: rect.midX + dx * distance, y: rect.midY + dy * distance)
    }
}
