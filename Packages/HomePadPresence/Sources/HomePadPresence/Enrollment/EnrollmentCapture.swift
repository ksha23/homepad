@preconcurrency import AVFoundation
import Foundation

/// A source of enrollment frames: the real front camera, or a scripted one
/// in the simulator.
@MainActor
protocol EnrollmentCapture: AnyObject {
    /// Session and device for the live preview, nil when simulated.
    var previewSession: AVCaptureSession? { get }
    var previewDevice: AVCaptureDevice? { get }
    /// True on TrueDepth iPads, where every sample must pass the depth liveness check.
    var requiresLiveness: Bool { get }
    /// Feature print revision recorded with the template.
    var featurePrintRevision: Int { get }

    func start(
        onObservation: @escaping @MainActor (EnrollmentObservation) -> Void,
        failed: @escaping @MainActor (String) -> Void
    )
    func stop()
}

/// A scripted person who follows the instructions, for the simulator.
/// Produces synthetic embeddings around the member's stable identity vector.
@MainActor
final class SimulatedEnrollmentCapture: EnrollmentCapture {
    let previewSession: AVCaptureSession? = nil
    let previewDevice: AVCaptureDevice? = nil
    let requiresLiveness = false
    let featurePrintRevision = 0
    /// The step the person is asked to do, set by the session.
    var currentStep: (() -> EnrollmentStep?)?

    private let identity: [Float]
    private var task: Task<Void, Never>?
    private var frame: UInt64 = 0

    init(memberID: UUID) {
        identity = SyntheticFace.identity(for: memberID)
    }

    func start(
        onObservation: @escaping @MainActor (EnrollmentObservation) -> Void,
        failed: @escaping @MainActor (String) -> Void
    ) {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                guard let self else { return }
                onObservation(self.nextObservation())
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func nextObservation() -> EnrollmentObservation {
        frame += 1
        let step = currentStep?() ?? .center
        let pose = Self.pose(for: step, frame: frame)
        let radians = Double.pi / 180
        let sample = FaceEmbeddingSample(
            embedding: SyntheticFace.sample(around: identity, noise: 0.04, seed: frame),
            liveness: nil, yaw: pose.yaw * radians, pitch: pose.pitch * radians
        )
        return EnrollmentObservation(
            faceCount: 1, faceWidth: step.distance == .far ? 0.15 : 0.3, yaw: sample.yaw, pitch: sample.pitch,
            sample: sample, time: Double(frame) * 0.35
        )
    }

    /// A pose for the step, in degrees, that sweeps back and forth a few
    /// degrees per frame like a person turning slowly, so samples spread over
    /// the range.
    nonisolated static func pose(for step: EnrollmentStep, frame: UInt64) -> (yaw: Double, pitch: Double) {
        let phase = Double([0, 1, 2, 3, 2, 1][Int(frame % 6)])
        switch step {
        case .center, .sitBack: return (0, 0)
        case .sideA: return (16 + phase * 6, 0)
        case .sideB: return (-16 - phase * 6, 0)
        case .chinUp: return (phase * 5 - 7, -12)
        case .chinDown: return (phase * 5 - 7, 12)
        case .sitBackTurn: return (10 + phase * 7, 0)
        }
    }
}
