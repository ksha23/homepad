import Foundation

/// AVCapture-based sensing: the RGB front camera with Vision, or the TrueDepth
/// camera with its depth stream for scanning dark rooms.
@MainActor
final class CaptureBackend: SensingBackend {
    let kind: BackendKind
    private let camera: CameraSession
    private let analyzer: FrameAnalyzer
    private let queue: DispatchQueue
    private let throttle = FrameThrottle(framesPerSecond: 2)

    /// - Parameter kind: `.frontCamera` or `.depthScan`.
    init(kind: BackendKind, analyzer: FrameAnalyzer, queue: DispatchQueue) {
        self.kind = kind
        self.analyzer = analyzer
        self.queue = queue
        self.camera = CameraSession(outputQueue: queue)
    }

    func start(
        framesPerSecond: Double,
        deliver: @escaping @MainActor (FrameAnalysis) -> Void,
        failed: @escaping @MainActor (String) -> Void
    ) {
        throttle.setFrameRate(framesPerSecond)
        let analyzer = self.analyzer
        let throttle = self.throttle
        let kind = self.kind
        camera.onFrame = { frame in
            guard throttle.accept(frame.timestamp) else { return }
            let analysis = analyzer.analyze(frame, backend: kind)
            Task { @MainActor in deliver(analysis) }
        }
        camera.onDepth = { depth, time, fieldOfView in
            analyzer.ingestDepth(depth, at: time, horizontalFOVDegrees: fieldOfView)
        }
        queue.async { analyzer.reset() }

        let depth = kind == .depthScan
        let configuration = CameraSession.Configuration(
            camera: depth ? .trueDepth : .front, preset: .vga640x480,
            framesPerSecond: framesPerSecond, deliversFrames: true, deliversDepth: depth
        )
        camera.start(configuration) { result in
            if case .failure(let error) = result { failed("Camera could not start (\(error)).") }
        }
    }

    func setFrameRate(_ framesPerSecond: Double) {
        throttle.setFrameRate(framesPerSecond)
        camera.setFrameRate(framesPerSecond)
    }

    func stop() {
        camera.stop()
    }

    func stop(released: @escaping @MainActor () -> Void) {
        camera.stop(completion: released)
    }
}
