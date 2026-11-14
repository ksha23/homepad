import Foundation

/// The shape of a face from the TrueDepth depth map alone, for depth
/// identity: the dot projector's view of it, which needs no light.
/// Evaluation only: it never decides who someone is (README, "Depth identity").
///
/// It is the face's surface within 9 cm of the nose tip (`DepthFaceFinder`),
/// in meters, the nose tip at the origin and turned upright. Two signatures
/// are compared by lining one up with the other's surface (`DepthAlignment`)
/// and measuring how far apart they still are, so where the head is and a
/// small turn of it do not matter, and the size of the face does.
///
/// It replaced a signature from ARKit's face mesh, which needs ARKit to find
/// the face, and ARKit found none in a dark room.
///
/// This is face data. It stays in memory and in the protected template folder
/// (`FaceTemplateStore`), never in a trace, a log or anywhere off the iPad.
struct DepthSignature: Codable, Equatable, Sendable {
    /// Signatures of another version are not comparable. Version 1, ARKit's
    /// face mesh, had no version field, so its templates no longer load.
    /// Version 2 was a single depth map, often with the nose tip off the
    /// nose; version 3 merges several (`DepthFaceFusion`), but front camera
    /// frames on a short edge were turned upside down. Version 4 is upright.
    static let version = 4
    /// ARKit expression coefficients (blend shapes, the eyes left out) above
    /// this change the face too much for a signature, where ARKit can tell.
    static let maximumExpression = 0.35

    let version: Int
    /// x, y and z of each point, in meters (`DepthFace.points`).
    let points: [Float]

    init(points: [Float]) {
        version = Self.version
        self.points = points
    }

    init(face: DepthFace) {
        self.init(points: face.points)
    }

    private enum CodingKeys: String, CodingKey {
        case version, points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "Depth signature version \(version)")
        }
        points = try container.decode([Float].self, forKey: .points)
    }

    var pointCount: Int { points.count / 3 }

    /// How far apart two signatures are, in millimeters: the root mean square
    /// distance from this face's points to `other`'s surface once lined up,
    /// over the closest `DepthAlignment.comparedFraction` of them. Nil when they
    /// do not overlap enough or one is turned too far from the other.
    func distance(to other: DepthSignature) -> Double? {
        DepthAlignment.align(points, to: DepthSurface(points: other.points, radius: Float(DepthFaceFinder.radiusMeters)))?
            .rmsMillimeters
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
