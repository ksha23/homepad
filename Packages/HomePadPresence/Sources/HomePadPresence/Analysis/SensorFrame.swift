@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import HomePadCore

/// One camera frame handed from a backend to the analyzer, on the analysis queue.
/// It is only valid for the duration of the call (the pixel buffer is recycled).
struct SensorFrame: @unchecked Sendable {
    var pixelBuffer: CVPixelBuffer
    /// Rotation that makes the native buffer upright (no mirroring).
    var orientation: CGImagePropertyOrientation
    /// Monotonic capture time in seconds.
    var timestamp: TimeInterval
    var source: PresenceSource
    /// Horizontal field of view across the native buffer width, in degrees.
    var horizontalFOVDegrees: Double?
    /// EXIF BrightnessValue (APEX) from the capture metadata.
    var brightnessValue: Double?
    /// ARKit light estimate, used when EXIF is missing.
    var arkitAmbientIntensity: Double?
    /// Faces already measured by ARKit. Nil means the analyzer runs Vision.
    var trackedFaces: [DetectedFace]?
    /// The unbroken single-face track this frame belongs to (`FaceTrackContinuity`).
    /// Nil unless ARKit tracks exactly one face.
    var faceTrackID: UUID?
    /// How far from resting that face's expression is, the largest ARKit
    /// blend shape with the eyes left out. Nil where ARKit tracks no one face.
    var faceExpression: Double?

    /// Focal length in pixels, from the field of view and native width.
    var focalLengthPixels: Double? {
        horizontalFOVDegrees.flatMap {
            ProximityMath.focalLengthPixels(imageWidth: Double(CVPixelBufferGetWidth(pixelBuffer)), horizontalFOVDegrees: $0)
        }
    }

    /// Size of the upright image in pixels.
    var uprightSize: CGSize {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored: return CGSize(width: height, height: width)
        default: return CGSize(width: width, height: height)
        }
    }

    /// Converts a normalized rect in the upright image back to the native
    /// buffer (both bottom-left origin), for sampling the depth map.
    func nativeRect(fromUpright rect: CGRect) -> CGRect {
        let native = CIImage(cvPixelBuffer: pixelBuffer)
        let transform = native.orientationTransform(for: orientation)
        let uprightExtent = native.extent.applying(transform)
        let pixels = rect.denormalized(in: uprightExtent)
        let nativePixels = pixels.applying(transform.inverted())
        return CGRect(
            x: nativePixels.minX / native.extent.width, y: nativePixels.minY / native.extent.height,
            width: nativePixels.width / native.extent.width, height: nativePixels.height / native.extent.height
        )
    }
}

extension CGRect {
    /// Maps a normalized rect into an absolute rect inside `region`.
    func denormalized(in region: CGRect) -> CGRect {
        CGRect(
            x: region.minX + minX * region.width, y: region.minY + minY * region.height,
            width: width * region.width, height: height * region.height
        )
    }
}
