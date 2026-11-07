import RoomPlan

/// Maps RoomPlan's `CapturedRoom` onto the plain scan types the converter tests use.
enum RoomPlanAdapter {
    static func surfaces(in room: CapturedRoom) -> [ScannedSurface] {
        let walls = room.walls.map { ScannedSurface(kind: .wall, dimensions: $0.dimensions, transform: $0.transform) }
        let doors = room.doors.map { ScannedSurface(kind: .door, dimensions: $0.dimensions, transform: $0.transform) }
        let windows = room.windows.map { ScannedSurface(kind: .window, dimensions: $0.dimensions, transform: $0.transform) }
        let openings = room.openings.map { ScannedSurface(kind: .opening, dimensions: $0.dimensions, transform: $0.transform) }
        return walls + doors + windows + openings
    }

    static func objects(in room: CapturedRoom) -> [ScannedObject] {
        room.objects.map { ScannedObject(category: String(describing: $0.category), dimensions: $0.dimensions, transform: $0.transform) }
    }

    /// One plan from every room scanned in the same session (they share a coordinate space).
    static func plan(from rooms: [CapturedRoom], name: String, keeping placements: [FloorPlan.AccessoryPlacement]) -> FloorPlan {
        FloorPlanConverter.makePlan(
            name: name, surfaces: rooms.flatMap(surfaces(in:)), objects: rooms.flatMap(objects(in:)), placements: placements
        )
    }
}
