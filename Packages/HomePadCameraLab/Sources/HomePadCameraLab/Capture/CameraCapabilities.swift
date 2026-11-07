import AVFoundation
import RoomPlan
import VisionKit

/// What this iPad's cameras can do. The hub shows these as chips and tools
/// use them to pick a live experience or a demo.
struct CameraCapabilities: Equatable {
    var hasBackCamera: Bool
    var hasFrontCamera: Bool
    var hasLiDAR: Bool
    var supportsRoomPlan: Bool
    var supportsMultiCamera: Bool
    var supportsLiveScanner: Bool
    var supportsDocumentCamera: Bool

    /// Probes the hardware. Cheap, but call once and keep the result.
    @MainActor
    static func detect() -> CameraCapabilities {
        CameraCapabilities(
            hasBackCamera: LiveCameraSession.device(for: .back) != nil,
            hasFrontCamera: LiveCameraSession.device(for: .front) != nil,
            hasLiDAR: AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil,
            supportsRoomPlan: RoomCaptureSession.isSupported,
            supportsMultiCamera: AVCaptureMultiCamSession.isMultiCamSupported,
            supportsLiveScanner: DataScannerViewController.isSupported,
            supportsDocumentCamera: VNDocumentCameraViewController.isSupported
        )
    }

    /// True in the simulator, where demo feeds and demo content stand in.
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
