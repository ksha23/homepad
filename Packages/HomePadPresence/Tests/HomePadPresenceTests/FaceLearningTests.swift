import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

/// Embeddings with exact similarities: unit axes, and probes at a chosen
/// cosine to one axis that lean toward another.
enum LearningVectors {
    static func axis(_ index: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: SyntheticFace.dimension)
        vector[index] = 1
        return vector
    }

    /// A unit vector at cosine `similarity` to axis `base`, leaning toward axis `toward`.
    static func probe(_ similarity: Double, toward: Int, base: Int = 0) -> [Float] {
        var vector = [Float](repeating: 0, count: SyntheticFace.dimension)
        vector[base] = Float(similarity)
        vector[toward] = Float((1 - similarity * similarity).squareRoot())
        return vector
    }

    static let live = LivenessResult(isLive: true, reliefMeters: 0.014, validFraction: 1)

    static func sample(_ embedding: [Float], track: UUID?, liveness: LivenessResult? = live, faces: Int? = 1) -> FaceEmbeddingSample {
        FaceEmbeddingSample(embedding: embedding, liveness: liveness, trackID: track, visibleFaces: faces)
    }
}

@Suite struct FaceTrackContinuityTests {
    private let anchor = UUID()
    private let here = SIMD3<Float>(0, 0, -0.6)

    private func face(_ anchor: UUID, at position: SIMD3<Float>? = nil) -> FaceTrackContinuity.TrackedFace {
        FaceTrackContinuity.TrackedFace(anchor: anchor, position: position ?? here)
    }

    @Test func oneFaceKeepsItsTrack() {
        var continuity = FaceTrackContinuity()
        let first = continuity.update(tracked: [face(anchor)], at: 0)
        let second = continuity.update(tracked: [face(anchor)], at: 0.1)
        #expect(first != nil)
        #expect(first == second)
    }

    /// In a dark room ARKit drops the face on about half the frames. The track holds through it.
    @Test func aShortGapKeepsTheTrack() {
        var continuity = FaceTrackContinuity()
        let before = continuity.update(tracked: [face(anchor)], at: 0)
        let gap = continuity.update(tracked: [], at: 0.1)
        let after = continuity.update(tracked: [face(anchor, at: here + SIMD3(0.03, 0, 0))], at: 0.3)
        #expect(gap == before)
        #expect(after == before)
    }

    /// ARKit may reuse the same anchor for whoever comes back after a longer gap: a new track.
    @Test func aLongGapEndsTheTrack() {
        var continuity = FaceTrackContinuity()
        let before = continuity.update(tracked: [face(anchor)], at: 0)
        _ = continuity.update(tracked: [], at: 0.1)
        let ended = continuity.update(tracked: [], at: 0.7)
        let after = continuity.update(tracked: [face(anchor)], at: 0.8)
        #expect(ended == nil)
        #expect(after != nil && after != before)
    }

    @Test func aFaceBackSomewhereElseStartsANewTrack() {
        var continuity = FaceTrackContinuity()
        let before = continuity.update(tracked: [face(anchor)], at: 0)
        _ = continuity.update(tracked: [], at: 0.1)
        let after = continuity.update(tracked: [face(anchor, at: here + SIMD3(0.4, 0, 0))], at: 0.2)
        #expect(after != nil && after != before)
    }

    @Test func aSecondFaceEndsTheTrack() {
        var continuity = FaceTrackContinuity()
        let before = continuity.update(tracked: [face(anchor)], at: 0)
        let both = continuity.update(tracked: [face(anchor), face(UUID())], at: 0.1)
        let after = continuity.update(tracked: [face(anchor)], at: 0.2)
        #expect(both == nil)
        #expect(after != before)
    }

    @Test func aDifferentAnchorStartsANewTrack() {
        var continuity = FaceTrackContinuity()
        let before = continuity.update(tracked: [face(anchor)], at: 0)
        let after = continuity.update(tracked: [face(UUID())], at: 0.1)
        #expect(after != nil && after != before)
    }
}

@Suite struct FaceLearningSessionTests {
    private let alice = UUID()
    private let bob = UUID()
    private let track = UUID()
    private let t0 = Date(timeIntervalSinceReferenceDate: 8000)
    private let policy = FaceLearningPolicy()

    private func votes(_ session: inout FaceLearningSession, _ id: UUID, count: Int, track: UUID?) {
        for _ in 0..<count { session.noteDecision(.member(id, score: 0.86), track: track) }
    }

