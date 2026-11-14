import CoreGraphics
import Foundation
import ImageIO
import simd

/// A face found in the depth map alone, on the followed person's head: the
/// dot projector's view of it, with no camera image and no ARKit face. In a
/// 3 lux room ARKit found no face in 478 frames with the owner looking at the
/// iPad from 0.5 m, while the depth map showed him the whole time.
///
/// This is face data. It stays on the analysis queue, in the depth identity
/// evaluation and in the protected template folder, never in a trace or a log.
struct DepthFace: Sendable {
    /// The nose tip in the depth map, normalized with a top-left origin.
    var nosePoint: CGPoint
    /// Distance to the nose tip along the camera axis, in meters.
    var noseMeters: Double
    /// The face's surface within `DepthFaceFinder.radiusMeters` of the nose
    /// tip: x, y and z of each point in meters, the nose tip at the origin, x
    /// to the right, y down and z away from the camera, turned upright.
    var points: [Float]
    /// Median depth of that surface behind the nose tip, in meters.
    var relief: Double
    /// Share of the disc within `DepthFaceFinder.coverageRadiusMeters` of the
    /// nose tip, seen from the camera, the surface covers.
    var coverage: Double

    var pointCount: Int { points.count / 3 }
}

/// Finds the face on the followed head in a full depth map.
///
/// The nose tip is the nearest part of a face that looks at the camera, so it
/// is taken as the nearest few millimeters of the head (a robust minimum, so a
/// stray pixel does not count). The face is everything within 9 cm of it.
/// It must look like a face: a surface that falls away behind the nose by a
/// face's depth and covers most of the disc around it. A flat photo, a wall or
/// a chair back does not.
enum DepthFaceFinder {
    /// How far from the nose tip the face reaches, in meters.
    static let radiusMeters = 0.09
    /// Points kept at most, taken on an even grid: about 3.6 mm apart.
    static let maximumPoints = 2000
    static let minimumPoints = 150
    /// How far behind its nose tip a face's surface lies, at the median, in meters.
    static let reliefRange = 0.012...0.06
    /// Share of the disc within `coverageRadiusMeters` of the nose tip, seen
    /// from the camera, the surface must cover. Farther out a face curves
    /// away behind the 9 cm reach, so the full disc is never covered.
    static let minimumCoverage = 0.6
    static let coverageRadiusMeters = 0.05
    /// The nearest share of the head's depths, and how far behind their
    /// deepest the nose tip still reaches, in meters.
    static let nearestFraction = 0.01
    static let noseDepthMeters: Float = 0.005

