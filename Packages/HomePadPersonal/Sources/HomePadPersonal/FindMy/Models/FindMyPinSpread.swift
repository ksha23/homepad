import CoreGraphics
import Foundation

/// Fans out map pins that would sit on top of each other at the current zoom,
/// so every device stays visible and tappable. A household's devices are
/// usually all at home, a few meters apart, where their pins would stack.
///
/// Pins closer than `gap` points form a group, and each group spreads around
/// its middle in a small circle. Zoomed in far enough, nothing overlaps and
/// every pin sits on its own coordinate. It is worked out once each time the
/// map stops moving, never per frame.
enum FindMyPinSpread {
    struct Pin: Equatable {
        var id: String
        var latitude: Double
        var longitude: Double
    }

    /// How far each pin moves from its coordinate, in points. Pins that need
    /// no move are left out.
    /// - Parameters:
    ///   - pins: In a stable order, so groups do not reshuffle between updates.
    ///   - metersPerPoint: The map's scale right now.
    ///   - gap: The closest two pin centers may be, about a pin's width.
    static func offsets(for pins: [Pin], metersPerPoint: Double, gap: CGFloat = 52) -> [String: CGSize] {
        guard metersPerPoint > 0, pins.count > 1 else { return [:] }
        var groups: [[Pin]] = []
        for pin in pins {
            if let index = groups.firstIndex(where: { group in
                group.contains { distance(from: $0, to: pin, metersPerPoint: metersPerPoint) < gap }
            }) {
                groups[index].append(pin)
            } else {
                groups.append([pin])
            }
        }
        var result: [String: CGSize] = [:]
        for group in groups where group.count > 1 {
            let center = Pin(id: "", latitude: group.map(\.latitude).reduce(0, +) / Double(group.count),
                             longitude: group.map(\.longitude).reduce(0, +) / Double(group.count))
            // Neighbors on the circle sit `gap` apart: the chord 2R sin(pi / n).
            let radius = gap / (2 * sin(.pi / CGFloat(max(group.count, 2))))
            for (index, pin) in group.enumerated() {
                let angle = 2 * .pi * CGFloat(index) / CGFloat(group.count) - .pi / 2
                let target = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
                let actual = point(of: pin, from: center, metersPerPoint: metersPerPoint)
                result[pin.id] = CGSize(width: target.x - actual.x, height: target.y - actual.y)
            }
        }
        return result
    }

    /// Where to draw each pin that has to move: its coordinate shifted by its
    /// offset. Moving the coordinate rather than the drawing keeps MapKit's own
    /// placement and tapping.
    static func coordinates(for pins: [Pin], metersPerPoint: Double, gap: CGFloat = 52) -> [String: Pin] {
        let moves = offsets(for: pins, metersPerPoint: metersPerPoint, gap: gap)
        var result: [String: Pin] = [:]
        for pin in pins {
            guard let offset = moves[pin.id] else { continue }
            let metersPerDegree = 111_320.0
            let north = -Double(offset.height) * metersPerPoint
            let east = Double(offset.width) * metersPerPoint
            result[pin.id] = Pin(
                id: pin.id,
                latitude: pin.latitude + north / metersPerDegree,
                longitude: pin.longitude + east / (metersPerDegree * cos(pin.latitude * .pi / 180))
            )
        }
        return result
    }

    /// Where a pin sits relative to another on screen, in points (y grows southward).
    static func point(of pin: Pin, from origin: Pin, metersPerPoint: Double) -> CGPoint {
        let metersPerDegree = 111_320.0
        let east = (pin.longitude - origin.longitude) * metersPerDegree * cos(origin.latitude * .pi / 180)
        let north = (pin.latitude - origin.latitude) * metersPerDegree
        return CGPoint(x: east / metersPerPoint, y: -north / metersPerPoint)
    }

    static func distance(from a: Pin, to b: Pin, metersPerPoint: Double) -> CGFloat {
        let delta = point(of: b, from: a, metersPerPoint: metersPerPoint)
        return hypot(delta.x, delta.y)
    }
}
