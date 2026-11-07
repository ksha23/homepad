@preconcurrency import AVFoundation
import ImageIO

/// Follows how a camera's native buffers must be rotated to look upright,
/// using `AVCaptureDevice.RotationCoordinator`. This handles every iPad
/// layout (portrait or landscape front cameras) without hard-coded tables.
///
/// Create it on the main actor. `orientation` may be read from any queue.
final class OrientationTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var angle: CGFloat
    private let coordinator: AVCaptureDevice.RotationCoordinator
    private var observation: NSKeyValueObservation?

    @MainActor
    init(device: AVCaptureDevice) {
        coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        angle = coordinator.videoRotationAngleForHorizonLevelCapture
        observation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] coordinator, _ in
            let value = coordinator.videoRotationAngleForHorizonLevelCapture
            self?.lock.withLock { self?.angle = value }
        }
    }

    /// EXIF orientation that rotates the native buffer upright (never mirrored).
    var orientation: CGImagePropertyOrientation {
        Self.orientation(forRotationAngle: lock.withLock { angle })
    }

    /// Maps a clockwise rotation angle in degrees to the matching EXIF orientation.
    static func orientation(forRotationAngle degrees: CGFloat) -> CGImagePropertyOrientation {
        switch (Int(degrees.rounded()) % 360 + 360) % 360 {
        case 90: .right
        case 180: .down
        case 270: .left
        default: .up
        }
    }
}
