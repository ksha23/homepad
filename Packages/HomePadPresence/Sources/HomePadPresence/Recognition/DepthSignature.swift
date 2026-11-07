import Foundation
import simd

/// The shape of a face from ARKit's face mesh, for depth identity.
/// Evaluation only: it never decides who someone is (README, "Depth identity").
///
/// ARKit fits its face mesh to the TrueDepth depth of the face. The mesh is in
/// the face's own coordinates and in meters, so it does not change with where
/// the head is or how it is turned, and it works in the dark. Whether it tells
/// household members apart well enough is not known yet, which is what the
/// evaluation in the trace measures.
///
/// Every third vertex is kept, as ARKit gives it. Centering them again would
/// let a smile shift every vertex a little. Expressions move the mouth, brows
/// and cheeks, so a signature is only taken from a face near its resting
/// expression, and comparing two leaves out the vertices that moved most.
///
/// This is face data. It stays in memory and in the protected template folder
/// (`FaceTemplateStore`), never in a trace, a log or anywhere off the iPad.
struct DepthSignature: Codable, Equatable, Sendable {
    /// Every this many vertices of the mesh is kept.
    static let vertexStride = 3
    /// ARKit expression coefficients (blend shapes, the eyes left out) above
    /// this change the mesh too much for a signature.
    static let maximumExpression = 0.35
    /// The share of vertices compared: the ones closest between the two.
    static let comparedFraction = 0.7

    /// x, y and z of each kept vertex, in meters, in face coordinates.
    var points: [Float]

    init(points: [Float]) {
        self.points = points
    }

    /// From the vertices of an ARKit face mesh, in face coordinates.
    init?(vertices: [SIMD3<Float>]) {
        let kept = stride(from: 0, to: vertices.count, by: Self.vertexStride).map { vertices[$0] }
        guard kept.count >= 10 else { return nil }
        var points: [Float] = []
        points.reserveCapacity(kept.count * 3)
        for vertex in kept {
            points.append(contentsOf: [vertex.x, vertex.y, vertex.z])
        }
        self.points = points
    }

    /// How far apart two signatures are: the root mean square distance between
    /// matching vertices, over the closest `comparedFraction` of them, in
    /// millimeters. Nil when the meshes do not match.
    func distance(to other: DepthSignature) -> Double? {
        guard points.count == other.points.count, points.count >= 3 else { return nil }
        var squared: [Float] = []
        squared.reserveCapacity(points.count / 3)
        for index in stride(from: 0, to: points.count - 2, by: 3) {
            let dx = points[index] - other.points[index]
            let dy = points[index + 1] - other.points[index + 1]
            let dz = points[index + 2] - other.points[index + 2]
            squared.append(dx * dx + dy * dy + dz * dz)
        }
        squared.sort()
        let count = max(1, Int(Double(squared.count) * Self.comparedFraction))
        let mean = squared.prefix(count).reduce(0, +) / Float(count)
        return Double(mean.squareRoot()) * 1000
    }
}

/// A depth signature taken while RGB recognition had confirmed the member.
struct DepthTemplate: Codable, Equatable, Sendable {
    var signature: DepthSignature
    var learnedAt: Date
}

/// One member's depth templates, oldest first. Stored next to the face
/// templates, with the same protection (`FaceTemplateStore`).
struct MemberDepthTemplates: Codable, Equatable, Sendable {
    var memberID: UUID
    var templates: [DepthTemplate]

    /// Adds a template, dropping the oldest ones beyond `cap`.
    mutating func append(_ template: DepthTemplate, cap: Int) {
        templates.append(template)
        if templates.count > cap { templates.removeFirst(templates.count - cap) }
    }
}