    @Test func startsOnlyWhenTheVotesCameFromThisTrack() {
        var session = FaceLearningSession()
        session.noteTrack(track)
        votes(&session, alice, count: 3, track: track)
        let early = session.confirmed(alice, track: track, requiredVotes: 4, at: t0)
        votes(&session, alice, count: 1, track: track)
        let started = session.confirmed(alice, track: track, requiredVotes: 4, at: t0)
        #expect(!early && started)
        #expect(session.mayLearn(alice, track: track, at: t0, policy: policy))
    }

    @Test func votesFromAnEarlierTrackDoNotCount() {
        var session = FaceLearningSession()
        session.noteTrack(track)
        votes(&session, alice, count: 3, track: track)
        let next = UUID()
        session.noteTrack(next)
        votes(&session, alice, count: 1, track: next)
        let started = session.confirmed(alice, track: next, requiredVotes: 4, at: t0)
        #expect(!started)
    }

    @Test func noTrackMeansNoLearning() {
        var session = FaceLearningSession()
        session.noteTrack(nil)
        votes(&session, alice, count: 4, track: nil)
        let started = session.confirmed(alice, track: nil, requiredVotes: 4, at: t0)
        #expect(!started)
        #expect(!session.mayLearn(alice, track: nil, at: t0, policy: policy))
    }

    @Test func theTrackEndingStopsLearningUntilTheNextRecognition() {
        var session = FaceLearningSession()
        session.noteTrack(track)
        votes(&session, alice, count: 4, track: track)
        _ = session.confirmed(alice, track: track, requiredVotes: 4, at: t0)
        let stopped = session.noteTrack(UUID())
        #expect(stopped)
        #expect(!session.isLearning)
        // Back to the old track identifier: still needs a new confirmation.
        session.noteTrack(track)
        #expect(!session.mayLearn(alice, track: track, at: t0, policy: policy))
    }

    @Test func twoMembersOnOneTrackNeverLearn() {
        var session = FaceLearningSession()
        session.noteTrack(track)
        votes(&session, alice, count: 4, track: track)
        votes(&session, bob, count: 1, track: track)
        votes(&session, alice, count: 4, track: track)
        let started = session.confirmed(alice, track: track, requiredVotes: 4, at: t0)
        #expect(!started)
    }

    @Test func anotherMemberConfirmedOnTheTrackStopsLearning() {
        var session = FaceLearningSession()
        session.noteTrack(track)
        votes(&session, alice, count: 4, track: track)
        _ = session.confirmed(alice, track: track, requiredVotes: 4, at: t0)
        _ = session.confirmed(bob, track: track, requiredVotes: 4, at: t0)
        #expect(!session.isLearning)
        let started = session.confirmed(alice, track: track, requiredVotes: 4, at: t0 + 1)
        #expect(!started)
    }

    @Test func rateLimitsPerTrack() {
        var session = FaceLearningSession()
        session.noteTrack(track)
        votes(&session, alice, count: 4, track: track)
        _ = session.confirmed(alice, track: track, requiredVotes: 4, at: t0)
        session.didLearn(at: t0)
        #expect(!session.wantsSample(at: t0 + policy.minimumSpacing - 1, policy: policy))
        #expect(session.wantsSample(at: t0 + policy.minimumSpacing, policy: policy))
        var time = t0
        for _ in 1..<policy.perTrackLimit {
            time += policy.minimumSpacing
            session.didLearn(at: time)
        }
        // The track's budget is spent, also after a refresh confirms again.
        _ = session.confirmed(alice, track: track, requiredVotes: 4, at: time + 30)
        #expect(!session.wantsSample(at: time + 60, policy: policy))
    }

    @Test func aTrackStopsSamplingAfterItsWindow() {
        var session = FaceLearningSession()
        session.noteTrack(track)
        votes(&session, alice, count: 4, track: track)
        _ = session.confirmed(alice, track: track, requiredVotes: 4, at: t0)
        #expect(session.wantsSample(at: t0 + policy.trackWindow, policy: policy))
        #expect(!session.wantsSample(at: t0 + policy.trackWindow + 1, policy: policy))
    }
}

@Suite struct FaceLearningPolicyTests {
    private let policy = FaceLearningPolicy()
    private let enrolled = [LearningVectors.axis(0)]
    private let margin = RecognitionStrictness.standard.matcher.margin

