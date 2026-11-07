import Foundation
import HomePadCore

/// A small two-room apartment for iPads without LiDAR and for the simulator.
/// Demo accessories are placed where they would sit in a real home.
enum DemoFloorPlan {
    static func make(accessories: [HomeAccessory]) -> FloorPlan {
        func point(_ x: Double, _ y: Double) -> PlanPoint { PlanPoint(x: x + 0.3, y: y + 0.3) }
        func wall(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> FloorPlan.Wall {
            FloorPlan.Wall(id: UUID(), start: point(x1, y1), end: point(x2, y2))
        }
        func opening(_ kind: FloorPlan.Opening.Kind, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> FloorPlan.Opening {
            FloorPlan.Opening(id: UUID(), kind: kind, start: point(x1, y1), end: point(x2, y2))
        }
        func item(_ category: String, _ x: Double, _ y: Double, _ width: Double, _ depth: Double, _ rotation: Double = 0) -> FloorPlan.Furniture {
            FloorPlan.Furniture(id: UUID(), category: category, center: point(x, y), width: width, depth: depth, rotation: rotation)
        }

        // Living room 5.5 m by 4.2 m on the left, kitchen 3.2 m wide on the right.
        let walls = [
            wall(0, 0, 8.7, 0), wall(8.7, 0, 8.7, 4.2), wall(8.7, 4.2, 0, 4.2), wall(0, 4.2, 0, 0),
            wall(5.5, 0, 5.5, 4.2),
        ]
        let openings = [
            opening(.door, 1.0, 4.2, 1.9, 4.2),
            opening(.opening, 5.5, 1.4, 5.5, 2.8),
            opening(.window, 1.6, 0, 3.6, 0),
            opening(.window, 6.4, 0, 7.8, 0),
            opening(.window, 0, 1.4, 0, 2.8),
        ]
        let furniture = [
            item("sofa", 2.6, 3.4, 2.2, 0.9),
            item("table", 2.6, 2.0, 1.2, 0.6),
            item("television", 2.6, 0.25, 1.4, 0.3),
            item("chair", 4.6, 1.2, 0.6, 0.6, .pi / 6),
            item("refrigerator", 8.3, 0.5, 0.75, 0.7),
            item("stove", 8.3, 1.6, 0.75, 0.65),
            item("sink", 8.3, 2.6, 0.75, 0.6),
            item("table", 6.8, 2.9, 1.2, 0.8),
        ]
        let spots: [String: PlanPoint] = [
            "demo:light.living": point(4.3, 3.3),
            "demo:light.kitchen": point(7.0, 1.5),
            "demo:light.entry": point(0.55, 3.0),
            "demo:lock.front": point(1.45, 3.7),
            "demo:climate.living": point(5.05, 0.7),
            "demo:cover.living": point(2.6, 0.6),
            "demo:fan.office": point(6.8, 3.6),
        ]
        let placements = accessories.compactMap { accessory in
            spots[accessory.id].map { FloorPlan.AccessoryPlacement(accessoryID: accessory.id, position: $0) }
        }
        return FloorPlan(name: "Demo Apartment", walls: walls, openings: openings, furniture: furniture,
                         placements: placements, isDemo: true, updatedAt: Date())
    }
}
