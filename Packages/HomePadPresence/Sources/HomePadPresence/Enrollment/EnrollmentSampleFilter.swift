import Foundation

/// Decides which enrollment frames become samples, and what to tell the
/// person meanwhile.
///
/// Hard rules never bend: one face, the step's distance, a live face on
/// TrueDepth iPads, and the step's pose. Quality rules keep samples useful:
/// the head is still enough not to blur, the face is neither dark nor blown
/// out, and the sample is not a near copy of one already taken, in pose or in
/// embedding. Their thresholds were not tuned on a device, so when the person
/// holds a valid pose for `relaxAfter` seconds and they still let nothing
/// through, the step drops them rather than stall.
struct EnrollmentSampleFilter: Sendable {
    /// Head turns faster than this blur the face.
    var maxTurnDegreesPerSecond = 30.0
    /// Face brightness (0 to 1) worth keeping.
    var lumaRange = 0.08...0.95
    /// Samples this similar to a kept one are near copies.
    var duplicateSimilarity = 0.98
    /// Seconds between two kept samples at least.
    var minimumSpacing: TimeInterval = 0.25
    /// Seconds without progress in a step after which the quality rules drop.
    var relaxAfter: TimeInterval = 6

    enum Verdict: Equatable, Sendable {
        /// Keep this sample.
        case accept
        /// Not this frame. Show the hint.
        case hint(String)
        /// Not this frame, nothing new to say.
        case wait
    }

    /// One kept sample.
    struct Kept: Equatable, Sendable {
        var step: EnrollmentStep
        var embedding: [Float]
        var yawDegrees: Double
        var pitchDegrees: Double
        var faceWidth: Double
        var distanceMeters: Double?
    }

    private(set) var kept: [Kept] = []
    /// Yaw sign of the first side, so the second side asks for the other one.
    private(set) var firstSide: Double?
    private var currentStep: EnrollmentStep?
    /// When the step's hard rules last started passing without a sample kept since.
    private var waitingSince: TimeInterval?
    private var lastKeptAt: TimeInterval = -.infinity
    private var lastPose: (time: TimeInterval, yaw: Double, pitch: Double)?
    private(set) var relaxedSteps: Set<EnrollmentStep> = []

    var embeddings: [[Float]] { kept.map(\.embedding) }

    /// Judges one frame for `step`. Call `keep(_:for:)` after `.accept`.
    mutating func evaluate(_ observation: EnrollmentObservation, step: EnrollmentStep, requiresLiveness: Bool) -> Verdict {
        if step != currentStep {
            currentStep = step
            waitingSince = nil
        }
        guard observation.faceCount > 0 else { return .hint("Center your face in the circle") }
        guard observation.faceCount == 1 else { return .hint("Only one person at a time, please") }
        if let hint = distanceHint(observation, step: step) { return .hint(hint) }
        guard let sample = observation.sample, let yaw = sample.yaw, let pitch = sample.pitch else { return .wait }
        let yawDegrees = yaw * 180 / .pi
        let pitchDegrees = pitch * 180 / .pi
        let turnRate = self.turnRate(yaw: yawDegrees, pitch: pitchDegrees, at: observation.time)
        if requiresLiveness {
            guard let liveness = sample.liveness else { return .hint("Move a little closer") }
            guard liveness.isLive else { return .hint("Use your real face, not a photo") }
        }
        guard step.matches(yaw: yaw, pitch: pitch, firstSide: firstSide) else { return .hint(step.poseHint) }
        guard observation.time - lastKeptAt >= minimumSpacing else { return .wait }
        if !isRelaxed(step, at: observation.time),
           let hint = qualityHint(observation, step: step, yaw: yawDegrees, pitch: pitchDegrees, turnRate: turnRate) {
            return .hint(hint)
        }
        return .accept
    }

    /// Keeps the sample of an accepted observation.
    mutating func keep(_ observation: EnrollmentObservation, for step: EnrollmentStep) {
        guard let sample = observation.sample, let yaw = sample.yaw, let pitch = sample.pitch else { return }
        if step == .sideA { firstSide = yaw }
        kept.append(Kept(
            step: step, embedding: sample.embedding, yawDegrees: yaw * 180 / .pi, pitchDegrees: pitch * 180 / .pi,
            faceWidth: observation.faceWidth, distanceMeters: sample.liveness?.distanceMeters
        ))
        lastKeptAt = observation.time
        waitingSince = nil
    }

    // MARK: Rules

    private func distanceHint(_ observation: EnrollmentObservation, step: EnrollmentStep) -> String? {
        let distance = observation.sample?.liveness?.distanceMeters
        switch step.distance {
        case .near:
            guard observation.faceWidth >= EnrollmentDistance.nearMinWidth else { return "Move a little closer" }
            if let distance, distance > EnrollmentDistance.nearMaxMeters { return "Move a little closer" }
            return nil
        case .far:
            guard observation.faceWidth >= EnrollmentDistance.farMinWidth else { return "Come a little closer" }
            if let distance {
                if distance < EnrollmentDistance.farMeters.lowerBound { return "Sit back a little more" }
                if distance > EnrollmentDistance.farMeters.upperBound { return "Come a little closer" }
                return nil
            }
            // Without depth, compare the face's size with the near samples'.
            let nearWidths = kept.filter { $0.step.distance == .near }.map(\.faceWidth).sorted()
            guard !nearWidths.isEmpty else { return nil }
            let ratio = observation.faceWidth / nearWidths[nearWidths.count / 2]
            if ratio > EnrollmentDistance.farWidthRatio.upperBound { return "Sit back a little more" }
            if ratio < EnrollmentDistance.farWidthRatio.lowerBound { return "Come a little closer" }
            return nil
        }
    }

    private func qualityHint(
        _ observation: EnrollmentObservation, step: EnrollmentStep, yaw: Double, pitch: Double, turnRate: Double?
    ) -> String? {
        if let turnRate, turnRate > maxTurnDegreesPerSecond { return "Hold still" }
        if let luma = observation.faceLuma {
            if luma < lumaRange.lowerBound { return "Find a little more light" }
            if luma > lumaRange.upperBound { return "Move out of the bright light" }
        }
        let spread = step.poseSpreadDegrees
        if spread > 0, kept.contains(where: { $0.step == step && max(abs($0.yawDegrees - yaw), abs($0.pitchDegrees - pitch)) < spread }) {
            return step.spreadHint
        }
        if let embedding = observation.sample?.embedding,
           kept.contains(where: { FaceMatcher.cosine($0.embedding, embedding) >= duplicateSimilarity }) {
            return "Move your head a little"
        }
        return nil
    }

    /// Degrees per second the head turned since the previous frame with a pose.
    private mutating func turnRate(yaw: Double, pitch: Double, at time: TimeInterval) -> Double? {
        defer { lastPose = (time, yaw, pitch) }
        guard let last = lastPose, time > last.time, time - last.time <= 1 else { return nil }
        return max(abs(yaw - last.yaw), abs(pitch - last.pitch)) / (time - last.time)
    }

    /// True once the person has held a valid pose for `relaxAfter` seconds
    /// without the quality rules letting a sample through.
    private mutating func isRelaxed(_ step: EnrollmentStep, at time: TimeInterval) -> Bool {
        if relaxedSteps.contains(step) { return true }
        let since = waitingSince ?? time
        waitingSince = since
        guard time - since >= relaxAfter else { return false }
        relaxedSteps.insert(step)
        return true
    }
}
