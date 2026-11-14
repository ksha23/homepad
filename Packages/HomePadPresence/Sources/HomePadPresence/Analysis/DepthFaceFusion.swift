import Foundation
import simd

/// Several depth faces of one person, taken within about a second, lined up
/// with the newest and merged into one face.
///
/// iOS does not smooth the depth HomePad gets, so what looks smooth is the
/// dot projector itself: a face at half a meter falls on a few thousand dots,
/// each measured with some noise. Depth arrives about 15 times a second, and
/// a person sitting still moves only a little between maps, so lining a
/// handful up and averaging them keeps the face's shape and lowers the noise.
enum DepthFaceFusion {
    /// 3 mm cells over the 18 cm a face reaches across.
    static let cells = 60
    /// Faces merged at least, and at most: each but the newest costs a
    /// line-up on the analysis queue, for every signature.
    static let minimumFaces = 3
    static let maximumFaces = 4

    /// The merged face's points (`DepthFace.points`): one per grid cell that
    /// any face fell in, the mean of what fell there. Faces that do not line
    /// up with the newest (moved or turned too far) are left out. Nil when
    /// fewer than `minimumFaces` remain.
    static func fuse(_ faces: [DepthFace]) -> [Float]? {
        guard let newest = faces.last else { return nil }
        let radius = Float(DepthFaceFinder.radiusMeters)
        let surface = DepthSurface(points: newest.points, radius: radius)
        let cellSize = 2 * radius / Float(cells)
        var sums = [SIMD3<Float>](repeating: .zero, count: cells * cells)
        var hits = [Int](repeating: 0, count: cells * cells)
        var merged = 0

        func add(_ points: [Float], rotation: simd_float3x3, translation: SIMD3<Float>) {
            for index in stride(from: 0, to: points.count - 2, by: 3) {
                let point = rotation * SIMD3(points[index], points[index + 1], points[index + 2]) + translation
                let x = (point.x + radius) / cellSize
                let y = (point.y + radius) / cellSize
                guard x >= 0, x < Float(cells), y >= 0, y < Float(cells), point.z.isFinite else { continue }
                let cell = Int(y) * cells + Int(x)
                sums[cell] += point
                hits[cell] += 1
            }
            merged += 1
        }

        add(newest.points, rotation: matrix_identity_float3x3, translation: .zero)
        for face in faces.dropLast() {
            guard let fit = DepthAlignment.align(face.points, to: surface) else { continue }
            add(face.points, rotation: fit.rotation, translation: fit.translation)
        }
        guard merged >= minimumFaces else { return nil }
        var points: [Float] = []
        points.reserveCapacity(cells * cells * 3)
        for cell in 0..<(cells * cells) where hits[cell] > 0 {
            let mean = sums[cell] / Float(hits[cell])
            guard simd_length(mean) <= radius else { continue }
            points.append(contentsOf: [mean.x, mean.y, mean.z])
        }
        return points.count / 3 >= DepthFaceFinder.minimumPoints ? points : nil
    }
}
