import CoreGraphics
import CoreVideo
import Foundation

/// Where the liveness grid goes: over the middle of the face, in the depth map.
///
/// Vision finds the face in the upright image. The box is turned back into
/// the native image buffer (`SensorFrame.nativeRect`), then into the depth map
/// (`DepthRegistration`). The second step is what used to be missing: the
/// depth map was read at the image's normalized coordinates, which is only
/// right when both cover the same view. ARKit's face tracking image is 16:9
/// and its depth map can be 4:3, so a face away from the middle of the image
/// had its grid read off to one side, partly beside the face. Against a dark
/// room with no depth behind the face it read flat. Against a near wall it
/// read the face and the wall together, a relief of a meter.
extension DepthLiveness {
    /// The grid covers the middle 70 percent of the face box, away from the
    /// background.
    static let innerFraction = 0.7
    /// Samples across and down the grid.
    static let gridSize = 9
    /// A face turned at least this far, in degrees, that reads flat is unsure,
    /// not a spoof. The side of a turned head is close to flat: in the
    /// 11-inch iPad's traces, real faces read flat on 1.5
    /// percent of samples facing the iPad, 8 percent at 15 to 29 degrees, 25
    /// percent at 30 to 44, 46 to 49 percent at 45 to 89 and 98 percent past 90.
    static let turnedDegrees = 30.0

    /// Checks the face in `faceBox` (normalized, bottom-left origin, in the
    /// upright image) against the depth map of the same frame. `yaw` is
    /// Vision's head yaw in radians.
    static func evaluate(faceBox: CGRect, in frame: SensorFrame, depth: DepthMap, yaw: Double? = nil) -> LivenessResult {
        let rect = depthRect(for: faceBox, in: frame, depth: depth)
        var result = evaluate(samples: depth.samples(in: rect, columns: gridSize, rows: gridSize), columns: gridSize)
        let degrees = yaw.map { abs($0) * 180 / .pi } ?? 0
        if !result.isLive, result.unsure == nil, degrees >= turnedDegrees {
            result.unsure = .turned(degrees: Int(degrees.rounded()))
        }
        return result
    }

    /// The middle of the face box as a normalized rect (bottom-left origin) in
    /// the depth map. `registration` replaces the map's own, for the
    /// alignment check in the trace.
    static func depthRect(
        for faceBox: CGRect, in frame: SensorFrame, depth: DepthMap, registration: DepthRegistration? = nil
    ) -> CGRect {
        let inset = (1 - innerFraction) / 2
        let inner = faceBox.insetBy(dx: faceBox.width * inset, dy: faceBox.height * inset)
        let native = frame.nativeRect(fromUpright: inner)
        return (registration ?? Self.registration(of: depth, for: frame)).depthRect(fromImageBottomLeft: native)
    }

    /// The map's registration, or, when it has none, the image matched to it
    /// by aspect ratio (AVCapture depth matches its video one to one).
    static func registration(of depth: DepthMap, for frame: SensorFrame) -> DepthRegistration {
        if let registration = depth.registration { return registration }
        let image = CGSize(width: CVPixelBufferGetWidth(frame.pixelBuffer), height: CVPixelBufferGetHeight(frame.pixelBuffer))
        return DepthRegistration(imageSize: image, depthSize: CGSize(width: depth.width, height: depth.height))
    }
}

/// For the presence trace only: when a face fails the liveness check, reads
/// the grid through other mappings too, to tell a flat face from a grid that
/// was not on the face. Prints only valid fractions, reliefs and distances.
enum LivenessAlignmentCheck {
    static func describe(faceBox: CGRect, in frame: SensorFrame, depth: DepthMap, faceMeters: Double?) -> String {
        let registered = DepthLiveness.registration(of: depth, for: frame)
        let candidates: [(String, DepthRegistration)] = [
            ("registered", registered),
            ("one to one", .identity),
            ("mirrored across", mirroredAcross(registered)),
            ("mirrored up-down", mirroredUpDown(registered)),
        ]
        let parts = candidates.map { name, registration in
            let rect = DepthLiveness.depthRect(for: faceBox, in: frame, depth: depth, registration: registration)
            let grid = depth.samples(in: rect, columns: DepthLiveness.gridSize, rows: DepthLiveness.gridSize)
            let result = DepthLiveness.evaluate(samples: grid, columns: DepthLiveness.gridSize)
            return "\(name) valid \(format(result.validFraction)) relief \(Int((result.reliefMeters * 1000).rounded()))mm"
                + " at \(result.distanceMeters.map { format($0) + "m" } ?? "-")"
        }
        return "liveness grid check: " + parts.joined(separator: ", ") + ", face \(faceMeters.map { format($0) + "m" } ?? "-")"
    }

    /// The same registration with the depth map read right to left.
    private static func mirroredAcross(_ registration: DepthRegistration) -> DepthRegistration {
        var mirrored = registration
        mirrored.scaleX = -registration.scaleX
        mirrored.offsetX = 1 - registration.offsetX
        return mirrored
    }

    /// The same registration with the depth map read bottom to top.
    private static func mirroredUpDown(_ registration: DepthRegistration) -> DepthRegistration {
        var mirrored = registration
        mirrored.scaleY = -registration.scaleY
        mirrored.offsetY = 1 - registration.offsetY
        return mirrored
    }

    private static func format(_ value: Double) -> String { String(format: "%.2f", value) }
}
