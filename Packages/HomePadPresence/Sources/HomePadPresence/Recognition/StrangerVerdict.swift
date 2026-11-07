import Foundation

/// Decides that the face of one look is confidently nobody in the household,
/// so the session drops to Guest at once instead of waiting for its timeout.
///
/// Feature prints score a household member low too, in the dark or at an odd
/// angle, so one low score proves nothing. A stranger takes `requiredSamples`
/// clean samples in a row, each scoring under `ceiling` against every enrolled
/// and learned embedding. Clean is the bar learning from use already sets:
/// exactly one face in view and the sample's own depth showing face shaped
/// relief over nearly all of the face. Anything else is skipped without
/// breaking the run, and any sample that scores `ceiling` or more, matches
/// someone or looks like a photo starts it over.
///
/// The numbers come from real presence traces (Presence README, "Who is
/// signed in"). Of 10,331 samples with face shaped relief from visits where the
/// member was recognized, none scored under 0.50, seven scored under 0.55, and never
/// two in a row.
struct StrangerVerdict: Equatable, Sendable {
    /// Best similarity a clean sample must stay under.
    var ceiling = 0.55
    /// Clean low samples in a row it takes.
    var requiredSamples = 4
    /// A run older than this is forgotten, so samples far apart in time never add up.
    var maxAge: TimeInterval = 6
    /// The relief and depth coverage a clean sample shows (`FaceLearningPolicy`).
    var reliefRange: ClosedRange<Double> = FaceLearningPolicy().reliefRange
    var minimumValidFraction = FaceLearningPolicy().minimumValidFraction

    private var run: [Date] = []

    /// Clean low samples in the current run, for the trace.
    var count: Int { run.count }

    /// Adds one matcher decision. Returns true once the face is confidently a stranger.
    mutating func add(_ decision: MatchDecision, sample: FaceEmbeddingSample, at time: Date) -> Bool {
        switch decision {
        case .member, .spoof:
            run.removeAll()
            return false
        case .unknown(let best):
            if best >= ceiling {
                run.removeAll()
                return false
            }
            guard isClean(sample) else { return false }
            run.removeAll { time.timeIntervalSince($0) > maxAge }
            run.append(time)
            return run.count >= requiredSamples
        }
    }

    mutating func reset() {
        run.removeAll()
    }

    /// One face in view, and its own depth check passed with face shaped relief
    /// over nearly all of the face.
    func isClean(_ sample: FaceEmbeddingSample) -> Bool {
        guard sample.visibleFaces == 1, let liveness = sample.liveness, liveness.isLive else { return false }
        return reliefRange.contains(liveness.reliefMeters) && liveness.validFraction >= minimumValidFraction
    }
}
