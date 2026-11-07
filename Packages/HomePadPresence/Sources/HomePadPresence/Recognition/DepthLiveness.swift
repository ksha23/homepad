import Foundation

/// The result of a depth liveness check on one face.
struct LivenessResult: Equatable, Sendable {
    /// True when the face has real 3D relief.
    var isLive: Bool
    /// Spread of depth around the best-fit plane of the face's own surface, in meters.
    var reliefMeters: Double
    /// Share of grid samples that had valid depth.
    var validFraction: Double
    /// Median depth of the face's own surface, in meters, when any sample had depth.
    var distanceMeters: Double? = nil
    /// Share of grid samples on the face's own surface (`DepthLiveness.faceSurface`).
    var faceFraction = 1.0
    /// Set when the depth cannot tell a face from a photo. The sample then
    /// neither votes for a match nor counts as a spoof: it is skipped.
    var unsure: LivenessUnsure? = nil
}

/// Why a liveness check could not decide.
enum LivenessUnsure: Equatable, Sendable {
    /// Too little of the grid had depth.
    case sparse
    /// No one surface covered enough of the grid: it was not on the face.
    case noSurface
    /// It read flat, but the face is turned this many degrees, and the side
    /// of a turned head is close to flat.
    case turned(degrees: Int)

    /// For the presence trace.
    var description: String {
        switch self {
        case .sparse: "too little depth"
        case .noSurface: "not on one surface"
        case .turned(let degrees): "turned \(degrees) degrees"
        }
    }

    var isTurned: Bool {
        if case .turned = self { return true }
        return false
    }
}

/// Tells a real face from a photo or a screen using TrueDepth depth.
///
/// A photo or tablet is flat even when tilted, so after fitting a plane the
/// depth barely varies. A real face has a nose 2 to 4 cm in front of the
/// cheeks. The check fits a plane by least squares to the face's own surface
/// in a grid of depth samples over the face box, and measures the spread of
/// what is left.
///
/// Only the face's own surface counts: the nearest run of depths, in depth
/// order, with no step of more than `surfaceGapMeters`, that covers at least
/// `minimumFaceFraction` of the grid. A grid that also caught the wall behind
/// a face used to read a meter of relief and pass, and a photo in front of a
/// farther wall would have passed the same way. A smaller nearer run, such as
/// a hand, is passed over.
enum DepthLiveness {
    /// Minimum relief (10th to 90th percentile of plane residuals) for a live face.
    static let minimumReliefMeters = 0.012
    /// Ignore checks where too little of the face had depth.
    static let minimumValidFraction = 0.5
    /// A step this deep between two depths, in depth order, ends a surface.
    /// A face's own depths run on without one, its background does not.
    static let surfaceGapMeters = 0.04
    /// Share of the grid the face's own surface must cover.
    static let minimumFaceFraction = 0.4

    /// - Parameters:
    ///   - samples: row-major depth grid in meters over the face box. NaN, zero or
    ///     negative values are treated as missing.
    ///   - columns: grid width. Rows are `samples.count / columns`.
    static func evaluate(samples: [Float], columns: Int) -> LivenessResult {
        guard columns > 0, samples.count >= columns * 2 else {
            return LivenessResult(isLive: false, reliefMeters: 0, validFraction: 0)
        }
        let rows = samples.count / columns
        var points: [(x: Double, y: Double, z: Double)] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let z = samples[row * columns + column]
                guard z.isFinite, z > 0 else { continue }
                points.append((Double(column), Double(row), Double(z)))
            }
        }
        let total = rows * columns
        let validFraction = Double(points.count) / Double(total)
        guard validFraction >= minimumValidFraction else {
            return LivenessResult(
                isLive: false, reliefMeters: 0, validFraction: validFraction,
                distanceMeters: median(points.map(\.z)), faceFraction: 0, unsure: .sparse
            )
        }
        let face = faceSurface(points, gridCount: total)
        let faceFraction = Double(face.count) / Double(total)
        guard face.count >= 6, let plane = fitPlane(face) else {
            return LivenessResult(
                isLive: false, reliefMeters: 0, validFraction: validFraction,
                distanceMeters: median(points.map(\.z)), faceFraction: faceFraction, unsure: .noSurface
            )
        }
        let residuals = face.map { $0.z - (plane.a * $0.x + plane.b * $0.y + plane.c) }.sorted()
        let low = residuals[Int(Double(residuals.count - 1) * 0.1)]
        let high = residuals[Int(Double(residuals.count - 1) * 0.9)]
        let relief = high - low
        return LivenessResult(
            isLive: relief >= minimumReliefMeters, reliefMeters: relief, validFraction: validFraction,
            distanceMeters: median(face.map(\.z)), faceFraction: faceFraction
        )
    }

    /// The face's own surface: the nearest run of depths, in depth order, with
    /// no step of more than `surfaceGapMeters`, that covers at least
    /// `minimumFaceFraction` of the grid. Empty when no run does.
    static func faceSurface(_ points: [(x: Double, y: Double, z: Double)], gridCount: Int) -> [(x: Double, y: Double, z: Double)] {
        let sorted = points.sorted { $0.z < $1.z }
        guard !sorted.isEmpty else { return [] }
        var start = 0
        for index in 1...sorted.count {
            let isLast = index == sorted.count
            let endsRun = isLast || sorted[index].z - sorted[index - 1].z > surfaceGapMeters
            guard endsRun else { continue }
            if Double(index - start) / Double(gridCount) >= minimumFaceFraction {
                return Array(sorted[start..<index])
            }
            start = index
        }
        return []
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    /// Least-squares plane z = a x + b y + c, solved with the 3x3 normal equations.
    private static func fitPlane(_ points: [(x: Double, y: Double, z: Double)]) -> (a: Double, b: Double, c: Double)? {
        var sxx = 0.0, sxy = 0.0, syy = 0.0, sx = 0.0, sy = 0.0
        var sxz = 0.0, syz = 0.0, sz = 0.0
        let n = Double(points.count)
        for p in points {
            sxx += p.x * p.x; sxy += p.x * p.y; syy += p.y * p.y
            sx += p.x; sy += p.y
            sxz += p.x * p.z; syz += p.y * p.z; sz += p.z
        }
        // Solve [sxx sxy sx; sxy syy sy; sx sy n] [a b c]^T = [sxz syz sz]^T by Cramer's rule.
        let det = sxx * (syy * n - sy * sy) - sxy * (sxy * n - sy * sx) + sx * (sxy * sy - syy * sx)
        guard abs(det) > 1e-9 else { return nil }
        let detA = sxz * (syy * n - sy * sy) - sxy * (syz * n - sy * sz) + sx * (syz * sy - syy * sz)
        let detB = sxx * (syz * n - sz * sy) - sxz * (sxy * n - sy * sx) + sx * (sxy * sz - syz * sx)
        let detC = sxx * (syy * sz - sy * syz) - sxy * (sxy * sz - syz * sx) + sxz * (sxy * sy - syy * sx)
        return (detA / det, detB / det, detC / det)
    }
}
