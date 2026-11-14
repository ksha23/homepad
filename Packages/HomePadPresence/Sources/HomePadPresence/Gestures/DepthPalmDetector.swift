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
/// apart and at most `handDepth` behind that point: a palm turned to the iPad
/// is nearly flat. It is a palm when it is:
/// - within `range`,
/// - the size of a hand, or of a hand on an upright forearm, which lies in the
///   same plane: `areas`, `lengths` and `widths`, measured at its depth,
/// - clearly closer than everything else: nothing in view lies within
///   `separation` (just over a foot) behind it, except the arm it is on:
///   surface joined to it with no step over `maximumStep`, no larger than
///   `maximumArmArea`. Kyle's rule. A hand beside the head, or less than a
///   foot in front of the face, has the head within reach behind it, and an
///   arm joined to a body within reach does not excuse the body. At 15 cm,
///   thin surfaces a few centimeters in front of the body counted.
/// - standing out from what lies right around it: on at least
///   `minimumClearance` of its outline, depth is missing or at least
///   `separation` farther. A face never does, since the head goes on around
///   it, and the arm joins only at the wrist.
enum DepthPalmDetector {
    static let columns = 160
    static let range: ClosedRange<Float> = 0.15...1.2
    static let handDepth: Float = 0.06
    static let maximumStep: Float = 0.03
    static let separation: Float = 0.31
    /// The most surface an arm joined to the hand covers (forearm and upper arm).
    static let maximumArmArea = 0.06
    static let minimumClearance = 0.6
    static let areas: ClosedRange<Double> = 0.005...0.05
    static let lengths: ClosedRange<Double> = 0.10...0.5
    static let widths: ClosedRange<Double> = 0.05...0.22
    /// Something else counts once it covers this many cells, so specks of
    /// noise at the hand's edge do not.
    static let minimumOtherCells = 25
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

    static func detect(in full: DepthMap) -> Result {
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
            let (shape, miss) = measure(cells, in: map, focal: focal)
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
    private static func measure(_ cells: [Int], in map: DepthMap, focal: Double) -> (DepthPalm, String?) {
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
        switch nearestOther(than: cells, inside: inside, depth: depth, in: map, focal: focal) {
        case .clear: break
        case .something(let meters):
            return (palm, String(format: "something else within %.0f cm behind it, at %.2fm", separation * 100, meters))
        case .joinedToBody:
            return (palm, String(format: "joined to more than an arm within %.0f cm behind it", separation * 100))
        }
        if palm.clearance < minimumClearance { return (palm, "not standing out from what is around it") }
        return (palm, nil)
    }

    private enum Behind {
        case clear
        /// The nearest depth of something within reach.
        case something(Double)
        /// What is joined to the hand within reach is larger than an arm.
        case joinedToBody
    }

    /// What lies within `separation` behind the surface at `depth`, other
    /// than the surface and the arm it is on.
    private static func nearestOther(than cells: [Int], inside: [Bool], depth: Float, in map: DepthMap, focal: Double) -> Behind {
        let zone = depth + separation
        // The arm: surface joined to the hand with no step over `maximumStep`, until it is `separation` behind.
        var joined = inside
        var queue = cells
        var next = 0
        var armArea = 0.0
        while next < queue.count {
            let cell = queue[next]
            next += 1
            for neighbor in neighbors(of: cell, in: map) where !joined[neighbor] {
                let other = map.meters[neighbor]
                guard other < zone, abs(other - map.meters[cell]) <= maximumStep else { continue }
                joined[neighbor] = true
                queue.append(neighbor)
                let side = Double(other) / focal
                armArea += side * side
            }
        }
        if armArea > maximumArmArea { return .joinedToBody }
        // Everything else within the zone, in patches big enough to be something.
        var seen = joined
        var nearest: Float?
        for start in map.meters.indices where !seen[start] && range.contains(map.meters[start]) && map.meters[start] < zone {
            seen[start] = true
            var patch = [start]
            var index = 0
            var patchNearest = map.meters[start]
            while index < patch.count {
                let cell = patch[index]
                index += 1
                for neighbor in neighbors(of: cell, in: map) where !seen[neighbor] {
                    let other = map.meters[neighbor]
                    guard range.contains(other), other < zone else { continue }
                    seen[neighbor] = true
                    patch.append(neighbor)
                    patchNearest = min(patchNearest, other)
                }
            }
            if patch.count >= minimumOtherCells { nearest = min(nearest ?? patchNearest, patchNearest) }
        }
        return nearest.map { .something(Double($0)) } ?? .clear
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
