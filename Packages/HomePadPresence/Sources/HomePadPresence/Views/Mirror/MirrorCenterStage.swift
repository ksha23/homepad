@preconcurrency import AVFoundation

/// Center Stage for the Mirror's Close-Up and Full Body.
///
/// Center Stage is an app-wide switch on `AVCaptureDevice`, so the Mirror
/// takes it while open, in cooperative mode so Control Center's Center Stage
/// toggle still works, and gives it back on close switched off under the
/// app's control. Presence sensing judges distance from a face's size in a
/// fixed view, which Center Stage's moving crop would break.
@MainActor
enum MirrorCenterStage {
    /// True when some format of the camera supports Center Stage.
    static func isSupported(by device: AVCaptureDevice) -> Bool {
        device.formats.contains(where: \.isCenterStageSupported)
    }

    static func apply(_ framing: MirrorFraming) {
        AVCaptureDevice.centerStageControlMode = .cooperative
        AVCaptureDevice.isCenterStageEnabled = framing.usesCenterStage
    }

    /// Off, and out of Control Center's reach, for every camera after the Mirror.
    static func release() {
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false
    }
}