    private func verdict(_ embedding: [Float], liveness: LivenessResult? = LearningVectors.live, faces: Int? = 1,
                         stored: [[Float]]? = nil, others: [[[Float]]] = []) -> FaceLearningPolicy.Verdict {
        policy.evaluate(
            LearningVectors.sample(embedding, track: UUID(), liveness: liveness, faces: faces),
            enrolled: enrolled, stored: stored ?? enrolled, others: others, margin: margin
        )
    }

    @Test func learnsASampleBetweenTheFloorAndTheCeiling() {
        guard case .learn(let score) = verdict(LearningVectors.probe(0.78, toward: 5)) else {
            Issue.record("a sample at 0.78 was not learned")
            return
        }
        #expect(abs(score - 0.78) < 1e-4)
    }

    @Test func skipsBelowTheFloor() {
        guard case .skip(.belowFloor(let score)) = verdict(LearningVectors.probe(0.66, toward: 5)) else {
            Issue.record("a sample at 0.66 was not stopped by the floor")
            return
        }
        #expect(abs(score - 0.66) < 1e-4)
    }

    @Test func skipsWhatAddsNothingNew() {
        guard case .skip(.notNew) = verdict(LearningVectors.probe(0.93, toward: 5)) else {
            Issue.record("a sample this close to the enrollment was learned")
            return
        }
    }

    @Test func theFloorCountsOnlyTheEnrolledFace() {
        // A learned sample at 0.85 to the probe would pass a floor measured on
        // everything stored. Measured on the enrollment alone, the probe is at 0.6.
        let probe = LearningVectors.probe(0.6, toward: 5)
        let learnedNearby = FaceMatcher.normalized(zip(probe, LearningVectors.axis(6)).map { $0 * 0.85 + $1 * 0.527 })
        let result = verdict(probe, stored: enrolled + [learnedNearby])
        guard case .skip(.belowFloor) = result else {
            Issue.record("expected the floor to reject, got \(result)")
            return
        }
    }

    @Test func skipsWhatIsCloseToALearnedSample() {
        let learned = LearningVectors.probe(0.78, toward: 5)
        let again = FaceMatcher.normalized(zip(learned, LearningVectors.axis(6)).map { $0 * 0.98 + $1 * 0.2 })
        guard case .skip(.notNew) = verdict(again, stored: enrolled + [learned]) else {
            Issue.record("a near copy of a learned sample was learned again")
            return
        }
    }

    @Test func needsItsOwnLiveDepth() {
        let probe = LearningVectors.probe(0.78, toward: 5)
        #expect(verdict(probe, liveness: nil) == .skip(.noOwnDepth))
        #expect(verdict(probe, liveness: LivenessResult(isLive: false, reliefMeters: 0.011, validFraction: 1)) == .skip(.flat))
        let background = LivenessResult(isLive: true, reliefMeters: 0.120, validFraction: 1)
        #expect(verdict(probe, liveness: background) == .skip(.reliefOutOfRange(0.120)))
        let patchy = LivenessResult(isLive: true, reliefMeters: 0.02, validFraction: 0.7)
        #expect(verdict(probe, liveness: patchy) == .skip(.partialDepth(0.7)))
    }

    @Test func needsExactlyOneFaceInView() {
        let probe = LearningVectors.probe(0.78, toward: 5)
        #expect(verdict(probe, faces: 2) == .skip(.notOneFace))
        #expect(verdict(probe, faces: nil) == .skip(.notOneFace))
    }

    @Test func neverLearnsWhatLooksLikeAnotherMember() {
        let bob = [LearningVectors.axis(1)]
        // 0.705 to this member and 0.709 to the other one.
        let closerToBob = LearningVectors.probe(0.705, toward: 1)
        guard case .skip(.nearOtherMember) = verdict(closerToBob, others: [bob]) else {
            Issue.record("learned a sample that matches another member better")
            return
        }
        // Ahead, but by less than the matcher's margin.
        guard case .skip(.nearOtherMember) = verdict(LearningVectors.probe(0.72, toward: 1), others: [bob]) else {
            Issue.record("learned a sample within the margin of another member")
            return
        }
        // Clearly this member's.
        guard case .learn = verdict(LearningVectors.probe(0.78, toward: 1), others: [bob]) else {
            Issue.record("rejected a sample that is clearly this member's")
            return
        }
    }
}
