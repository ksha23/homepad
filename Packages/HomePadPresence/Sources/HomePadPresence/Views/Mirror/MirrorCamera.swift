@preconcurrency import AVFoundation
import HomePadCore
import Observation

/// Drives the Mirror app's front camera. Claims the camera through
/// `services.capture` (so the presence sensor yields) and releases it on close.
@MainActor
@Observable
final class MirrorCamera {
    enum State: Equatable {
        case idle
        /// Show a friendly explanation before the system prompt.
        case needsPermission
        case denied
        /// Cameras are off by the privacy switch or another feature has one.
        case blocked
        /// No front camera (the simulator).
        case noCamera
        case running
    }

    private(set) var state: State = .idle
    /// True when the front camera runs Center Stage, so Mirror offers Close-Up and Full Body.
    private(set) var supportsCenterStage = false
    @ObservationIgnored let camera = CameraSession(outputQueue: DispatchQueue(label: "com.homepad.presence.mirror"))
    @ObservationIgnored private(set) var device: AVCaptureDevice?
    @ObservationIgnored private weak var services: AppServices?
    /// Follows Center Stage turned on or off in Control Center.
    @ObservationIgnored private var centerStageObservation: NSKeyValueObservation?
    /// Bumped on every open and close, so a slow open cannot start the camera after a close.
    @ObservationIgnored private var openGeneration = 0
    static let owner = "presence.mirror"

    /// Opens the camera, or reports why it cannot.
    func open(services: AppServices, framing: MirrorFraming) {
        self.services = services
        guard let device = CameraSession.device(for: .front) else {
            state = .noCamera
            #if DEBUG
            // `-PresenceMirrorCenterStage YES` shows Close-Up and Full Body in the simulator.
            supportsCenterStage = UserDefaults.standard.bool(forKey: "PresenceMirrorCenterStage")
            #endif
            return
        }
        switch CameraPermission.status {
        case .undetermined:
            state = .needsPermission
            return
        case .denied:
            state = .denied
            return
        case .granted:
            break
        }
        guard services.settings[CoreSettings.cameraEnabled] else {
            state = .blocked
            return
        }
        self.device = device
        openGeneration += 1
        let generation = openGeneration
        Task { [weak self] in
            guard let self else { return }
            // The presence sensor needs a moment to close the camera before ours can open.
            let claimed = await services.capture.claimWhenReady(Self.owner, camera: .front)
            guard generation == self.openGeneration else {
                if claimed { services.capture.release(Self.owner) }
                return
            }
            guard claimed else {
                self.state = .blocked
                return
            }
            self.startCamera(services: services, framing: framing)
        }
    }

    private func startCamera(services: AppServices, framing: MirrorFraming) {
        let configuration = CameraSession.Configuration(camera: .front, preset: .high, deliversFrames: false)
        camera.start(configuration) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.state = .running
                self.prepareFraming(framing)
            case .failure:
                self.state = .noCamera
                services.capture.release(Self.owner)
            }
        }
    }

    /// Asks for camera access after the user tapped Continue, then opens.
    func requestAccess(services: AppServices, framing: MirrorFraming) async {
        _ = await CameraPermission.request()
        open(services: services, framing: framing)
    }

    /// Uses Center Stage where the camera has it, or a fixed zoom where it does not.
    private func prepareFraming(_ framing: MirrorFraming) {
        guard let device, MirrorCenterStage.isSupported(by: device) else {
            camera.setZoom(framing.zoom)
            return
        }
        let generation = openGeneration
        camera.preferCenterStageFormat { [weak self] isSupported in
            guard let self, generation == self.openGeneration, self.state == .running else { return }
            self.supportsCenterStage = isSupported
            self.setFraming(framing)
            if isSupported { self.followControlCenter(device) }
        }
    }

    func setFraming(_ framing: MirrorFraming) {
        guard supportsCenterStage, device != nil else {
            camera.setZoom(framing.zoom)
            return
        }
        MirrorCenterStage.apply(framing)
        camera.setZoom(1)
    }

    /// In cooperative mode the person can turn Center Stage on or off in
    /// Control Center. The Mirror's switch follows.
    private func followControlCenter(_ device: AVCaptureDevice) {
        centerStageObservation = device.observe(\.isCenterStageActive, options: [.new]) { [weak self] device, _ in
            let isActive = device.isCenterStageActive
            Task { @MainActor in
                guard let self, self.state == .running, let settings = self.services?.settings else { return }
                let framing: MirrorFraming = isActive ? .closeUp : .wide
                if settings[PresenceSettings.mirrorFraming] != framing { settings[PresenceSettings.mirrorFraming] = framing }
            }
        }
    }

    func close(services: AppServices) {
        openGeneration += 1
        // Stop following before the camera stops, which turns Center Stage off.
        centerStageObservation?.invalidate()
        centerStageObservation = nil
        if supportsCenterStage, device != nil { MirrorCenterStage.release() }
        camera.stop()
        services.capture.release(Self.owner)
        if state == .running { state = .idle }
    }
}
