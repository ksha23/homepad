@preconcurrency import AVFoundation
import HomePadCore

/// The real camera: one `AVCaptureSession` with a BGRA video data output,
/// rotated upright, capped at 15 frames per second to stay cool when it runs for hours.
@MainActor
final class LiveCameraSession: FrameProducer {
    let hub = FrameHub()
    let session = AVCaptureSession()
    let isDemo = false
    private(set) var position: CameraPosition?
    private(set) var device: AVCaptureDevice?
    var onStatusChange: ((FeedStatus) -> Void)?

    private let sessionQueue = DispatchQueue(label: "cameralab.session")
    private let videoQueue = DispatchQueue(label: "cameralab.video", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let sampleDelegate: SampleBufferForwarder
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private let log = Log.make("CameraLab.Camera")

    init() {
        sampleDelegate = SampleBufferForwarder(hub: hub)
        observeSession()
    }

    /// The wide camera at a position, or nil when the device has none (the simulator).
    static func device(for position: CameraPosition) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position.avPosition)
    }

    func start(position: CameraPosition) {
        guard let device = Self.device(for: position) else {
            onStatusChange?(.failed("This iPad has no \(position.title.lowercased())."))
            return
        }
        if self.position == position, session.isRunning { return }
        self.position = position
        self.device = device
        onStatusChange?(.starting)
        let session = session, output = output, delegate = sampleDelegate, videoQueue = videoQueue
        sessionQueue.async { [weak self] in
            let problem = Self.configure(session: session, output: output, device: device, delegate: delegate, queue: videoQueue)
            if problem == nil, !session.isRunning { session.startRunning() }
            let running = session.isRunning
            Task { @MainActor in
                guard let self else { return }
                if let problem {
                    self.onStatusChange?(.failed(problem))
                    return
                }
                self.attachRotation(to: device)
                self.onStatusChange?(running ? .running : .failed("The camera did not start."))
            }
        }
    }

    func stop() {
        position = nil
        device = nil
        rotationObservation = nil
        rotationCoordinator = nil
        hub.reset()
        let session = session
        sessionQueue.async { session.stopRunning() }
        onStatusChange?(.stopped)
    }

    // MARK: Configuration

    private nonisolated static func configure(
        session: AVCaptureSession, output: AVCaptureVideoDataOutput, device: AVCaptureDevice,
        delegate: SampleBufferForwarder, queue: DispatchQueue
    ) -> String? {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        for input in session.inputs { session.removeInput(input) }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            return "Could not open the camera."
        }
        session.addInput(input)
        if !session.outputs.contains(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(delegate, queue: queue)
            guard session.canAddOutput(output) else { return "Could not read camera frames." }
            session.addOutput(output)
        }
        if (try? device.lockForConfiguration()) != nil {
            let frameDuration = CMTime(value: 1, timescale: 15)
            let supports15 = device.activeFormat.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 15 }
            if supports15 { device.activeVideoMinFrameDuration = frameDuration }
            device.unlockForConfiguration()
        }
        return nil
    }

    /// Keeps output frames horizon-level as the iPad rotates.
    private func attachRotation(to device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            Task { @MainActor in self?.applyRotation(angle) }
        }
    }

    private func applyRotation(_ angle: CGFloat) {
        let output = output
        sessionQueue.async {
            guard let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int).flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
            MainActor.assumeIsolated { self?.onStatusChange?(.interrupted(Self.describe(reason))) }
        })
        notificationTokens.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onStatusChange?(.running) }
        })
        notificationTokens.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            MainActor.assumeIsolated {
                self?.log.error("Capture runtime error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                self?.onStatusChange?(.failed(error?.localizedDescription ?? "The camera stopped unexpectedly."))
            }
        })
    }

    private static func describe(_ reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .videoDeviceNotAvailableInBackground: "Paused while HomePad is in the background."
        case .videoDeviceInUseByAnotherClient: "Another app is using the camera."
        case .videoDeviceNotAvailableWithMultipleForegroundApps: "Paused while another app shares the screen."
        case .videoDeviceNotAvailableDueToSystemPressure: "Paused because the iPad is too warm."
        default: "The camera is paused."
        }
    }
}

/// Bridges `AVCaptureVideoDataOutput` callbacks into the frame hub.
private final class SampleBufferForwarder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let hub: FrameHub

    init(hub: FrameHub) {
        self.hub = hub
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        hub.deliver(CameraFrame(pixelBuffer: pixelBuffer, capturedAt: Date(), isDemo: false))
    }
}
