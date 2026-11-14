import Foundation
import HomePadCore
import Observation

/// On-device face recognition for up to six household members.
///
/// Embeddings from the sensing pipeline are matched against enrolled
/// templates, a liveness check rejects photos on TrueDepth iPads, and
/// temporal voting confirms a member. Recognition decides about each look,
/// one unbroken view of one face (`FaceLookTracker`), from scratch, and
/// reports what it sees to the household's session (`Household.noteCamera`).
/// While a recognized member stays in view, it also learns how they look in
/// new conditions (`FaceRecognitionService+Learning`).
@MainActor
@Observable
final class FaceRecognitionService {
    /// Enrolled templates. Learning never changes them.
    private(set) var templates: [UUID: FaceTemplate] = [:]
    /// Embeddings learned from use, per member. Set only by load, enrollment
    /// and the learning extension.
    var learnedSamples: [UUID: LearnedFaceSamples] = [:]
    /// Latest matcher verdict, for diagnostics.
    private(set) var lastDecision: MatchDecision?
    /// Latest liveness verdict, for diagnostics.
    private(set) var lastLiveness: LivenessResult?
    /// What recognition has decided about the face in view, on its current look.
    private(set) var lookIdentity: FaceIdentity = .unsure
    private(set) var storageError: String?

    /// The member confirmed for the face in view, nil while undecided or a stranger.
    var confirmedMemberID: UUID? {
        if case .member(let id) = lookIdentity { return id }
        return nil
    }

    /// Called when the face in view is named a member, or a stranger (nil), so
    /// the snapshot can carry it.
    @ObservationIgnored var onRecognized: ((UUID?) -> Void)?

    @ObservationIgnored let store: FaceTemplateStore?
    @ObservationIgnored let services: AppServices
    /// Depth identity, evaluation only (`FaceRecognitionService+DepthIdentity`).
    @ObservationIgnored let depthIdentity: DepthIdentityEvaluator
    /// What the matcher compares against: each member's enrolled and learned
    /// embeddings together. Rebuilt when either changes.
    @ObservationIgnored private(set) var matchSet: [FaceTemplate] = []
    /// What became of the last sample, in words, for the recognition debug view.
    @ObservationIgnored private(set) var lastSampleSummary: String?
    /// Which face track learning may use (`FaceLearningSession`).
    @ObservationIgnored var learning = FaceLearningSession()
    let learningPolicy: FaceLearningPolicy
    @ObservationIgnored private var voter = RecognitionStrictness.standard.voter
    /// Clean samples far from everyone on this look (`StrangerVerdict`).
    @ObservationIgnored private var strangers = StrangerVerdict()
    /// Which look the face in view belongs to.
    @ObservationIgnored private var looks = FaceLookTracker()
    /// When this look's identity was last decided or confirmed again.
    @ObservationIgnored private var lastSettledAt: Date?
    /// When a sample last passed the depth liveness check, on this look.
    @ObservationIgnored private var lastLiveAt: Date?
    /// How long a passed liveness check covers samples that arrive without depth.
    private let livenessCarry: TimeInterval = 3
    /// How often to sample while nobody is confirmed.
    @ObservationIgnored private var cadence = RecognitionCadence()
    /// First face, first sample and sample counts of this look, for the trace.
    @ObservationIgnored private var timeline = RecognitionTimeline()
    /// Checks again this often that a recognized face is still that member, in
    /// case the face tracker kept one track across two people.
    private let recheckInterval: TimeInterval = 30
    /// Whether a camera watches and anyone is present, from `LivePresenceService`.
    @ObservationIgnored private var isWatching = false
    @ObservationIgnored private var isSomeonePresent = false
    /// The view last reported to the household.
    @ObservationIgnored private var reportedView: CameraView?

    init(services: AppServices, store: FaceTemplateStore?, learningPolicy: FaceLearningPolicy = FaceLearningPolicy()) {
        self.services = services
        self.store = store
        self.learningPolicy = learningPolicy
        depthIdentity = DepthIdentityEvaluator(store: store)
    }

