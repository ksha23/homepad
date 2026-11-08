import Foundation
import HomePadCore

/// Owns the running backend and the shared frame analyzer. Switches backends
/// when the duty-cycle mode or the chosen path changes, and only adjusts the
/// frame rate when the same backend keeps running.
@MainActor
final class SensingCoordinator {
    let analyzer = FrameAnalyzer()
    private let queue = DispatchQueue(label: "com.homepad.presence.analysis", qos: .utility)
    /// Models load here, beside the analysis queue (`warmUp`).
    private let warmUpQueue = DispatchQueue(label: "com.homepad.presence.warmup", qos: .utility)
    private let script: SimulatedPresenceScript?
    private let capture: CaptureCoordinator?
    private(set) var backend: (any SensingBackend)?
    /// The backend to start once the previous one has released the camera.
    private var next: (kind: BackendKind, framesPerSecond: Double)?
    /// A stopped backend has not released the camera yet.
    private var isReleasing = false
    /// When the running backend was asked for, until its first frame, for the
    /// presence trace: switching to face tracking is a large part of the time
    /// before someone is recognized.
    private var requestedAt: Date?

    /// Receives every analysis on the main actor.
    var deliver: (@MainActor (FrameAnalysis) -> Void)?
    /// Receives backend failures on the main actor, with the failing kind.
    var failed: (@MainActor (BackendKind, String) -> Void)?
    /// Enrolled identity for the simulated visitor to match.
    var simulatedRecognitionTarget: (() -> [Float]?)?

    init(script: SimulatedPresenceScript?, capture: CaptureCoordinator? = nil) {
        self.script = script
        self.capture = capture
    }

    /// Runs `kind` at the mode's rate, or stops everything when `kind` is nil.
    ///
    /// The next backend starts only once the previous one has released the
    /// camera. ARKit started while AVCapture still held the camera sent its first
    /// frame 10 s late, long enough for presence to lapse right after it was noticed.
    func apply(kind: BackendKind?, mode: SensingMode) {
        guard let kind, let fps = mode.framesPerSecond else {
            stop()
            return
        }
        if let backend, backend.kind == kind {
            backend.setFrameRate(fps)
            return
        }
        if next?.kind != kind {
            requestedAt = Date()
            PresenceTrace.trace.log("backend \(kind.rawValue) requested")
        }
        next = (kind, fps)
        if backend != nil {
            release()
        } else if !isReleasing {
            startNext()
        }
    }

    func stop() {
        next = nil
        requestedAt = nil
        release()
    }

    /// Loads the recognition models before anyone arrives, on a queue of its
    /// own, then reports how long each took on the main actor. On the analysis
    /// queue the load held up the camera's first frame: 73 s on the 11-inch
    /// after a cold boot (1 to 3 s on other launches), with no presence,
    /// distance or recognition until it finished.
    ///
    /// `recognitionReady` runs once the feature print has loaded. With
    /// `detectors`, the analyzer moves its detectors from the CPU to the Neural
    /// Engine after their models have loaded there.
    func warmUp(
        featurePrint: Bool, detectors: Bool, hands: Bool,
        recognitionReady: @escaping @MainActor (TimeInterval) -> Void,
        completion: @escaping @MainActor (RecognitionWarmUp) -> Void
    ) {
        let analyzer = self.analyzer
        let queue = self.queue
        warmUpQueue.async {
            let report = FrameAnalyzer.warmUpModels(featurePrint: featurePrint, detectors: detectors, hands: hands) { seconds in
                Task { @MainActor in recognitionReady(seconds) }
            }
            if detectors { queue.async { analyzer.moveVisionToNeuralEngine() } }
            Task { @MainActor in completion(report) }
        }
    }

    /// Stops the running backend. Once it has let go of the camera, starts the
    /// backend asked for meanwhile, or reports the camera free.
    private func release() {
        guard let stopping = backend else { return }
        backend = nil
        isReleasing = true
        stopping.stop { [weak self] in
            guard let self else { return }
            self.isReleasing = false
            if let requestedAt = self.requestedAt {
                PresenceTrace.trace.log("camera released after \(PresenceTrace.format(Date().timeIntervalSince(requestedAt))) s")
            }
            if self.next != nil {
                self.startNext()
            } else if self.backend?.kind.usesCamera != true {
                self.capture?.setBackgroundSensorUsingCamera(false)
            }
        }
    }

    private func startNext() {
        guard let request = next else { return }
        next = nil
        let kind = request.kind
        let backend = makeBackend(kind)
        self.backend = backend
        if kind.usesCamera { capture?.setBackgroundSensorUsingCamera(true) }
        backend.start(
            framesPerSecond: request.framesPerSecond,
            deliver: { [weak self] analysis in
                // Ignore late frames from a backend that was already replaced.
                guard let self, self.backend?.kind == analysis.backend else { return }
                if let requestedAt = self.requestedAt {
                    self.requestedAt = nil
                    PresenceTrace.trace.log("backend \(kind.rawValue) first frame "
                        + "\(PresenceTrace.format(Date().timeIntervalSince(requestedAt))) s after it was requested")
                }
                self.deliver?(analysis)
            },
            failed: { [weak self] message in self?.failed?(kind, message) }
        )
    }

    private func makeBackend(_ kind: BackendKind) -> any SensingBackend {
        switch kind {
        case .faceTracking:
            return FaceTrackingBackend(analyzer: analyzer, queue: queue)
        case .depthScan, .frontCamera:
            return CaptureBackend(kind: kind, analyzer: analyzer, queue: queue)
        case .simulated:
            let backend = SimulatedBackend(script: script ?? SimulatedPresenceScript(mode: .cycle))
            backend.recognitionTarget = { [weak self] in self?.simulatedRecognitionTarget?() }
            return backend
        }
    }
}