    static func find(
        in map: DepthMap, head: DepthPersonTracker.Person, orientation: CGImagePropertyOrientation
    ) -> DepthFace? {
        let width = map.width
        let height = map.height
        let focal = Float(map.focalLengthOrDefault)
        guard width > 0, height > 0, focal > 0 else { return nil }

        // The nose tip: the nearest few millimeters of the head.
        let centerX = Double(head.center.x) * Double(width)
        let centerY = Double(head.center.y) * Double(height)
        let reachX = max(4, Double(head.radius.width) * Double(width) * 1.2)
        let reachY = max(4, Double(head.radius.height) * Double(height) * 1.2)
        let columns = clamp(Int(centerX - reachX), width)...clamp(Int(centerX + reachX), width)
        let rows = clamp(Int(centerY - reachY), height)...clamp(Int(centerY + reachY), height)
        let near = Float(head.distanceMeters - 0.25)
        let far = Float(head.distanceMeters + 0.15)
        var headDepths: [Float] = []
        for row in rows {
            for column in columns {
                let z = map.meters[row * width + column]
                if z.isFinite, z > near, z < far { headDepths.append(z) }
            }
        }
        guard headDepths.count >= minimumPoints else { return nil }
        headDepths.sort()
        let nearest = headDepths[Int(Double(headDepths.count - 1) * nearestFraction)]
        var sumColumn = 0.0
        var sumRow = 0.0
        var tipDepths: [Float] = []
        for row in rows {
            for column in columns {
                let z = map.meters[row * width + column]
                guard z.isFinite, z >= nearest - 0.01, z <= nearest + noseDepthMeters else { continue }
                sumColumn += Double(column)
                sumRow += Double(row)
                tipDepths.append(z)
            }
        }
        guard !tipDepths.isEmpty else { return nil }
        tipDepths.sort()
        let tipColumn = sumColumn / Double(tipDepths.count)
        let tipRow = sumRow / Double(tipDepths.count)
        let tipZ = tipDepths[tipDepths.count / 2]
        let tip = point(column: tipColumn, row: tipRow, z: tipZ, width: width, height: height, focal: focal)

        // The face: the surface within `radiusMeters` of the tip, on an even grid.
        let radius = Float(radiusMeters)
        let radiusPixels = Double(radius * focal / tipZ)
        let step = max(1, Int((Double.pi * radiusPixels * radiusPixels / Double(maximumPoints)).squareRoot().rounded(.up)))
        let coveragePixels = Double(Float(coverageRadiusMeters) * focal / tipZ)
        var points: [Float] = []
        var behind: [Float] = []
        var discCells = 0
        var coveredCells = 0
        let disc = Int(radiusPixels.rounded(.up))
        for row in stride(from: Int(tipRow) - disc, through: Int(tipRow) + disc, by: step) {
            for column in stride(from: Int(tipColumn) - disc, through: Int(tipColumn) + disc, by: step) {
                let dx = Double(column) - tipColumn
                let dy = Double(row) - tipRow
                let lateral = dx * dx + dy * dy
                guard lateral <= radiusPixels * radiusPixels else { continue }
                let inCoverage = lateral <= coveragePixels * coveragePixels
                if inCoverage { discCells += 1 }
                let z = map.depth(column: column, row: row)
                guard z.isFinite else { continue }
                let p = point(column: Double(column), row: Double(row), z: z, width: width, height: height, focal: focal)
                let offset = p - tip
                guard simd_length(offset) <= radius else { continue }
                if inCoverage { coveredCells += 1 }
                let upright = uprighted(offset, orientation)
                points.append(contentsOf: [upright.x, upright.y, upright.z])
                behind.append(offset.z)
            }
        }
        guard points.count / 3 >= minimumPoints, discCells > 0 else { return nil }
        behind.sort()
        let relief = Double(behind[behind.count / 2])
        let coverage = Double(coveredCells) / Double(discCells)
        guard reliefRange.contains(relief), coverage >= minimumCoverage else { return nil }
        return DepthFace(
            nosePoint: CGPoint(x: tipColumn / Double(width), y: tipRow / Double(height)),
            noseMeters: Double(tipZ), points: points, relief: relief, coverage: coverage
        )
    }

    /// The point at a pixel and depth, in meters, with the principal point
    /// taken at the map's center.
    private static func point(column: Double, row: Double, z: Float, width: Int, height: Int, focal: Float) -> SIMD3<Float> {
        let x = (Float(column) - Float(width) / 2) * z / focal
        let y = (Float(row) - Float(height) / 2) * z / focal
        return SIMD3(x, y, z)
    }

    /// Turns an offset in the native map the way the image turns to stand
    /// upright, so faces from an iPad turned another way still compare.
    static func uprighted(_ offset: SIMD3<Float>, _ orientation: CGImagePropertyOrientation) -> SIMD3<Float> {
        let x = offset.x
        let y = offset.y
        switch orientation {
        case .up, .upMirrored: return SIMD3(x, y, offset.z)
        case .down, .downMirrored: return SIMD3(-x, -y, offset.z)
        case .right, .rightMirrored: return SIMD3(-y, x, offset.z)
        case .left, .leftMirrored: return SIMD3(y, -x, offset.z)
        }
    }

    private static func clamp(_ value: Int, _ size: Int) -> Int {
        min(max(value, 0), size - 1)
    }
}
