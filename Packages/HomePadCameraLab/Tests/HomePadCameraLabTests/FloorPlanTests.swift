import Foundation
import HomePadCore
import simd
import Testing
@testable import HomePadCameraLab

@Suite struct FloorPlanConverterTests {
    /// A transform that turns `angle` radians about the vertical axis and moves to (x, y, z).
    private func transform(angle: Float, x: Float, y: Float = 1.2, z: Float) -> simd_float4x4 {
        var matrix = simd_float4x4(simd_quatf(angle: angle, axis: SIMD3(0, 1, 0)))
        matrix.columns.3 = SIMD4(x, y, z, 1)
        return matrix
    }

    private func close(_ a: PlanPoint, _ b: PlanPoint, tolerance: Double = 0.001) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    @Test func wallAlongXProjectsToASegment() throws {
        let wall = ScannedSurface(kind: .wall, dimensions: SIMD3(4, 2.5, 0), transform: transform(angle: 0, x: 2, z: 0))
        let (start, end) = try #require(FloorPlanConverter.segment(of: wall))
        #expect(close(start, PlanPoint(x: 0, y: 0)))
        #expect(close(end, PlanPoint(x: 4, y: 0)))
    }

    @Test func rotatedWallRunsAlongZ() throws {
        // Turning 90 degrees about y maps the local x axis onto world -z.
        let wall = ScannedSurface(kind: .wall, dimensions: SIMD3(3, 2.5, 0), transform: transform(angle: .pi / 2, x: 5, z: 1.5))
        let (start, end) = try #require(FloorPlanConverter.segment(of: wall))
        #expect(close(start, PlanPoint(x: 5, y: 3)))
        #expect(close(end, PlanPoint(x: 5, y: 0)))
    }

    @Test func horizontalSurfacesAreSkipped() {
        // A floor's width axis points straight up after this tilt.
        var tilted = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)))
        tilted.columns.3 = SIMD4(1, 0, 1, 1)
        let floor = ScannedSurface(kind: .wall, dimensions: SIMD3(4, 4, 0), transform: tilted)
        #expect(FloorPlanConverter.segment(of: floor) == nil)
    }

    @Test func objectsKeepFootprintAndRotation() throws {
        let sofa = ScannedObject(category: "sofa", dimensions: SIMD3(2.2, 0.8, 0.9), transform: transform(angle: -.pi / 4, x: 1, z: 2))
        let footprint = try #require(FloorPlanConverter.footprint(of: sofa))
        #expect(footprint.category == "sofa")
        #expect(close(footprint.center, PlanPoint(x: 1, y: 2)))
        #expect(abs(footprint.width - 2.2) < 0.001)
        #expect(abs(footprint.depth - 0.9) < 0.001)
        // Turning -45 degrees about y points local x at (+x, +z), 45 degrees toward the plan's y axis.
        #expect(abs(footprint.rotation - .pi / 4) < 0.001)
        #expect(footprint.corners.count == 4)
    }

    @Test func roomBecomesANormalizedPlan() {
        // A 4 by 3 m room centered on the world origin, with a door and a window.
        let surfaces = [
            ScannedSurface(kind: .wall, dimensions: SIMD3(4, 2.5, 0), transform: transform(angle: 0, x: 0, z: -1.5)),
            ScannedSurface(kind: .wall, dimensions: SIMD3(4, 2.5, 0), transform: transform(angle: .pi, x: 0, z: 1.5)),
            ScannedSurface(kind: .wall, dimensions: SIMD3(3, 2.5, 0), transform: transform(angle: .pi / 2, x: -2, z: 0)),
            ScannedSurface(kind: .wall, dimensions: SIMD3(3, 2.5, 0), transform: transform(angle: -.pi / 2, x: 2, z: 0)),
            ScannedSurface(kind: .door, dimensions: SIMD3(0.9, 2, 0), transform: transform(angle: 0, x: 0.5, z: 1.5)),
            ScannedSurface(kind: .window, dimensions: SIMD3(1.2, 1, 0), transform: transform(angle: 0, x: 0, z: -1.5)),
        ]
        let objects = [ScannedObject(category: "table", dimensions: SIMD3(1, 0.75, 0.6), transform: transform(angle: 0, x: 0, z: 0))]
        let plan = FloorPlanConverter.makePlan(name: "Test", surfaces: surfaces, objects: objects)

        #expect(plan.walls.count == 4)
        #expect(plan.openings.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.door, .window])
        #expect(plan.furniture.count == 1)
        let bounds = plan.bounds
        #expect(abs(bounds.minX - FloorPlanConverter.margin) < 0.001)
        #expect(abs(bounds.minY - FloorPlanConverter.margin) < 0.001)
        #expect(abs(bounds.width - 4) < 0.001)
        #expect(abs(bounds.height - 3) < 0.001)
        // The table sits in the middle of the room after the shift.
        #expect(close(plan.furniture[0].center, PlanPoint(x: 2.3, y: 1.8)))
        #expect(!plan.isDemo)
    }

    @Test func placementsAreKeptOutOfNormalization() {
        let placement = FloorPlan.AccessoryPlacement(accessoryID: "demo:light.kitchen", position: PlanPoint(x: 1, y: 1))
        let plan = FloorPlanConverter.makePlan(
            name: "Test",
            surfaces: [ScannedSurface(kind: .wall, dimensions: SIMD3(4, 2.5, 0), transform: transform(angle: 0, x: 10, z: 10))],
            objects: [], placements: [placement]
        )
        #expect(plan.placements == [placement])
    }

    @Test func placingMovesAnExistingPin() {
        var plan = DemoFloorPlan.make(accessories: [])
        plan.place("a", at: PlanPoint(x: 1, y: 1))
        plan.place("a", at: PlanPoint(x: 2, y: 2))
        plan.place("b", at: PlanPoint(x: 3, y: 3))
        #expect(plan.placements.count == 2)
        #expect(plan.placements.first { $0.accessoryID == "a" }?.position == PlanPoint(x: 2, y: 2))
        plan.removePlacement("a")
        #expect(plan.placements.map(\.accessoryID) == ["b"])
    }
}

