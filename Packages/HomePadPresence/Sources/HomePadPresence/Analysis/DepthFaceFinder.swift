import CoreGraphics
import Foundation
import ImageIO
import simd

/// A face found in the depth map alone: the dot projector's view of it, with
/// no camera image and no ARKit face.
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

/// Finds the face inside a face box (`DepthFaceDetector`) of a full depth map.
///
/// 1. The face's own surface: what is connected to a point near the box's
///    center at the depth of its middle third, through neighbors with no depth step over
///    `surfaceStepMeters`. A hand in front of the face or the wall behind it
///    is not part of it.
/// 2. The nose tip: the nearest few millimeters of that surface.
/// 3. The face: the surface within `radiusMeters` of the nose tip, turned
///    upright. It must look like a face, falling away behind the nose
///    (`reliefRange`) and covering most of the disc around it
///    (`minimumCoverage`). A flat photo, a wall or a chair back does not.
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
    /// away behind the 9 cm reach. A face looking a little down read 0.54.
    static let minimumCoverage = 0.5
    static let coverageRadiusMeters = 0.05
    /// Depth step between neighbors, in meters, that ends a surface.
    static let surfaceStepMeters: Float = 0.025
    /// Neighbors are this many pixels apart when following the surface.
    static let surfaceStride = 2
    /// Seeds for the surface: up to this many points nearest the box's
    /// center, within `seedDepthMeters` of the box's depth. One seed alone
    /// often sat on a stray pixel of hair or an edge.
    static let seedAttempts = 8
    static let seedDepthMeters: Float = 0.08
    /// The nose tip: the pixels within `noseDepthMeters` of the surface's
    /// nearest (its `nearestFraction` percentile, so a stray pixel does not
    /// count), within `tipRadiusMeters` of it sideways.
    static let nearestFraction = 0.01
    static let noseDepthMeters: Float = 0.005
    static let tipRadiusMeters: Float = 0.03

    /// One search: the face, or why there was none in numbers only, with the
    /// nose tip it tried.
    struct Search: Sendable {
        var face: DepthFace?
        /// The nose tip tried, normalized with a top-left origin.
        var nosePoint: CGPoint?
        /// Why it is not a face, for the trace and the debug view. Nil when it is.
        var miss: String?
    }

    private typealias Pixel = (column: Int, row: Int, z: Float)

    /// `faceBox` is in the native map, normalized with a top-left origin.
    /// `orientation` turns the map upright.
    static func search(in map: DepthMap, faceBox: CGRect, orientation: CGImagePropertyOrientation) -> Search {
        let focal = Float(map.focalLengthOrDefault)
        guard map.width > 0, map.height > 0, focal > 0 else { return Search(miss: "no depth map") }
        let columns = clamp(Int(faceBox.minX * Double(map.width)), map.width)...clamp(Int(faceBox.maxX * Double(map.width)), map.width)
        let rows = clamp(Int(faceBox.minY * Double(map.height)), map.height)...clamp(Int(faceBox.maxY * Double(map.height)), map.height)

        let surface = faceSurface(in: map, columns: columns, rows: rows)
        guard surface.count >= minimumPoints, let tip = noseTip(of: surface, focal: focal) else {
            return Search(miss: "only \(surface.count) points on the face's surface")
        }
        return face(around: tip, in: map, focal: focal, orientation: orientation)
    }

    /// The largest surface connected to a seed near the box's center at the
    /// depth of its middle third, which is face: the whole box's median was
    /// the wall behind a face that filled less than half of it.
    private static func faceSurface(in map: DepthMap, columns: ClosedRange<Int>, rows: ClosedRange<Int>) -> [Pixel] {
        var pixels: [Pixel] = []
        for row in rows {
            for column in columns {
                let z = map.meters[row * map.width + column]
                if z.isFinite { pixels.append((column, row, z)) }
            }
        }
        let centerColumn = Double(columns.lowerBound + columns.upperBound) / 2
        let centerRow = Double(rows.lowerBound + rows.upperBound) / 2
        let thirdWidth = Double(columns.upperBound - columns.lowerBound) / 6
        let thirdHeight = Double(rows.upperBound - rows.lowerBound) / 6
        let middle = pixels.filter {
            abs(Double($0.column) - centerColumn) <= thirdWidth && abs(Double($0.row) - centerRow) <= thirdHeight
        }
        guard !middle.isEmpty else { return [] }
        let boxDepth = middle.map(\.z).sorted()[middle.count / 2]
        let seeds = pixels
            .filter { abs($0.z - boxDepth) <= seedDepthMeters }
            .sorted { distance($0, centerColumn, centerRow) < distance($1, centerColumn, centerRow) }
            .prefix(seedAttempts)
        var largest: [Pixel] = []
        for seed in seeds {
            let surface = connectedSurface(in: map, from: seed, columns: columns, rows: rows)
            if surface.count > largest.count { largest = surface }
            if largest.count >= minimumPoints * 4 { break }
        }
        return largest
    }

    /// The pixels connected to `seed` within the box: neighbors
    /// `surfaceStride` pixels apart with no depth step over `surfaceStepMeters`.
    private static func connectedSurface(
        in map: DepthMap, from seed: Pixel, columns: ClosedRange<Int>, rows: ClosedRange<Int>
    ) -> [Pixel] {
        let stride = surfaceStride
        let cellColumns = (columns.upperBound - columns.lowerBound) / stride + 1
        let cellRows = (rows.upperBound - rows.lowerBound) / stride + 1
        // Every pixel visited is a whole number of strides from the seed, so
        // its offset from the box's corner, in strides, is its own cell.
        var visited = [Bool](repeating: false, count: cellColumns * cellRows)
        func cell(_ column: Int, _ row: Int) -> Int {
            (row - rows.lowerBound) / stride * cellColumns + (column - columns.lowerBound) / stride
        }
        var surface: [Pixel] = []
        var stack: [Pixel] = [seed]
        visited[cell(seed.column, seed.row)] = true
        while let pixel = stack.popLast() {
            surface.append(pixel)
            for (dx, dy) in [(stride, 0), (-stride, 0), (0, stride), (0, -stride)] {
                let column = pixel.column + dx
                let row = pixel.row + dy
                guard columns.contains(column), rows.contains(row) else { continue }
                let index = cell(column, row)
                guard !visited[index] else { continue }
                let z = map.meters[row * map.width + column]
                guard z.isFinite, abs(z - pixel.z) <= surfaceStepMeters else { continue }
                visited[index] = true
                stack.append((column, row, z))
            }
        }
        return surface
    }

    /// The centroid of the surface's nearest few millimeters around its
    /// robust nearest point, in pixels, and its depth.
    private static func noseTip(of surface: [Pixel], focal: Float) -> (column: Double, row: Double, z: Float)? {
        let sorted = surface.sorted { $0.z < $1.z }
        guard let nearest = sorted.dropFirst(Int(Double(sorted.count - 1) * nearestFraction)).first else { return nil }
        let reach = Double(tipRadiusMeters * focal / nearest.z)
        var sumColumn = 0.0
        var sumRow = 0.0
        var depths: [Float] = []
        for pixel in sorted {
            guard pixel.z <= nearest.z + noseDepthMeters else { break }
            guard distance(pixel, Double(nearest.column), Double(nearest.row)) <= reach * reach else { continue }
            sumColumn += Double(pixel.column)
            sumRow += Double(pixel.row)
            depths.append(pixel.z)
        }
        guard !depths.isEmpty else { return nil }
        return (sumColumn / Double(depths.count), sumRow / Double(depths.count), depths[depths.count / 2])
    }

    /// The surface within `radiusMeters` of the nose tip on an even grid,
    /// turned upright, when it looks like a face.
    private static func face(
        around tip: (column: Double, row: Double, z: Float), in map: DepthMap, focal: Float,
        orientation: CGImagePropertyOrientation
    ) -> Search {
        let nosePoint = CGPoint(x: tip.column / Double(map.width), y: tip.row / Double(map.height))
        let origin = point(column: tip.column, row: tip.row, z: tip.z, map: map, focal: focal)
        let radius = Float(radiusMeters)
        let radiusPixels = Double(radius * focal / tip.z)
        let coveragePixels = Double(Float(coverageRadiusMeters) * focal / tip.z)
        let step = max(1, Int((Double.pi * radiusPixels * radiusPixels / Double(maximumPoints)).squareRoot().rounded(.up)))
        let disc = Int(radiusPixels.rounded(.up))

        var points: [Float] = []
        var behind: [Float] = []
        var discCells = 0
        var coveredCells = 0
        for row in stride(from: Int(tip.row) - disc, through: Int(tip.row) + disc, by: step) {
            for column in stride(from: Int(tip.column) - disc, through: Int(tip.column) + disc, by: step) {
                let lateral = distance((column, row, 0), tip.column, tip.row)
                guard lateral <= radiusPixels * radiusPixels else { continue }
                let inCoverage = lateral <= coveragePixels * coveragePixels
                if inCoverage { discCells += 1 }
                let z = map.depth(column: column, row: row)
                guard z.isFinite else { continue }
                let offset = point(column: Double(column), row: Double(row), z: z, map: map, focal: focal) - origin
                guard simd_length(offset) <= radius else { continue }
                if inCoverage { coveredCells += 1 }
                let upright = uprighted(offset, orientation)
                points.append(contentsOf: [upright.x, upright.y, upright.z])
                behind.append(offset.z)
            }
        }

        let count = points.count / 3
        guard count >= minimumPoints, discCells > 0 else {
            return Search(nosePoint: nosePoint, miss: "only \(count) points around the nose tip")
        }
        behind.sort()
        let relief = Double(behind[behind.count / 2])
        let coverage = Double(coveredCells) / Double(discCells)
        let numbers = String(format: "relief %.1f cm, coverage %.2f, %d points", relief * 100, coverage, count)
        guard reliefRange.contains(relief) else {
            return Search(nosePoint: nosePoint, miss: "not face shaped: " + numbers)
        }
        guard coverage >= minimumCoverage else {
            return Search(nosePoint: nosePoint, miss: "too little surface around the nose tip: " + numbers)
        }
        let face = DepthFace(nosePoint: nosePoint, noseMeters: Double(tip.z), points: points, relief: relief, coverage: coverage)
        return Search(face: face, nosePoint: nosePoint)
    }

    /// The point at a pixel and depth, in meters, with the principal point
    /// taken at the map's center.
    private static func point(column: Double, row: Double, z: Float, map: DepthMap, focal: Float) -> SIMD3<Float> {
        let x = (Float(column) - Float(map.width) / 2) * z / focal
        let y = (Float(row) - Float(map.height) / 2) * z / focal
        return SIMD3(x, y, z)
    }

    /// Turns an offset in the native map the way the map turns to stand
    /// upright, so faces compare whichever way the iPad stands.
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

    /// Squared distance in pixels from a pixel to a point.
    private static func distance(_ pixel: Pixel, _ column: Double, _ row: Double) -> Double {
        let dx = Double(pixel.column) - column
        let dy = Double(pixel.row) - row
        return dx * dx + dy * dy
    }

    private static func clamp(_ value: Int, _ size: Int) -> Int {
        min(max(value, 0), size - 1)
    }
}
