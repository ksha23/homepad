import Foundation
import simd

/// A wall, door, window or opening from a room scan, in RoomPlan's world
/// coordinates (meters, y up). Kept separate from RoomPlan's types so the
/// conversion math can be tested with synthetic rooms.
struct ScannedSurface: Sendable {
    enum Kind: Equatable, Sendable {
        case wall
        case door
        case window
        case opening
    }

    var kind: Kind
    /// Width (x), height (y) and depth (z) in the surface's local frame.
    var dimensions: SIMD3<Float>
    var transform: simd_float4x4
}

/// A piece of furniture or an appliance from a room scan.
struct ScannedObject: Sendable {
    var category: String
    var dimensions: SIMD3<Float>
    var transform: simd_float4x4
}

/// Projects scanned rooms onto the floor (world x and z) to make a 2D plan.
///
/// A surface's local x axis runs along its width, so its footprint is the
/// segment `center ± axis × width / 2`. Objects keep their x by z footprint and
/// the rotation of their x axis. The result is shifted so the plan starts at
/// `margin` meters from the origin.
enum FloorPlanConverter {
    static let margin = 0.3

    static func makePlan(
        name: String, surfaces: [ScannedSurface], objects: [ScannedObject],
        placements: [FloorPlan.AccessoryPlacement] = [], date: Date = Date()
    ) -> FloorPlan {
        var walls: [FloorPlan.Wall] = []
        var openings: [FloorPlan.Opening] = []
        for surface in surfaces {
            guard let (start, end) = segment(of: surface) else { continue }
            switch surface.kind {
            case .wall: walls.append(FloorPlan.Wall(id: UUID(), start: start, end: end))
            case .door: openings.append(FloorPlan.Opening(id: UUID(), kind: .door, start: start, end: end))
            case .window: openings.append(FloorPlan.Opening(id: UUID(), kind: .window, start: start, end: end))
            case .opening: openings.append(FloorPlan.Opening(id: UUID(), kind: .opening, start: start, end: end))
            }
        }
        let furniture = objects.compactMap(footprint(of:))
        var plan = FloorPlan(name: name, walls: walls, openings: openings, furniture: furniture,
                             placements: [], isDemo: false, updatedAt: date)
        plan = normalized(plan)
        plan.placements = placements
        return plan
    }

    /// The floor-level segment a vertical surface covers, or nil for surfaces
    /// whose width axis points up (floors, ceilings).
    static func segment(of surface: ScannedSurface) -> (PlanPoint, PlanPoint)? {
        guard let axis = planAxis(surface.transform) else { return nil }
        let center = planCenter(surface.transform)
        let half = Double(surface.dimensions.x) / 2
        return (PlanPoint(x: center.x - axis.x * half, y: center.y - axis.y * half),
                PlanPoint(x: center.x + axis.x * half, y: center.y + axis.y * half))
    }

    static func footprint(of object: ScannedObject) -> FloorPlan.Furniture? {
        guard let axis = planAxis(object.transform) else { return nil }
        return FloorPlan.Furniture(
            id: UUID(), category: object.category, center: planCenter(object.transform),
            width: Double(object.dimensions.x), depth: Double(object.dimensions.z), rotation: atan2(axis.y, axis.x)
        )
    }

    /// Shifts everything so the plan's top left corner sits at (margin, margin).
    static func normalized(_ plan: FloorPlan) -> FloorPlan {
        let bounds = plan.bounds
        let dx = margin - bounds.minX, dy = margin - bounds.minY
        func shift(_ point: PlanPoint) -> PlanPoint { PlanPoint(x: point.x + dx, y: point.y + dy) }
        var result = plan
        result.walls = plan.walls.map { FloorPlan.Wall(id: $0.id, start: shift($0.start), end: shift($0.end)) }
        result.openings = plan.openings.map { FloorPlan.Opening(id: $0.id, kind: $0.kind, start: shift($0.start), end: shift($0.end)) }
        result.furniture = plan.furniture.map { item in
            var moved = item
            moved.center = shift(item.center)
            return moved
        }
        result.placements = plan.placements.map { FloorPlan.AccessoryPlacement(accessoryID: $0.accessoryID, position: shift($0.position)) }
        return result
    }

    private static func planCenter(_ transform: simd_float4x4) -> PlanPoint {
        PlanPoint(x: Double(transform.columns.3.x), y: Double(transform.columns.3.z))
    }

    /// The local x axis projected onto the floor and normalized.
    private static func planAxis(_ transform: simd_float4x4) -> PlanPoint? {
        let x = Double(transform.columns.0.x), z = Double(transform.columns.0.z)
        let length = (x * x + z * z).squareRoot()
        guard length > 0.1 else { return nil }
        return PlanPoint(x: x / length, y: z / length)
    }
}
