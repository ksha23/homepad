import Foundation
import simd

/// A face signature's surface as a height map over the plane facing the
/// camera: for each cell of a grid around the nose tip, how far behind it the
/// face lies. Another face is lined up with it by `DepthAlignment`.
struct DepthSurface {
    /// 3.75 mm cells over the 18 cm across a signature reaches.
    static let cells = 48
    let radius: Float
    let cellSize: Float
    /// Row-major, row 0 at the top (y most negative). NaN where no point fell.
    let heights: [Float]

    /// From signature points (x, y, z triples), within `radius` of the nose tip.
    init(points: [Float], radius: Float) {
        let count = Self.cells
        self.radius = radius
        cellSize = 2 * radius / Float(count)
        var sums = [Float](repeating: 0, count: count * count)
        var hits = [Int](repeating: 0, count: count * count)
        for index in stride(from: 0, to: points.count - 2, by: 3) {
            let x = (points[index] + radius) / cellSize
            let y = (points[index + 1] + radius) / cellSize
            guard x >= 0, x < Float(count), y >= 0, y < Float(count), points[index + 2].isFinite else { continue }
            let column = Int(x)
            let row = Int(y)
            sums[row * count + column] += points[index + 2]
            hits[row * count + column] += 1
        }
        let heights = (0..<count * count).map { hits[$0] > 0 ? sums[$0] / Float(hits[$0]) : Float.nan }
        self.heights = Self.filled(heights, count: count)
    }

    /// The height and slope at (x, y), bilinear between the four cells around
    /// it. Nil off the surface.
    func sample(x: Float, y: Float) -> (z: Float, dzdx: Float, dzdy: Float)? {
        let count = Self.cells
        let fx = (x + radius) / cellSize - 0.5
        let fy = (y + radius) / cellSize - 0.5
        guard fx >= 0, fy >= 0, fx < Float(count - 1), fy < Float(count - 1) else { return nil }
        let column = Int(fx)
        let row = Int(fy)
        let tx = fx - Float(column)
        let ty = fy - Float(row)
        let z00 = heights[row * count + column]
        let z10 = heights[row * count + column + 1]
        let z01 = heights[(row + 1) * count + column]
        let z11 = heights[(row + 1) * count + column + 1]
        guard z00.isFinite, z10.isFinite, z01.isFinite, z11.isFinite else { return nil }
        let z = z00 * (1 - tx) * (1 - ty) + z10 * tx * (1 - ty) + z01 * (1 - tx) * ty + z11 * tx * ty
        let dzdx = ((z10 - z00) * (1 - ty) + (z11 - z01) * ty) / cellSize
        let dzdy = ((z01 - z00) * (1 - tx) + (z11 - z10) * tx) / cellSize
        return (z, dzdx, dzdy)
    }

    /// Fills each empty cell with three or more filled neighbors with their
    /// mean, so the gaps between grid points of a far face do not break it.
    private static func filled(_ heights: [Float], count: Int) -> [Float] {
        var result = heights
        for row in 0..<count {
            for column in 0..<count where !heights[row * count + column].isFinite {
                var sum: Float = 0
                var found = 0
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let r = row + dy
                        let c = column + dx
                        guard r >= 0, r < count, c >= 0, c < count else { continue }
                        let value = heights[r * count + c]
                        if value.isFinite {
                            sum += value
                            found += 1
                        }
                    }
                }
                if found >= 3 { result[row * count + column] = sum / Float(found) }
            }
        }
        return result
    }
}

/// Lines one face's points up with another face's surface and says how far
/// apart they still are.
///
/// Both start with their nose tips together. Each round matches every point
/// to the surface straight behind or in front of it, keeps the closest
/// `alignedFraction` (so an open mouth or a strand of hair does not pull the
/// faces apart), and solves for the small turn and shift that bring those
/// closer to the surface's tangent planes (point to plane alignment). What is
/// left is the root mean square of the closest `comparedFraction` of those
/// distances, in millimeters. It keeps more than the alignment uses: trimming
/// as much would leave out the nose, which sets faces apart most.
enum DepthAlignment {
    struct Result: Equatable {
        var rmsMillimeters: Double
        /// Share of the points that landed on the surface.
        var overlap: Double
        /// How far the points had to turn.
        var rotationDegrees: Double
    }

