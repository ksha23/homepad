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
    /// away behind the 9 cm reach, so the full disc is never covered. A face
    /// looking a little down or aside read 0.54 to 0.57, with 3.6 cm of relief.
    static let minimumCoverage = 0.5
    static let coverageRadiusMeters = 0.05
    /// The nearest share of the head's depths, and how far behind their
    /// deepest the nose tip still reaches, in meters.
    static let nearestFraction = 0.01
    static let noseDepthMeters: Float = 0.005

    /// One search of the followed head: the face, or why there was none,
    /// in numbers only, with where the nose tip was looked for.
    struct Search: Sendable {
        var face: DepthFace?
        /// The nose tip candidate, normalized with a top-left origin, and its distance.
        var nosePoint: CGPoint?
        var noseMeters: Double?
        /// Why it is not a face, for the trace and the debug view. Nil when it is.
        var miss: String?
    }

    /// How far around the nearest point the nose tip is averaged, in meters.
    static let tipRadiusMeters: Float = 0.03

    static func find(
        in map: DepthMap, head: DepthPersonTracker.Person, orientation: CGImagePropertyOrientation
    ) -> DepthFace? {
        search(in: map, head: head, orientation: orientation).face
    }

    static func search(
        in map: DepthMap, head: DepthPersonTracker.Person, orientation: CGImagePropertyOrientation
    ) -> Search {
        let width = map.width
        let height = map.height
        let focal = Float(map.focalLengthOrDefault)
        guard width > 0, height > 0, focal > 0 else { return Search(miss: "no depth map") }

        // The nose tip: the nearest few millimeters of the head, around its nearest point.
        let centerX = Double(head.center.x) * Double(width)
        let centerY = Double(head.center.y) * Double(height)
        let reachX = max(4, Double(head.radius.width) * Double(width) * 1.2)
        let reachY = max(4, Double(head.radius.height) * Double(height) * 1.2)
        let columns = clamp(Int(centerX - reachX), width)...clamp(Int(centerX + reachX), width)
        let rows = clamp(Int(centerY - reachY), height)...clamp(Int(centerY + reachY), height)
        let near = Float(head.distanceMeters - 0.25)
        let far = Float(head.distanceMeters + 0.15)
        var headPixels: [(column: Int, row: Int, z: Float)] = []
        for row in rows {
            for column in columns {
                let z = map.meters[row * width + column]
                if z.isFinite, z > near, z < far { headPixels.append((column, row, z)) }
            }
        }
        guard headPixels.count >= minimumPoints else {
            return Search(miss: "the head shows only \(headPixels.count) depth points")
        }
        guard var candidate = nearestTip(headPixels, focal: focal) else { return Search(miss: "no nose tip") }
        // The followed head is not always centered on the face, so the nearest
        // point of its window can sit on its edge with the nose beyond it. The
        // tip moves to the nearest point within reach of where it is until it
        // stays put: on a face looking at the camera, the nose.
        for _ in 0..<4 {
            let reach = Double(radiusMeters) * Double(focal) / Double(candidate.z)
            var around: [(column: Int, row: Int, z: Float)] = []
            let rowRange = clamp(Int(candidate.row - reach), height)...clamp(Int(candidate.row + reach), height)
            let columnRange = clamp(Int(candidate.column - reach), width)...clamp(Int(candidate.column + reach), width)
            for row in rowRange {
                for column in columnRange {
                    let dx = Double(column) - candidate.column
                    let dy = Double(row) - candidate.row
                    guard dx * dx + dy * dy <= reach * reach else { continue }
                    let z = map.meters[row * width + column]
                    if z.isFinite, z > candidate.z - 0.15, z < candidate.z + 0.15 { around.append((column, row, z)) }
                }
            }
            guard let next = nearestTip(around, focal: focal) else { break }
            let moved = abs(next.column - candidate.column) + abs(next.row - candidate.row)
            candidate = next
            if moved < 1 { break }
        }
        let tipColumn = candidate.column
        let tipRow = candidate.row
        let tipZ = candidate.z
        let tip = point(column: tipColumn, row: tipRow, z: tipZ, width: width, height: height, focal: focal)
        var result = Search(
            nosePoint: CGPoint(x: tipColumn / Double(width), y: tipRow / Double(height)), noseMeters: Double(tipZ)
        )

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
        let count = points.count / 3
        guard count >= minimumPoints, discCells > 0 else {
            result.miss = "only \(count) points around the nose tip"
            return result
        }
        behind.sort()
        let relief = Double(behind[behind.count / 2])
        let coverage = Double(coveredCells) / Double(discCells)
        let numbers = String(format: "relief %.1f cm, coverage %.2f, %d points", relief * 100, coverage, count)
        guard reliefRange.contains(relief) else {
            result.miss = "not face shaped: " + numbers
            return result
        }
        guard coverage >= minimumCoverage else {
            result.miss = "too little surface around the nose tip: " + numbers
            return result
        }
        result.face = DepthFace(
            nosePoint: CGPoint(x: tipColumn / Double(width), y: tipRow / Double(height)),
            noseMeters: Double(tipZ), points: points, relief: relief, coverage: coverage
        )
        return result
    }

    /// The nose tip among `pixels`: the centroid of the pixels within
    /// `noseDepthMeters` of their robust nearest, and within
    /// `tipRadiusMeters` of it sideways.
    private static func nearestTip(
        _ pixels: [(column: Int, row: Int, z: Float)], focal: Float
    ) -> (column: Double, row: Double, z: Float)? {
        guard !pixels.isEmpty else { return nil }
        let sorted = pixels.sorted { $0.z < $1.z }
        let nearest = sorted[Int(Double(sorted.count - 1) * nearestFraction)]
        let tipPixels = Double(tipRadiusMeters * focal / nearest.z)
        var sumColumn = 0.0
        var sumRow = 0.0
        var depths: [Float] = []
        for pixel in sorted {
            guard pixel.z <= nearest.z + noseDepthMeters else { break }
            let dx = Double(pixel.column - nearest.column)
            let dy = Double(pixel.row - nearest.row)
            guard dx * dx + dy * dy <= tipPixels * tipPixels else { continue }
            sumColumn += Double(pixel.column)
            sumRow += Double(pixel.row)
            depths.append(pixel.z)
        }
        guard !depths.isEmpty else { return nil }
        return (sumColumn / Double(depths.count), sumRow / Double(depths.count), depths[depths.count / 2])
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
