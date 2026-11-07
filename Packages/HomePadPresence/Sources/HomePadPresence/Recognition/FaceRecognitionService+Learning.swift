import Foundation
import HomePadCore

/// Learning from use, like Face ID: while a recognized member stays in view on
/// one unbroken face track, a few more of their embeddings are kept from poses,
/// distances and light their enrollment does not cover yet, so the next visit
/// in those conditions matches quickly.
///
/// Matching uses enrolled and learned embeddings together with the same
/// threshold, margin and votes. What may be learned is `FaceLearningPolicy`,
/// and which track it may come from is `FaceLearningSession`.
extension FaceRecognitionService {
    /// How many samples were learned for a member, for Settings.
    func learnedCount(for memberID: UUID) -> Int {
        learnedSamples[memberID]?.samples.count ?? 0
    }

    /// Forgets what was learned for a member, depth templates included.
    /// Their enrollment stays.
    func resetLearned(memberID: UUID) {
        try? store?.deleteLearned(memberID: memberID)
        learnedSamples[memberID] = nil
        depthIdentity.reset(memberID: memberID)
        learning.reset()
        rebuildMatchSet()
        PresenceTrace.trace.log("learned samples reset for \(memberName(memberID))")
    }

    /// Notes the face track of a frame. Learning stops when it changes.
    func noteFaceTrack(_ trackID: UUID?) {
        if learning.noteTrack(trackID) {
            PresenceTrace.trace.log("learning stopped: the face track ended")
        }
    }

    /// True while samples of the confirmed member could be learned right now.
    func wantsLearningSamples(at now: Date) -> Bool {
        guard isEnabled, let member = confirmedMemberID, learning.member == member else { return false }
        return learning.wantsSample(at: now, policy: learningPolicy)
    }

    /// Starts learning when `memberID` was confirmed by votes from this face track.
    func startLearningIfConfirmedOnTrack(_ memberID: UUID, track: UUID?, requiredVotes: Int, at time: Date) {
        guard learning.confirmed(memberID, track: track, requiredVotes: requiredVotes, at: time) else { return }
        PresenceTrace.trace.log("learning started for \(memberName(memberID)): recognized on an unbroken face track, "
            + "\(learnedCount(for: memberID)) learned so far")
    }

    /// Keeps a sample of the confirmed member when it passes `FaceLearningPolicy`.
    func learnIfUseful(_ sample: FaceEmbeddingSample, of member: UUID, at time: Date) {
        guard learning.mayLearn(member, track: sample.trackID, at: time, policy: learningPolicy),
              let template = templates[member] else { return }
        let learned = learnedSamples[member] ?? LearnedFaceSamples(
            memberID: member, featurePrintRevision: template.featurePrintRevision, samples: []
        )
        let others = matchSet.filter { $0.memberID != member }.map(\.embeddings)
        let margin = services.settings[PresenceSettings.recognitionStrictness].matcher.margin
        let verdict = learningPolicy.evaluate(
            sample, enrolled: template.embeddings, stored: template.embeddings + learned.embeddings, others: others, margin: margin
        )
        switch verdict {
        case .skip(let reason):
            PresenceTrace.trace.logIfChanged("learning", "learning skipped: \(reason.description)")
        case .learn(let score):
            let relief = sample.liveness?.reliefMeters ?? 0
            var updated = learned
            updated.append(
                LearnedFaceSample(embedding: sample.embedding, learnedAt: time, enrolledScore: score, reliefMeters: relief),
                cap: learningPolicy.capPerMember
            )
            do {
                try store?.saveLearned(updated)
            } catch {
                // Complete protection: nothing can be written while the iPad is locked.
                PresenceTrace.trace.log("learned sample not saved: \(error.localizedDescription)")
                return
            }
            learnedSamples[member] = updated
            rebuildMatchSet()
            learning.didLearn(at: time)
            PresenceTrace.trace.log("learned sample for \(memberName(member)) score \(PresenceTrace.format(score)) "
                + "relief \(PresenceTrace.format(relief * 1000))mm, \(updated.samples.count) learned"
                + PresenceTrace.describePose(sample))
        }
    }

    func memberName(_ id: UUID) -> String {
        services.household.members.first { $0.id == id }?.name ?? "?"
    }
}
