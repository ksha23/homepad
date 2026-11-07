import CoreGraphics
import Foundation

/// Finds people in the depth stream without needing a face: someone walking
/// past changes the depth of one patch of the scene. Works in the dark because
/// TrueDepth uses its own infrared light.
///
/// Depth noise changes scattered cells, and more of them the farther away the
/// scene is, so only a connected patch counts, and far cells must change more.
struct DepthMotionDetector: Sendable {
    /// Depth change, in meters, that counts as a changed cell up close.
    var changeMeters: Float = 0.15
    /// TrueDepth noise grows with the square of distance: a cell d meters away
    /// must change by this times d squared (0.27 m at 3 m) to count.
    var noisePerSquareMeter: Float = 0.03
    /// Ignore changes beyond this range (TrueDepth gets unreliable past it).
    var maxRangeMeters: Float = 4
    /// Share of the frame the largest connected patch of changed cells must cover.
    var areaFraction: Double = 0.03
    private let columns = 24
    private let rows = 18
    private var previous: [Float]?

    struct Result: Equatable, Sendable {
        var moved: Bool
        /// Nearest cell of the moving patch, a proxy for where the person is.
        var nearestMeters: Double?
        /// Largest moving patch as a share of the frame.
        var blobFraction: Double = 0
        /// Where the nearest cell of the moving patch is, normalized with a
        /// top-left origin, so the person can be followed from there.
        var nearestPoint: CGPoint?
    }

    mutating func process(_ map: DepthMap) -> Result {
        let grid = map.samples(in: CGRect(x: 0, y: 0, width: 1, height: 1), columns: columns, rows: rows)
        defer { previous = grid }
        guard let previous else { return Result(moved: false, nearestMeters: nil) }
        return Self.compare(previous: previous, current: grid, columns: columns, changeMeters: changeMeters,
                            noisePerSquareMeter: noisePerSquareMeter, maxRange: maxRangeMeters, areaFraction: areaFraction)
    }

    mutating func reset() { previous = nil }

    static func compare(previous: [Float], current: [Float], columns: Int, changeMeters: Float,
                        noisePerSquareMeter: Float, maxRange: Float, areaFraction: Double) -> Result {
        guard previous.count == current.count, !current.isEmpty, columns > 0 else { return Result(moved: false, nearestMeters: nil) }
        var changed = [Bool](repeating: false, count: current.count)
        for index in current.indices {
            let old = previous[index]
            let new = current[index]
            guard new.isFinite, new <= maxRange else { continue }
            if old.isFinite {
                let far = max(old, new)
                changed[index] = abs(new - old) >= max(changeMeters, noisePerSquareMeter * far * far)
            } else {
                // A cell that just gained close depth (someone stepped in front of a
                // wall too far to measure) also counts. Far holes flicker, so they do not.
                changed[index] = new < 2.5
            }
        }
        let patch = largestPatch(changed, columns: columns)
        let fraction = Double(patch.count) / Double(current.count)
        let moved = fraction >= areaFraction
        guard moved, let nearest = patch.min(by: { current[$0] < current[$1] }) else {
            return Result(moved: false, nearestMeters: nil, blobFraction: fraction)
        }
        return Result(
            moved: true, nearestMeters: Double(current[nearest]), blobFraction: fraction,
            nearestPoint: point(ofCell: nearest, columns: columns, rows: current.count / columns)
        )
    }

    /// The center of a cell of the sampled grid, whose row 0 is the bottom of
    /// the map, as a normalized point with a top-left origin.
    private static func point(ofCell index: Int, columns: Int, rows: Int) -> CGPoint {
        let column = index % columns
        let rowFromBottom = index / columns
        let x = (Double(column) + 0.5) / Double(columns)
        let y = 1 - (Double(rowFromBottom) + 0.5) / Double(rows)
        return CGPoint(x: x, y: y)
    }

    /// Cells of the largest 4-connected patch of set cells in a row-major mask.
    static func largestPatch(_ mask: [Bool], columns: Int) -> [Int] {
        var seen = [Bool](repeating: false, count: mask.count)
        var largest: [Int] = []
        for start in mask.indices where mask[start] && !seen[start] {
            var patch: [Int] = []
            var stack = [start]
            seen[start] = true
            while let cell = stack.popLast() {
                patch.append(cell)
                let column = cell % columns
                let neighbors = [cell - columns, cell + columns, column > 0 ? cell - 1 : -1, column < columns - 1 ? cell + 1 : -1]
                for next in neighbors where next >= 0 && next < mask.count && mask[next] && !seen[next] {
                    seen[next] = true
                    stack.append(next)
                }
            }
            if patch.count > largest.count { largest = patch }
        }
        return largest
    }
}