    var isEnabled: Bool { services.settings[CoreSettings.faceRecognitionEnabled] }

    /// True when the pipeline should spend time computing embeddings.
    var wantsEmbeddings: Bool {
        let now = Date()
        return (isEnabled && !templates.isEmpty && confirmedMemberID == nil) || needsRecheck(at: now) || wantsLearningSamples(at: now)
    }

    func hasEnrollment(_ memberID: UUID) -> Bool { templates[memberID] != nil }

    /// Seconds the analyzer should leave between samples (`RecognitionCadence`,
    /// or the learning rate while samples are only taken to learn).
    func sampleInterval(at now: Date = Date()) -> TimeInterval {
        if isSamplingOnlyToLearn(at: now) { return learningPolicy.sampleInterval }
        let strictness = services.settings[PresenceSettings.recognitionStrictness]
        return cadence.interval(at: now, fastInterval: strictness.fastSampleInterval)
    }

    /// True while a confirmed member is sampled for learning, not for recognition.
    func isSamplingOnlyToLearn(at now: Date) -> Bool {
        confirmedMemberID != nil && !needsRecheck(at: now) && wantsLearningSamples(at: now)
    }

    // MARK: Templates

    func load() {
        guard let store else { return }
        do {
            let all = try store.loadAll().filter { $0.featurePrintRevision == FaceEmbedder.featurePrintRevision || isSyntheticTemplate($0) }
            let enrolled = Dictionary(all.map { ($0.memberID, $0) }, uniquingKeysWith: { _, latest in latest })
            // Learned samples count only next to an enrollment from the same feature print revision.
            let learned = try store.loadLearned().filter { enrolled[$0.memberID]?.featurePrintRevision == $0.featurePrintRevision }
            templates = enrolled
            learnedSamples = Dictionary(learned.map { ($0.memberID, $0) }, uniquingKeysWith: { _, latest in latest })
            try depthIdentity.load(enrolled: Set(enrolled.keys))
            rebuildMatchSet()
            storageError = nil
        } catch {
            storageError = "Face templates could not be read. They are locked while the iPad is locked."
        }
    }

    /// Saves a new enrollment. It replaces the old one and clears what was
    /// learned, depth templates included.
    func saveEnrollment(memberID: UUID, embeddings: [[Float]], revision: Int = FaceEmbedder.featurePrintRevision) throws {
        let template = FaceTemplate(memberID: memberID, embeddings: embeddings, featurePrintRevision: revision, createdAt: Date())
        try store?.deleteLearned(memberID: memberID)
        depthIdentity.reset(memberID: memberID)
        try store?.save(template)
        templates[memberID] = template
        learnedSamples[memberID] = nil
        learning.reset()
        rebuildMatchSet()
        setEnrollmentFlag(memberID, true)
    }

    /// Deletes a member's face data: enrolled, learned and depth templates.
    func deleteEnrollment(memberID: UUID) {
        try? store?.delete(memberID: memberID)
        templates[memberID] = nil
        learnedSamples[memberID] = nil
        depthIdentity.forget(memberID: memberID)
        learning.reset()
        rebuildMatchSet()
        if confirmedMemberID == memberID { presenceEnded() }
        setEnrollmentFlag(memberID, false)
    }

    /// A person took the household's ID for them as this HomePad joined the
    /// household's shared setup. Their face data here moves to that ID, so
    /// this HomePad keeps recognizing them. It never leaves this iPad.
    func moveMember(from old: UUID, to new: UUID) {
        do {
            try store?.move(from: old, to: new)
        } catch {
            storageError = "Face data could not be moved to the household's ID for this person. Set up their face again."
        }
        if var template = templates.removeValue(forKey: old) {
            template.memberID = new
            templates[new] = template
        }
        if var learned = learnedSamples.removeValue(forKey: old) {
            learned.memberID = new
            learnedSamples[new] = learned
        }
        depthIdentity.move(from: old, to: new)
        if confirmedMemberID == old { presenceEnded() }
        learning.reset()
        rebuildMatchSet()
    }