@MainActor
@Suite struct FloorPlanStoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cameralab-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("floorplan.json")
    }

    @Test func savesAndLoadsTheSamePlan() throws {
        let url = temporaryFile()
        let store = FloorPlanStore(fileURL: url)
        #expect(store.plan == nil)
        let accessories = DemoSmartHomeService().accessories
        store.useDemo(accessories: accessories)
        store.place("demo:light.kitchen", at: PlanPoint(x: 4.25, y: 1.5))
        let saved = try #require(store.plan)

        let reloaded = FloorPlanStore(fileURL: url)
        #expect(reloaded.plan == saved)
        #expect(reloaded.plan?.placements.first { $0.accessoryID == "demo:light.kitchen" }?.position == PlanPoint(x: 4.25, y: 1.5))
        #expect(reloaded.plan?.isDemo == true)
        #expect(reloaded.plan?.version == FloorPlan.currentVersion)

        reloaded.reset()
        #expect(FloorPlanStore(fileURL: url).plan == nil)
    }

    @Test func rescanKeepsPlacements() {
        let store = FloorPlanStore(fileURL: temporaryFile())
        store.useDemo(accessories: DemoSmartHomeService().accessories)
        let before = store.plan?.placements ?? []
        #expect(!before.isEmpty)
        let scanned = FloorPlanConverter.makePlan(name: "Scan", surfaces: [], objects: [])
        store.replaceGeometry(with: scanned)
        #expect(store.plan?.placements == before)
        #expect(store.plan?.name == "Scan")
    }

    @Test func demoPlacesOnlyKnownAccessories() {
        let plan = DemoFloorPlan.make(accessories: [HomeAccessory(id: "demo:light.kitchen", name: "Kitchen", kind: .light, backend: .demo)])
        #expect(plan.placements.map(\.accessoryID) == ["demo:light.kitchen"])
        #expect(!plan.walls.isEmpty)
        #expect(plan.openings.contains { $0.kind == .door })
    }
}
