import Foundation
import simd

/// Decides whether someone is looking at the screen.
enum GazeMath {
    /// Radius around the camera, in meters, that counts as "the screen". The
    /// camera sits on the bezel, so this covers the whole display plus a margin.
    static let screenRadiusMeters: Float = 0.3

    /// TrueDepth path. `face` is the face position and `gazeTarget` the ARKit
    /// `lookAtPoint`, both in camera space (camera at the origin looking down -Z,
    /// display roughly in the z = 0 plane). Casts the gaze ray onto that plane.
    static func isLookingAtScreen(face: SIMD3<Float>, gazeTarget: SIMD3<Float>, radius: Float = screenRadiusMeters) -> Bool {
        let direction = gazeTarget - face
        // The face is in front of the camera (negative z), so a gaze toward the
        // screen must move toward z = 0.
        guard face.z < 0, direction.z > 1e-4 else { return false }
        let t = -face.z / direction.z
        let hit = face + t * direction
        return simd_length(SIMD2(hit.x, hit.y)) <= radius
    }

    /// RGB path. A face turned toward the camera (small yaw and pitch, in
    /// radians) is treated as looking at the screen.
    static func isFacingScreen(yaw: Double?, pitch: Double?, limitDegrees: Double = 22) -> Bool {
        guard let yaw else { return false }
        let limit = limitDegrees * .pi / 180
        return abs(yaw) <= limit && abs(pitch ?? 0) <= limit
    }
}
