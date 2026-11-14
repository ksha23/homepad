import CoreGraphics
import Foundation

/// A palm raised toward the iPad, found in a depth map (`DepthPalmDetector`).
struct DepthPalm: Equatable, Sendable {
    /// Center in the native depth map, normalized with a top-left origin.
    var center: CGPoint
    /// The hand's median depth, in meters.
    var meters: Double
    /// Its long and short sides, and its area, measured at its depth.
    var length: Double
    var width: Double
    var area: Double
    /// Share of its outline with nothing within `DepthPalmDetector.separation` behind it.
    var clearance: Double
}

/// Finds a raised palm in a TrueDepth depth map: a hand-sized surface clearly
/// in front of everything around it. Camera hand pose was unreliable: it
/// missed hands in dim light and took hands resting anywhere in view. Depth
/// needs no light and measures how far the hand is from what is behind it.
///
/// Surfaces are taken nearest first, on a map of about `columns` columns.
/// Each grows from its nearest point over neighbors at most `maximumStep`
/// apart and at most `handDepth` behind that point. A palm turned to the iPad
/// is nearly flat, so the surface ends at the wrist instead of running down
/// the arm. It is a palm when it is:
/// - within `range`,
/// - hand-sized: `areas`, `lengths` and `widths`, measured at its depth,
/// - clearly in front: on at least `minimumClearance` of its outline, what
///   lies just outside is missing or at least `separation` farther. A face
///   never is, since the head goes on around it, and neither is a hand
///   resting on a table.
/// - clearly in front of the person: at least `separation` nearer than the
///   head depth follows, when it follows one. A hand held up beside the head
///   has only the room behind it, and is not a gesture.
enum DepthPalmDetector {
    static let columns = 160
    static let range: ClosedRange<Float> = 0.15...1.2
    static let handDepth: Float = 0.06
    static let maximumStep: Float = 0.03
    static let separation: Float = 0.15
    static let minimumClearance = 0.6
    static let areas: ClosedRange<Double> = 0.005...0.035
    static let lengths: ClosedRange<Double> = 0.10...0.26
    static let widths: ClosedRange<Double> = 0.05...0.22
    /// Surfaces looked at, nearest first. Specks of a few cells do not count.
    static let maximumSurfaces = 4
    static let minimumCells = 6

    struct Result: Equatable, Sendable {
        var palm: DepthPalm?
        /// With no palm, the nearest surface looked at and why it was not one.
        var nearest: DepthPalm?
        var miss: String?

        /// "at 0.42m, 18 by 11 cm, 0.014 m², 85% of its outline clear: palm", for the debug view.
        var details: String {
            guard let shape = palm ?? nearest else { return miss ?? "none" }
            let text = String(format: "at %.2fm, %.0f by %.0f cm, %.3f m², %.0f%% of its outline clear",
                              shape.meters, shape.length * 100, shape.width * 100, shape.area, shape.clearance * 100)
            return text + ": " + (palm != nil ? "palm" : miss ?? "?")
        }

        /// The same for the trace.
        var description: String { "depth hand " + details }
    }

    /// `headMeters` is the depth of the followed person's head, if any.
    static func detect(in full: DepthMap, headMeters: Double?) -> Result {
        let map = full.downsampled(step: full.step(toColumns: columns))
        let focal = map.focalLengthOrDefault
        var order = map.meters.indices.filter { range.contains(map.meters[$0]) }
        guard !order.isEmpty else { return Result(miss: "nothing within reach") }
        order.sort { map.meters[$0] < map.meters[$1] }

        var taken = [Bool](repeating: false, count: map.meters.count)
        var nearest: (shape: DepthPalm, miss: String)?
        var surfaces = 0
        for seed in order where !taken[seed] {
            let cells = grow(from: seed, in: map, taken: &taken)
            guard cells.count >= minimumCells else { continue }
            let (shape, miss) = measure(cells, in: map, focal: focal, headMeters: headMeters)
            guard let miss else { return Result(palm: shape) }
            if nearest == nil { nearest = (shape, miss) }
            surfaces += 1
            if surfaces >= maximumSurfaces { break }
        }
        guard let nearest else { return Result(miss: "only specks within reach") }
        return Result(nearest: nearest.shape, miss: nearest.miss)
    }

