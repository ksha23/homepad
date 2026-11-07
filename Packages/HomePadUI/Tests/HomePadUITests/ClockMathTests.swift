import CoreGraphics
import Testing
@testable import HomePadUI

/// Numerals along a rounded rectangle sit where the line from the center
/// toward their hour meets its edge.
struct ClockMathTests {
    private static let rect = CGRect(x: 100, y: 50, width: 1000, height: 700)

    @Test func theQuarterHoursMeetTheMiddleOfEachSide() {
        let rect = Self.rect
        let points = [0, 0.25, 0.5, 0.75].map { ClockMath.point(fraction: $0, onRoundedRect: rect, cornerRadius: 120) }
        let expected = [CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                        CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)]
        for (point, target) in zip(points, expected) {
            #expect(abs(point.x - target.x) < 0.001 && abs(point.y - target.y) < 0.001, "\(point) \(target)")
        }
    }

    @Test func eachHourLiesOnTheRoundedEdgeAlongItsDirection() {
        let rect = Self.rect
        let radius: CGFloat = 120
        for hour in 0..<12 {
            let fraction = Double(hour) / 12
            let point = ClockMath.point(fraction: fraction, onRoundedRect: rect, cornerRadius: radius)
            // Along the hour's direction from the center, like a hand.
            let onCircle = ClockMath.point(fraction: fraction, radius: 1, center: CGPoint(x: rect.midX, y: rect.midY))
            let direction = CGVector(dx: onCircle.x - rect.midX, dy: onCircle.y - rect.midY)
            let cross = (point.x - rect.midX) * direction.dy - (point.y - rect.midY) * direction.dx
            #expect(abs(cross) < 0.01, "hour \(hour)")
            // On the edge: on a straight side, or exactly the radius from a corner's center.
            let straightX = rect.width / 2 - radius
            let straightY = rect.height / 2 - radius
            let local = CGPoint(x: point.x - rect.midX, y: point.y - rect.midY)
            if abs(local.x) > straightX, abs(local.y) > straightY {
                let corner = CGPoint(x: local.x < 0 ? -straightX : straightX, y: local.y < 0 ? -straightY : straightY)
                #expect(abs(hypot(local.x - corner.x, local.y - corner.y) - radius) < 0.01, "hour \(hour)")
            } else {
                #expect(abs(abs(local.x) - rect.width / 2) < 0.01 || abs(abs(local.y) - rect.height / 2) < 0.01, "hour \(hour)")
            }
        }
    }

    @Test func roundedCornersPullTheCornerHoursIn() {
        // On a square, 1:30 points straight at the corner.
        let square = CGRect(x: 0, y: 0, width: 400, height: 400)
        let sharp = ClockMath.point(fraction: 1.5 / 12, onRoundedRect: square, cornerRadius: 0)
        let round = ClockMath.point(fraction: 1.5 / 12, onRoundedRect: square, cornerRadius: 100)
        #expect(abs(sharp.x - 400) < 0.01 && abs(sharp.y) < 0.01)
        #expect(round.x < sharp.x && round.y > sharp.y)
    }
}