    static let iterations = 12
    static let alignedFraction = 0.7
    static let comparedFraction = 0.85
    /// Points that must land on the surface, or the faces do not compare.
    static let minimumOverlap = 0.6
    /// A face turned further than this from the other does not compare.
    static let maximumRotationDegrees = 30.0
    /// Points used at most, every so many of the signature's.
    static let maximumProbePoints = 350
    static let maximumTurnPerRound: Float = 0.1
    static let maximumShiftPerRound: Float = 0.01

    static func align(_ points: [Float], to surface: DepthSurface) -> Result? {
        let total = points.count / 3
        guard total >= 10 else { return nil }
        let every = max(1, (total + maximumProbePoints - 1) / maximumProbePoints)
        var probe: [SIMD3<Float>] = []
        probe.reserveCapacity(total / every + 1)
        for index in stride(from: 0, to: total, by: every) {
            probe.append(SIMD3(points[index * 3], points[index * 3 + 1], points[index * 3 + 2]))
        }
        var rotation = matrix_identity_float3x3
        var translation = SIMD3<Float>(repeating: 0)
        for _ in 0..<iterations {
            let matched = matches(probe, rotation: rotation, translation: translation, surface: surface)
            guard Double(matched.count) >= minimumOverlap * Double(probe.count) else { return nil }
            guard var step = solveStep(trimmed(matched, keeping: alignedFraction)) else { break }
            // One round turns at most 6 degrees and moves at most 1 cm, so a
            // poorly conditioned round cannot throw the face away.
            let turnLength = simd_length(step.omega)
            if turnLength > maximumTurnPerRound { step.omega *= maximumTurnPerRound / turnLength }
            let shiftLength = simd_length(step.shift)
            if shiftLength > maximumShiftPerRound { step.shift *= maximumShiftPerRound / shiftLength }
            let turn = rotationMatrix(step.omega)
            rotation = turn * rotation
            translation = turn * translation + step.shift
            if simd_length(step.omega) < 1e-4 && simd_length(step.shift) < 1e-5 { break }
        }
        let matched = matches(probe, rotation: rotation, translation: translation, surface: surface)
        let overlap = Double(matched.count) / Double(probe.count)
        guard overlap >= minimumOverlap else { return nil }
        let cosine = Double((rotation[0][0] + rotation[1][1] + rotation[2][2] - 1) / 2)
        let degrees = acos(min(max(cosine, -1), 1)) * 180 / .pi
        guard degrees <= maximumRotationDegrees else { return nil }
        let kept = trimmed(matched, keeping: comparedFraction)
        let squares = kept.reduce(0.0) { $0 + Double($1.residual * $1.residual) }
        let rms = (squares / Double(max(1, kept.count))).squareRoot()
        return Result(rmsMillimeters: rms * 1000, overlap: overlap, rotationDegrees: degrees)
    }

    private struct Match {
        var point: SIMD3<Float>
        var normal: SIMD3<Float>
        /// Distance to the surface's tangent plane along its normal, in meters.
        var residual: Float
    }

    private static func matches(
        _ probe: [SIMD3<Float>], rotation: simd_float3x3, translation: SIMD3<Float>, surface: DepthSurface
    ) -> [Match] {
        var result: [Match] = []
        result.reserveCapacity(probe.count)
        for point in probe {
            let moved = rotation * point + translation
            guard let sample = surface.sample(x: moved.x, y: moved.y) else { continue }
            let normal = simd_normalize(SIMD3<Float>(-sample.dzdx, -sample.dzdy, 1))
            result.append(Match(point: moved, normal: normal, residual: (moved.z - sample.z) * normal.z))
        }
        return result
    }

