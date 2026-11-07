import Foundation
import HomePadCore
import Observation

/// Guides one household member through face enrollment: five head poses at
/// arm's length and two sitting back, a few samples each, with live hints
/// (`EnrollmentStep`, `EnrollmentSampleFilter`). Holds the camera claim while
/// it runs.
@MainActor
@Observable
final class EnrollmentSession: Identifiable {
    enum Phase: Equatable {
        case ready
        case needsPermission
        case denied
        case unavailable(String)
        case capturing
        case finished
        case failed(String)
    }

    let member: HouseholdMember
    /// Stored so `Identifiable` works from any isolation (sheet presentation).
    nonisolated let id: UUID
    let steps = EnrollmentStep.allCases

    private(set) var phase: Phase = .ready
    private(set) var stepIndex = 0
    private(set) var samplesInStep = 0
    /// Short guidance under the instruction ("Move closer", "Hold still").
    private(set) var hint = ""

    @ObservationIgnored let capture: any EnrollmentCapture
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let recognition: FaceRecognitionService
    @ObservationIgnored private var filter = EnrollmentSampleFilter()
    static let owner = "presence.enrollment"

    init(member: HouseholdMember, services: AppServices, recognition: FaceRecognitionService, capture: any EnrollmentCapture) {
        self.id = member.id
        self.member = member
        self.services = services
        self.recognition = recognition
        self.capture = capture
    }

    var currentStep: EnrollmentStep? { phase == .capturing ? steps[stepIndex] : nil }
    var stepProgress: Double { Double(samplesInStep) / Double(steps[stepIndex].samplesNeeded) }

    /// Starts capturing, or reports what is missing first.
    func begin() {
        let simulated = capture is SimulatedEnrollmentCapture
        if !simulated {
            switch CameraPermission.status {
            case .undetermined: phase = .needsPermission; return
            case .denied: phase = .denied; return
            case .granted: break
            }
        }
        guard services.settings[CoreSettings.cameraEnabled] else {
            phase = .unavailable("Turn on the camera in Control Center to set up recognition.")
            return
        }
        filter = EnrollmentSampleFilter()
        stepIndex = 0
        samplesInStep = 0
        hint = "Starting the camera"
        phase = .capturing
        (capture as? SimulatedEnrollmentCapture)?.currentStep = { [weak self] in self?.currentStep }
        Task { [weak self] in
            guard let self else { return }
            // The presence sensor needs a moment to close the camera before ours can open.
            guard await self.services.capture.claimWhenReady(Self.owner, camera: .trueDepth) else {
                self.phase = .unavailable("Turn on the camera in Control Center to set up recognition.")
                return
            }
            guard self.phase == .capturing else {
                self.services.capture.release(Self.owner)
                return
            }
            self.capture.start(
                onObservation: { [weak self] observation in self?.handle(observation) },
                failed: { [weak self] message in self?.fail(message) }
            )
        }
    }

    /// Asks for camera access after the explanation, then begins.
    func requestAccessAndBegin() async {
        _ = await CameraPermission.request()
        begin()
    }

    func cancel() {
        capture.stop()
        services.capture.release(Self.owner)
        if phase == .capturing { phase = .ready }
    }

    // MARK: Capture

    private func handle(_ observation: EnrollmentObservation) {
        guard phase == .capturing else { return }
        let step = steps[stepIndex]
        let relaxedBefore = filter.relaxedSteps.count
        let verdict = filter.evaluate(observation, step: step, requiresLiveness: capture.requiresLiveness)
        if filter.relaxedSteps.count > relaxedBefore {
            PresenceTrace.trace.log("enrollment \(step) took too long, quality checks relaxed")
        }
        switch verdict {
        case .wait:
            return
        case .hint(let text):
            traceLivenessFailure(observation)
            hint = text
        case .accept:
            filter.keep(observation, for: step)
            traceSample(observation, step: step)
            hint = step.poseSpreadDegrees > 0 ? step.spreadHint : "Hold still"
            samplesInStep += 1
            if samplesInStep >= step.samplesNeeded { advance() }
        }
    }

    private func traceLivenessFailure(_ observation: EnrollmentObservation) {
        guard capture.requiresLiveness, observation.faceCount == 1, let sample = observation.sample,
              sample.liveness?.isLive != true else { return }
        if let liveness = sample.liveness {
            PresenceTrace.trace.log("enrollment sample rejected: \(PresenceTrace.describe(liveness)) "
                + "width \(PresenceTrace.format(observation.faceWidth))")
        } else {
            PresenceTrace.trace.log("enrollment sample: no depth")
        }
    }

    private func traceSample(_ observation: EnrollmentObservation, step: EnrollmentStep) {
        guard PresenceTrace.trace.isEnabled, let sample = observation.sample else { return }
        let distance = sample.liveness?.distanceMeters.map { " distance \(PresenceTrace.format($0)) m" } ?? ""
        let luma = observation.faceLuma.map { " luma \(PresenceTrace.format($0))" } ?? ""
        PresenceTrace.trace.log("enrollment sample \(step)\(PresenceTrace.describePose(sample)) "
            + "width \(PresenceTrace.format(observation.faceWidth))\(distance) \(PresenceTrace.describe(sample.liveness))\(luma)")
    }

    private func advance() {
        samplesInStep = 0
        hint = ""
        if stepIndex + 1 < steps.count {
            stepIndex += 1
        } else {
            finish()
        }
    }

    private func finish() {
        capture.stop()
        services.capture.release(Self.owner)
        do {
            try recognition.saveEnrollment(memberID: member.id, embeddings: filter.embeddings, revision: capture.featurePrintRevision)
            let far = filter.kept.filter { $0.step.distance == .far }.count
            PresenceTrace.trace.log("enrollment saved \(filter.kept.count) samples, \(far) sitting back")
            phase = .finished
        } catch {
            phase = .failed("The face template could not be saved.")
        }
    }

    private func fail(_ message: String) {
        capture.stop()
        services.capture.release(Self.owner)
        phase = .failed(message)
    }
}
