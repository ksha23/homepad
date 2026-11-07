import Foundation
import HomePadCore

/// Produces scripted readings in the simulator so the rest of the pipeline
/// (fusion, events, recognition voting, diagnostics) runs without a camera.
@MainActor
final class SimulatedBackend: SensingBackend {
    let kind = BackendKind.simulated
    private let script: SimulatedPresenceScript
    /// Returns the enrolled identity the simulated visitor should match, if any.
    var recognitionTarget: (() -> [Float]?)?
    private var task: Task<Void, Never>?
    private var interval: TimeInterval = 0.5
    private let startedAt = Date()
    private var sampleCount: UInt64 = 0
    /// The scripted visitor's face track, like ARKit's: one face without a break.
    private var continuity = FaceTrackContinuity()
    private let visitorAnchor = UUID()

    init(script: SimulatedPresenceScript) {
        self.script = script
    }

    func start(
        framesPerSecond: Double,
        deliver: @escaping @MainActor (FrameAnalysis) -> Void,
        failed: @escaping @MainActor (String) -> Void
    ) {
        setFrameRate(framesPerSecond)
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                deliver(self.makeAnalysis())
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    func setFrameRate(_ framesPerSecond: Double) {
        // A few readings per second is plenty to drive the UI.
        interval = 1 / min(max(framesPerSecond, 0.5), 4)
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func makeAnalysis() -> FrameAnalysis {
        let now = Date()
        let elapsed = now.timeIntervalSince(startedAt)
        let observation = script.observation(at: elapsed, now: now)
        let visitor = FaceTrackContinuity.TrackedFace(anchor: visitorAnchor, position: .zero)
        let trackID = continuity.update(tracked: Array(repeating: visitor, count: observation.faces.count), at: elapsed)
        var embedding: FaceEmbeddingSample?
        if let nearest = observation.faces.first, (nearest.distanceMeters ?? .infinity) < 1.6,
           let identity = recognitionTarget?() {
            sampleCount += 1
            let vector = SyntheticFace.sample(around: identity, noise: 0.04, seed: sampleCount)
            embedding = FaceEmbeddingSample(
                embedding: vector, liveness: LivenessResult(isLive: true, reliefMeters: 0.03, validFraction: 0.9),
                trackID: trackID, visibleFaces: observation.faces.count
            )
        }
        return FrameAnalysis(
            observation: observation, embedding: embedding, handGesture: nil,
            framesPerSecond: 1 / interval, backend: .simulated, faceTrackID: trackID
        )
    }
}