    /// The surface around `seed`: neighbors at most `maximumStep` apart, at
    /// most `handDepth` behind the seed. Marks its cells taken.
    private static func grow(from seed: Int, in map: DepthMap, taken: inout [Bool]) -> [Int] {
        let limit = map.meters[seed] + handDepth
        var cells = [seed]
        taken[seed] = true
        var next = 0
        while next < cells.count {
            let cell = cells[next]
            next += 1
            let depth = map.meters[cell]
            for neighbor in neighbors(of: cell, in: map) where !taken[neighbor] {
                let other = map.meters[neighbor]
                // Missing depth (NaN) fails both comparisons.
                guard other <= limit, abs(other - depth) <= maximumStep else { continue }
                taken[neighbor] = true
                cells.append(neighbor)
            }
        }
        return cells
    }

    /// The surface's size, shape and clearance, and why it is not a palm (nil when it is).
    private static func measure(_ cells: [Int], in map: DepthMap, focal: Double, headMeters: Double?) -> (DepthPalm, String?) {
        let depths = cells.map { map.meters[$0] }.sorted()
        let depth = depths[depths.count / 2]
        let cellMeters = Double(depth) / focal
        let count = Double(cells.count)

        // Center, and the spread along the surface's own axes. A uniform strip
        // L long has a variance of L² / 12 along it.
        let points = cells.map { (x: Double($0 % map.width), y: Double($0 / map.width)) }
        let meanX = points.reduce(0) { $0 + $1.x } / count
        let meanY = points.reduce(0) { $0 + $1.y } / count
        var xx = 0.0, yy = 0.0, xy = 0.0
        for point in points {
            let dx = point.x - meanX
            let dy = point.y - meanY
            xx += dx * dx
            yy += dy * dy
            xy += dx * dy
        }
        xx /= count
        yy /= count
        xy /= count
        let middle = (xx + yy) / 2
        let half = ((xx - yy) * (xx - yy) / 4 + xy * xy).squareRoot()
        let length = (12 * (middle + half)).squareRoot() * cellMeters
        let width = (12 * max(0, middle - half)).squareRoot() * cellMeters

        // The cells just outside: clear when depth is missing there (the edge
        // of something in front casts a gap) or at least `separation` farther.
        // Past the edge of the map is not clear: the hand is cut off.
        var inside = [Bool](repeating: false, count: map.meters.count)
        for cell in cells { inside[cell] = true }
        var seen = [Bool](repeating: false, count: map.meters.count)
        var outline = 0
        var clear = 0
        for cell in cells {
            let column = cell % map.width
            let row = cell / map.width
            if column == 0 || row == 0 || column == map.width - 1 || row == map.height - 1 { outline += 1 }
            for neighbor in neighbors(of: cell, in: map) where !inside[neighbor] && !seen[neighbor] {
                seen[neighbor] = true
                outline += 1
                let other = map.meters[neighbor]
                if other.isNaN || other >= depth + separation { clear += 1 }
            }
        }

        let palm = DepthPalm(
            center: CGPoint(x: (meanX + 0.5) / Double(map.width), y: (meanY + 0.5) / Double(map.height)),
            meters: Double(depth), length: length, width: width, area: count * cellMeters * cellMeters,
            clearance: outline > 0 ? Double(clear) / Double(outline) : 0
        )
        if !areas.contains(palm.area) { return (palm, palm.area < areas.lowerBound ? "too small for a hand" : "too large for a hand") }
        if !lengths.contains(length) || !widths.contains(width) { return (palm, "not hand shaped") }
        if palm.clearance < minimumClearance { return (palm, "not clearly in front of what is behind it") }
        if let headMeters, palm.meters > headMeters - Double(separation) {
            return (palm, String(format: "not clearly in front of the head at %.2fm", headMeters))
        }
        return (palm, nil)
    }

    private static func neighbors(of cell: Int, in map: DepthMap) -> [Int] {
        let column = cell % map.width
        let row = cell / map.width
        var result: [Int] = []
        result.reserveCapacity(4)
        if column > 0 { result.append(cell - 1) }
        if column < map.width - 1 { result.append(cell + 1) }
        if row > 0 { result.append(cell - map.width) }
        if row < map.height - 1 { result.append(cell + map.width) }
        return result
    }
}
