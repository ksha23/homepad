import Foundation

/// A point on the floor plan, in meters, seen from above. `y` grows toward
/// the bottom of the screen.
struct PlanPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

/// An axis-aligned rectangle on the plan, in meters.
struct PlanRect: Codable, Hashable, Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
}

/// A 2D floor plan made from a LiDAR room scan (or the demo), with the
/// accessories the household placed on it. Stored as JSON on the iPad.
struct FloorPlan: Codable, Equatable, Sendable {
    static let currentVersion = 1

    struct Wall: Codable, Hashable, Identifiable, Sendable {
        var id: UUID
        var start: PlanPoint
        var end: PlanPoint
    }

    /// A door, window or open passage, drawn on top of its wall.
    struct Opening: Codable, Hashable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable { case door, window, opening }
        var id: UUID
        var kind: Kind
        var start: PlanPoint
        var end: PlanPoint
    }

    /// Furniture and appliances RoomPlan recognized, as a rotated footprint.
    struct Furniture: Codable, Hashable, Identifiable, Sendable {
        var id: UUID
        /// RoomPlan's category name, for example "sofa" or "refrigerator".
        var category: String
        var center: PlanPoint
        var width: Double
        var depth: Double
        /// Radians, turning from the plan's x axis toward its y axis.
        var rotation: Double
    }

    /// Where a smart home accessory sits on the plan.
    struct AccessoryPlacement: Codable, Hashable, Identifiable, Sendable {
        var accessoryID: String
        var position: PlanPoint
        var id: String { accessoryID }
    }

    var version = FloorPlan.currentVersion
    var name: String
    var walls: [Wall]
    var openings: [Opening]
    var furniture: [Furniture]
    var placements: [AccessoryPlacement]
    var isDemo: Bool
    var updatedAt: Date

    /// Everything drawn on the plan, so views can scale it to fit.
    var bounds: PlanRect {
        var points = walls.flatMap { [$0.start, $0.end] } + openings.flatMap { [$0.start, $0.end] }
        points += furniture.flatMap(\.corners)
        points += placements.map(\.position)
        guard let first = points.first else { return PlanRect(minX: 0, minY: 0, maxX: 1, maxY: 1) }
        return points.dropFirst().reduce(PlanRect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)) { rect, point in
            PlanRect(minX: min(rect.minX, point.x), minY: min(rect.minY, point.y),
                     maxX: max(rect.maxX, point.x), maxY: max(rect.maxY, point.y))
        }
    }

    /// Moves or adds an accessory's placement.
    mutating func place(_ accessoryID: String, at position: PlanPoint) {
        placements.removeAll { $0.accessoryID == accessoryID }
        placements.append(AccessoryPlacement(accessoryID: accessoryID, position: position))
    }

    mutating func removePlacement(_ accessoryID: String) {
        placements.removeAll { $0.accessoryID == accessoryID }
    }
}

extension FloorPlan.Furniture {
    /// The four corners of the rotated footprint.
    var corners: [PlanPoint] {
        let cosine = cos(rotation), sine = sin(rotation)
        let halfWidth = width / 2, halfDepth = depth / 2
        return [(-halfWidth, -halfDepth), (halfWidth, -halfDepth), (halfWidth, halfDepth), (-halfWidth, halfDepth)].map { dx, dy in
            PlanPoint(x: center.x + dx * cosine - dy * sine, y: center.y + dx * sine + dy * cosine)
        }
    }
}