    /// Deletes templates whose member was removed from the household.
    func reconcile(with members: [HouseholdMember]) {
        let ids = Set(members.map(\.id))
        for orphan in templates.keys where !ids.contains(orphan) {
            try? store?.delete(memberID: orphan)
            templates[orphan] = nil
            learnedSamples[orphan] = nil
            depthIdentity.forget(memberID: orphan)
        }
        rebuildMatchSet()
        for member in members where member.hasFaceEnrollment != (templates[member.id] != nil) {
            setEnrollmentFlag(member.id, templates[member.id] != nil)
        }
    }

    /// Joins each member's enrolled and learned embeddings for the matcher.
    func rebuildMatchSet() {
        matchSet = templates.values.map { template in
            var combined = template
            combined.embeddings += learnedSamples[template.memberID]?.embeddings ?? []
            return combined
        }
    }

    // MARK: Recognition

    /// Considers one embedding. `requireLiveness` is true on TrueDepth iPads,
    /// where an embedding without a depth verdict is skipped.
    func consider(_ sample: FaceEmbeddingSample, requireLiveness: Bool, at time: Date = Date()) {
        guard isEnabled, !templates.isEmpty else { return }
        noteFaceTrack(sample.trackID)
        if looks.noteSample(track: sample.trackID) { lookChanged(at: time) }
        // Too dark to tell anyone apart: neither a match, a stranger nor a lesson.
        if let luma = sample.cropLuma, luma < FaceEmbedder.minimumCropLuma {
            lastSampleSummary = "too dark to tell" + Self.describeLuma(sample)
            noteSample(nil, at: time)
            PresenceTrace.trace.log("sample skipped: too dark" + Self.describeLuma(sample) + PresenceTrace.describePose(sample))
            return
        }
        if let member = confirmedMemberID {
            let name = services.household.members.first { $0.id == member }?.name ?? "someone"
            lastSampleSummary = "\(name) confirmed, sampling to learn" + Self.describeLuma(sample)
            learnIfUseful(sample, of: member, at: time)
            // Samples taken only to learn stay out of the votes.
            guard needsRecheck(at: time) else { return }
        }
        let strictness = services.settings[PresenceSettings.recognitionStrictness]
        let preset = strictness.voter
        if voter.windowSize != preset.windowSize || voter.requiredVotes != preset.requiredVotes { voter = preset }

        lastLiveness = sample.liveness
        let decision: MatchDecision
        if requireLiveness {
            if let liveness = sample.liveness {
                lastLiveAt = liveness.isLive ? time : nil
                // The depth could not tell a face from a photo: neither a match nor a spoof.
                if let unsure = liveness.unsure {
                    lastSampleSummary = "skipped, depth unsure: \(unsure.description)"
                    noteSample(nil, at: time)
                    PresenceTrace.trace.log("sample skipped: \(PresenceTrace.describe(liveness))" + PresenceTrace.describePose(sample))
                    return
                }
            } else if !hasRecentLiveness(at: time) {
                lastSampleSummary = "skipped, no depth for the liveness check"
                noteSample(nil, at: time)
                PresenceTrace.trace.log("sample skipped: liveness required, no depth\(Self.describeWait(sample))")
                return
            }
            // A sample without its own depth counts when a live check passed moments
            // ago and no flat face was seen since: TrueDepth measures depth on only
            // some frames, and requiring it on every sample made recognition slow.
            let isLive = sample.liveness?.isLive ?? true
            decision = isLive ? strictness.matcher.match(sample.embedding, against: matchSet) : .spoof
        } else {
            decision = strictness.matcher.match(sample.embedding, against: matchSet)
        }
        lastDecision = decision
        let summaryNames = Dictionary(services.household.members.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        lastSampleSummary = PresenceTrace.describe(decision, names: summaryNames) + Self.describeLuma(sample)
        noteSample(decision, at: time)
        learning.noteDecision(decision, track: sample.trackID)
        let winner = voter.add(decision, at: time)
        let isStranger = strangers.add(decision, sample: sample, at: time)
        if PresenceTrace.trace.isEnabled {
            let names = Dictionary(services.household.members.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            let stranger = strangers.count > 0 ? " stranger \(strangers.count) of \(strangers.requiredSamples)" : ""
            PresenceTrace.trace.log("sample \(PresenceTrace.describe(sample.liveness)) -> \(PresenceTrace.describe(decision, names: names)) "
                + "votes \(voter.voteSummary) needs \(voter.requiredVotes) of \(voter.windowSize)\(stranger)\(Self.describeWait(sample))"
                + Self.describeLuma(sample)
                + PresenceTrace.describePose(sample))
            if let check = sample.livenessCheck { PresenceTrace.trace.log(check) }
        }
        if let winner {
            confirm(winner, at: time, track: sample.trackID)
        } else if isStranger {
            settleStranger(at: time)
        }
    }

    /// Notes the faces of every analyzed frame. Learning stops when the face
    /// track ends, and a new look starts whenever the face in view may be
    /// someone else.
    func noteFaces(count: Int, track: UUID?, at time: Date = Date()) {
        noteFaceTrack(track)
        let before = looks.look
        _ = looks.note(faceCount: count, track: track)
        if looks.look != before { lookChanged(at: time) }
    }

    /// The sensing state the camera view depends on, from `LivePresenceService`
    /// after every frame and every change of mode.
    func updateSensing(isWatching: Bool, isSomeonePresent: Bool, at time: Date = Date()) {
        self.isWatching = isWatching
        self.isSomeonePresent = isSomeonePresent
        reportView(at: time)
    }

    /// What the camera tells the household's session.
    var cameraView: CameraView {
        guard isWatching, isEnabled, !templates.isEmpty else { return .notWatching }
        if let look = looks.look { return .face(look: look, identity: lookIdentity) }
        return isSomeonePresent ? .noFace : .nobody
    }

    /// Notes a frame with a face, so the trace can time recognition from the first face.
    func noteFace(backend: BackendKind, isPresent: Bool, at time: Date = Date()) {
        guard PresenceTrace.trace.isEnabled, isEnabled, !templates.isEmpty, confirmedMemberID == nil,
              timeline.noteFace(at: time) else { return }
        PresenceTrace.trace.log("first face (\(backend.rawValue), \(isPresent ? "someone present" : "nobody present yet"))")
    }

    /// Feeds the cadence and the trace timeline. `decision` is nil for a skipped sample.
    private func noteSample(_ decision: MatchDecision?, at time: Date) {
        cadence.record(decision, at: time)
        // Samples that refresh a confirmed member are not part of recognizing them.
        guard confirmedMemberID == nil, timeline.noteSample(skipped: decision == nil, at: time) else { return }
        let face = timeline.sinceFirstFace(time).map { " \(PresenceTrace.format($0)) s after the first face" } ?? ""
        PresenceTrace.trace.log("first sample\(face)")
    }

    private static func describeWait(_ sample: FaceEmbeddingSample) -> String {
        sample.depthWaitSeconds.map { " (waited \(PresenceTrace.format($0)) s for depth)" } ?? ""
    }

    /// " crop 0.25", the crop's mean brightness.
    private static func describeLuma(_ sample: FaceEmbeddingSample) -> String {
        sample.cropLuma.map { " crop " + String(format: "%.2f", $0) } ?? ""
    }

    private func hasRecentLiveness(at time: Date) -> Bool {
        lastLiveAt.map { time.timeIntervalSince($0) <= livenessCarry } ?? false
    }

    /// Clears the visit when nobody is present any more.
    func presenceEnded() {
        PresenceTrace.trace.log("presence ended")
        learning.reset()
        looks.end()
        clearLook()
        cadence.reset()
        timeline.reset()
        onRecognized?(nil)
        isSomeonePresent = false
        reportView(at: Date())
    }

    /// The face in view may be someone else: a new look starts undecided, or
    /// the last face left. Votes, the stranger run and the liveness carry
    /// belonged to the old face, so they go.
    private func lookChanged(at time: Date) {
        clearLook()
        if looks.look != nil {
            // A new face gets the fast burst, like the first face of a visit.
            cadence.reset()
            timeline.reset()
        }
        reportView(at: time)
    }

    private func clearLook() {
        voter.reset()
        strangers.reset()
        lastLiveAt = nil
        lastSettledAt = nil
        lookIdentity = .unsure
    }

    /// True when a recognized face is due to be checked again.
    private func needsRecheck(at now: Date) -> Bool {
        guard isEnabled, confirmedMemberID != nil, let last = lastSettledAt else { return false }
        return now.timeIntervalSince(last) >= recheckInterval
    }

    private func confirm(_ memberID: UUID, at time: Date, track: UUID?) {
        defer { startLearningIfConfirmedOnTrack(memberID, track: track, requiredVotes: voter.requiredVotes, at: time) }
        lastSettledAt = time
        // A recheck that agrees changes nothing.
        guard lookIdentity != .member(memberID) else { return }
        PresenceTrace.trace.log("recognized \(memberName(memberID)) " + timeline.summary(at: time))
        lookIdentity = .member(memberID)
        onRecognized?(memberID)
        reportView(at: time)
    }

    private func settleStranger(at time: Date) {
        lastSettledAt = time
        guard lookIdentity != .stranger else { return }
        PresenceTrace.trace.log("stranger: \(strangers.requiredSamples) clean samples in a row under "
            + "\(PresenceTrace.format(strangers.ceiling)) " + timeline.summary(at: time))
        lookIdentity = .stranger
        onRecognized?(nil)
        reportView(at: time)
    }

    /// Tells the household what the camera sees, when that changed, and posts
    /// `.memberRecognized` when it signed someone in by face.
    private func reportView(at time: Date) {
        let view = cameraView
        guard view != reportedView else { return }
        reportedView = view
        let household = services.household
        let before = household.unlockedMember?.id
        household.noteCamera(view, now: time)
        let after = household.unlockedMember?.id
        if PresenceTrace.trace.isEnabled {
            PresenceTrace.trace.log("camera view \(describe(view)), session \(describe(household.session.mode))")
        }
        if let after, after != before, case .face(_, let identity) = view, identity == .member(after) {
            services.events.post(.memberRecognized(after))
        }
    }

    private func describe(_ view: CameraView) -> String {
        switch view {
        case .notWatching: "not watching"
        case .nobody: "nobody"
        case .noFace: "no face"
        case .face(_, .unsure): "face undecided"
        case .face(_, .member(let id)): "face \(memberName(id))"
        case .face(_, .stranger): "face of a stranger"
        }
    }

    private func describe(_ mode: MemberSession.Mode) -> String {
        switch mode {
        case .guest: "guest"
        case .picked(let id): "picked \(memberName(id))"
        case .recognized(let id): "recognized \(memberName(id))"
        case .verified(let id): "verified \(memberName(id))"
        }
    }

    private func setEnrollmentFlag(_ memberID: UUID, _ enrolled: Bool) {
        guard var member = services.household.members.first(where: { $0.id == memberID }),
              member.hasFaceEnrollment != enrolled else { return }
        member.hasFaceEnrollment = enrolled
        services.household.update(member)
    }

    /// Simulator enrollments use synthetic vectors and revision 0.
    private func isSyntheticTemplate(_ template: FaceTemplate) -> Bool {
        template.featurePrintRevision == 0 && PresenceLaunchOptions.current.isSimulated
    }
}
