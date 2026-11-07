import Foundation

/// Which face track learning from use may take samples from.
///
/// Learning starts on a track (`FaceTrackContinuity`) only when a member was
/// confirmed by votes cast on that same track, and it ends for good when the
/// track ends: the face was lost, a second face appeared or ARKit switched
/// anchors. Learning then waits for the next confirmed recognition, which
/// needs a full set of votes on the new track. A track on which two members
/// matched is never learned from.
struct FaceLearningSession: Equatable, Sendable {
    private(set) var trackID: UUID?
    /// The member being learned, nil while not learning.
    private(set) var member: UUID?
    private(set) var learnedOnTrack = 0
    /// Matching votes per member on this track.
    private var matches: [UUID: Int] = [:]
    private var isConflicted = false
    private var startedAt: Date?
    private var lastLearnedAt: Date?

    var isLearning: Bool { member != nil }

    /// Notes the face track of a frame. Returns true when this ended learning.
    @discardableResult
    mutating func noteTrack(_ id: UUID?) -> Bool {
        guard id != trackID else { return false }
        let wasLearning = isLearning
        self = FaceLearningSession()
        trackID = id
        return wasLearning
    }

    /// Counts a recognition decision made on `track`.
    mutating func noteDecision(_ decision: MatchDecision, track: UUID?) {
        guard let track, track == trackID, let id = decision.memberID else { return }
        matches[id, default: 0] += 1
        if matches.count > 1 {
            isConflicted = true
            member = nil
        }
    }

    /// A member was confirmed by the votes. Starts learning when the face track
    /// is unbroken and at least `requiredVotes` of the votes for them, and none
    /// for anyone else, came from this track. Returns true when learning started.
    mutating func confirmed(_ id: UUID, track: UUID?, requiredVotes: Int, at time: Date) -> Bool {
        guard let track, track == trackID, !isConflicted else { return false }
        if let member {
            if member != id {
                isConflicted = true
                self.member = nil
            }
            return false
        }
        guard matches[id, default: 0] >= requiredVotes, matches.count == 1 else { return false }
        member = id
        // A refresh on the same track keeps its budget and its window.
        startedAt = startedAt ?? time
        return true
    }

    /// True while a sample taken now could be learned.
    func wantsSample(at time: Date, policy: FaceLearningPolicy) -> Bool {
        guard member != nil, let startedAt, learnedOnTrack < policy.perTrackLimit,
              time.timeIntervalSince(startedAt) <= policy.trackWindow else { return false }
        return lastLearnedAt.map { time.timeIntervalSince($0) >= policy.minimumSpacing } ?? true
    }

    /// True when a sample of `id` from `track` taken at `time` may be learned.
    func mayLearn(_ id: UUID, track: UUID?, at time: Date, policy: FaceLearningPolicy) -> Bool {
        track != nil && track == trackID && member == id && wantsSample(at: time, policy: policy)
    }

    mutating func didLearn(at time: Date) {
        learnedOnTrack += 1
        lastLearnedAt = time
    }

    /// Stops learning until the next confirmed recognition on a new track.
    mutating func reset() {
        self = FaceLearningSession()
    }
}
