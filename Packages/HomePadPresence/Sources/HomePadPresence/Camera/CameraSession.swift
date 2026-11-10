@preconcurrency import AVFoundation
import HomePadCore
import ImageIO

/// Which front camera to open.
enum CameraChoice: Sendable {
    /// The Face ID camera, which can also stream infrared depth.
    case trueDepth
    /// The regular front camera (ultra wide on recent iPads).
    case front
}

/// One AVCaptureSession wrapper reused by presence scanning, face enrollment
/// and the Mirror app: device choice, frame rate, optional frame and depth
/// delivery, zoom and a session for preview layers.
final class CameraSession: NSObject, @unchecked Sendable {
    struct Configuration: Equatable, Sendable {
        var camera: CameraChoice
        var preset: AVCaptureSession.Preset = .vga640x480
        /// Nil keeps the device default.
        var framesPerSecond: Double?
        var deliversFrames = true
        var deliversDepth = false
    }

    enum Failure: Error {
        case noDevice
        case configurationFailed
    }

    let session = AVCaptureSession()
    /// Called on the output queue for each video frame.
    var onFrame: ((SensorFrame) -> Void)?
    /// Called on the output queue for each depth map, with its capture time and
    /// the video's horizontal field of view in degrees (depth matches the video).
    var onDepth: ((AVDepthData, TimeInterval, Double?) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.homepad.presence.camera-session")
    private let outputQueue: DispatchQueue
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let stateLock = NSLock()
    private var device: AVCaptureDevice?
    private var source: PresenceSource = .frontCamera
    private var fieldOfView: Double?
    private var orientation: OrientationTracker?
    private let log = Log.make("PresenceCamera")

    init(outputQueue: DispatchQueue) {
        self.outputQueue = outputQueue
        super.init()
    }

    static func device(for camera: CameraChoice) -> AVCaptureDevice? {
        switch camera {
        case .trueDepth:
            AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
        case .front:
            AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .front
            ).devices.first
        }
    }

    /// Configures and starts the session. Completion runs on the main actor.
    @MainActor
    func start(_ configuration: Configuration, completion: @escaping @MainActor (Result<Void, Failure>) -> Void) {
        guard let device = Self.device(for: configuration.camera) else {
            completion(.failure(.noDevice))
            return
        }
        let tracker = OrientationTracker(device: device)
        sessionQueue.async { [self] in
            let ok = configure(device: device, configuration: configuration)
            stateLock.withLock {
                self.device = device
                self.orientation = tracker
                self.source = configuration.camera == .trueDepth ? .trueDepth : .frontCamera
                self.fieldOfView = Double(device.activeFormat.videoFieldOfView)
            }
            if ok, let fps = configuration.framesPerSecond { applyFrameRate(fps, to: device) }
            if ok { session.startRunning() }
            DispatchQueue.main.async { completion(ok ? .success(()) : .failure(.configurationFailed)) }
        }
    }

    func setFrameRate(_ fps: Double) {
        sessionQueue.async { [self] in
            guard let device = stateLock.withLock({ self.device }) else { return }
            applyFrameRate(fps, to: device)
        }
    }