    private static func trimmed(_ matches: [Match], keeping fraction: Double) -> [Match] {
        let sorted = matches.sorted { abs($0.residual) < abs($1.residual) }
        return Array(sorted.prefix(max(1, Int(Double(sorted.count) * fraction))))
    }

    /// The small turn (a rotation vector) and shift that best bring the
    /// points onto their tangent planes, by least squares.
    private static func solveStep(_ matches: [Match]) -> (omega: SIMD3<Float>, shift: SIMD3<Float>)? {
        var turnTurn = simd_double3x3()
        var turnShift = simd_double3x3()
        var shiftShift = simd_double3x3()
        var turnSide = SIMD3<Double>(repeating: 0)
        var shiftSide = SIMD3<Double>(repeating: 0)
        for match in matches {
            let normal = SIMD3<Double>(match.normal)
            let lever = simd_cross(SIMD3<Double>(match.point), normal)
            let residual = Double(match.residual)
            turnTurn += outer(lever, lever)
            turnShift += outer(lever, normal)
            shiftShift += outer(normal, normal)
            turnSide += lever * residual
            shiftSide += normal * residual
        }
        // The six normal equations, [A B; Bᵀ C] x = -[turnSide; shiftSide].
        var system = [Double](repeating: 0, count: 42)
        for row in 0..<3 {
            for column in 0..<3 {
                system[row * 7 + column] = turnTurn[column][row]
                system[row * 7 + column + 3] = turnShift[column][row]
                system[(row + 3) * 7 + column] = turnShift[row][column]
                system[(row + 3) * 7 + column + 3] = shiftShift[column][row]
            }
            system[row * 7 + 6] = -turnSide[row]
            system[(row + 3) * 7 + 6] = -shiftSide[row]
        }
        guard let x = solve(&system, size: 6) else { return nil }
        return (SIMD3<Float>(Float(x[0]), Float(x[1]), Float(x[2])), SIMD3<Float>(Float(x[3]), Float(x[4]), Float(x[5])))
    }

    /// a bᵀ.
    private static func outer(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> simd_double3x3 {
        simd_double3x3(columns: (a * b.x, a * b.y, a * b.z))
    }

    /// Gaussian elimination with partial pivoting on an augmented
    /// `size` x (`size` + 1) matrix. Nil when it is singular.
    private static func solve(_ system: inout [Double], size: Int) -> [Double]? {
        let width = size + 1
        for pivot in 0..<size {
            var best = pivot
            for row in pivot + 1..<size where abs(system[row * width + pivot]) > abs(system[best * width + pivot]) {
                best = row
            }
            guard abs(system[best * width + pivot]) > 1e-12 else { return nil }
            if best != pivot {
                for column in 0..<width { system.swapAt(pivot * width + column, best * width + column) }
            }
            for row in pivot + 1..<size {
                let factor = system[row * width + pivot] / system[pivot * width + pivot]
                guard factor != 0 else { continue }
                for column in pivot..<width { system[row * width + column] -= factor * system[pivot * width + column] }
            }
        }
        var x = [Double](repeating: 0, count: size)
        for row in stride(from: size - 1, through: 0, by: -1) {
            var sum = system[row * width + size]
            for column in row + 1..<size { sum -= system[row * width + column] * x[column] }
            x[row] = sum / system[row * width + row]
        }
        return x
    }

    /// The rotation by a rotation vector (axis times angle), Rodrigues' formula.
    private static func rotationMatrix(_ omega: SIMD3<Float>) -> simd_float3x3 {
        let angle = simd_length(omega)
        guard angle > 1e-9 else { return matrix_identity_float3x3 }
        let axis = omega / angle
        let k = simd_float3x3(columns: (
            SIMD3(0, axis.z, -axis.y), SIMD3(-axis.z, 0, axis.x), SIMD3(axis.y, -axis.x, 0)
        ))
        return matrix_identity_float3x3 + sin(angle) * k + (1 - cos(angle)) * (k * k)
    }
}