    /// Zoom relative to the widest view: 1 is widest, 2 is a close-up.
    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [self] in
            guard let device = stateLock.withLock({ self.device }), (try? device.lockForConfiguration()) != nil else { return }
            let base = device.minAvailableVideoZoomFactor
            device.videoZoomFactor = min(max(base * factor, base), device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        }
    }

    /// Moves the running camera to a format that supports Center Stage when
    /// the current one does not, then reports whether the format supports it.
    func preferCenterStageFormat(completion: @escaping @MainActor (Bool) -> Void) {
        sessionQueue.async { [self] in
            guard let device = stateLock.withLock({ self.device }) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            if !device.activeFormat.isCenterStageSupported, let format = Self.centerStageFormat(of: device),
               (try? device.lockForConfiguration()) != nil {
                device.activeFormat = format
                device.unlockForConfiguration()
            }
            let isSupported = device.activeFormat.isCenterStageSupported
            DispatchQueue.main.async { completion(isSupported) }
        }
    }

    /// The largest Center Stage format up to 1920 pixels wide, enough for a full screen preview.
    private static func centerStageFormat(of device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = device.formats.filter(\.isCenterStageSupported)
        let width = { (format: AVCaptureDevice.Format) in CMVideoFormatDescriptionGetDimensions(format.formatDescription).width }
        return formats.filter { width($0) <= 1920 }.max { width($0) < width($1) } ?? formats.first
    }

    func stop(completion: (@MainActor () -> Void)? = nil) {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            if let completion { Task { @MainActor in completion() } }
        }
    }

    // MARK: Configuration

    private func configure(device: AVCaptureDevice, configuration: Configuration) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            log.error("Cannot add camera input")
            return false
        }
        session.addInput(input)
        if session.canSetSessionPreset(configuration.preset) { session.sessionPreset = configuration.preset }

        if configuration.deliversFrames {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
            guard session.canAddOutput(videoOutput) else { return false }
            session.addOutput(videoOutput)
        }
        if configuration.deliversDepth, configuration.camera == .trueDepth {
            addDepthOutput(device: device)
        }
        return true
    }

    private func addDepthOutput(device: AVCaptureDevice) {
        guard session.canAddOutput(depthOutput) else { return }
        session.addOutput(depthOutput)
        depthOutput.isFilteringEnabled = true
        depthOutput.alwaysDiscardsLateDepthData = true
        depthOutput.setDelegate(self, callbackQueue: outputQueue)
        // The smallest float depth format is plenty for motion and liveness.
        let formats = device.activeFormat.supportedDepthDataFormats.filter {
            let type = CMFormatDescriptionGetMediaSubType($0.formatDescription)
            return type == kCVPixelFormatType_DepthFloat16 || type == kCVPixelFormatType_DepthFloat32
        }
        let smallest = formats.min {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width
                < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        }
        if let smallest, (try? device.lockForConfiguration()) != nil {
            device.activeDepthDataFormat = smallest
            device.unlockForConfiguration()
        }
    }

    private func applyFrameRate(_ fps: Double, to device: AVCaptureDevice) {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard let low = ranges.map(\.minFrameRate).min(), let high = ranges.map(\.maxFrameRate).max(),
              (try? device.lockForConfiguration()) != nil else { return }
        let clamped = min(max(fps, low), high)
        let duration = CMTime(value: 1000, timescale: CMTimeScale(clamped * 1000))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let onFrame, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let (source, fov, tracker) = stateLock.withLock { (self.source, self.fieldOfView, self.orientation) }
        // The TrueDepth session's BrightnessValue never moves from the camera's
        // starting value (283 lux, in a dark room too), and its exposure time
        // and ISO read 8,640 lux in a 1 lux room, so it reports no light.
        let frame = SensorFrame(
            pixelBuffer: pixelBuffer,
            orientation: tracker?.orientation ?? .up,
            timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds,
            source: source,
            horizontalFOVDegrees: fov,
            brightnessValue: source == .trueDepth ? nil : Self.brightnessValue(sampleBuffer)
        )
        onFrame(frame)
    }

    func depthDataOutput(
        _ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
        timestamp: CMTime, connection: AVCaptureConnection
    ) {
        let fieldOfView = stateLock.withLock { self.fieldOfView }
        onDepth?(depthData, timestamp.seconds, fieldOfView)
    }

    /// EXIF BrightnessValue (APEX) from the frame's metadata attachments.
    static func brightnessValue(_ sampleBuffer: CMSampleBuffer) -> Double? {
        guard let exif = CMGetAttachment(sampleBuffer, key: kCGImagePropertyExifDictionary, attachmentModeOut: nil) as? NSDictionary else {
            return nil
        }
        return (exif[kCGImagePropertyExifBrightnessValue] as? NSNumber)?.doubleValue
    }
}
