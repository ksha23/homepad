import Foundation
import HomePadCore

/// Depth identity, evaluation only. It never decides who someone is, never
/// unlocks anything and never changes what recognition decided.
///
/// While RGB recognition has named the face in view a member, each depth
/// signature (`DepthSignature`) of that face is scored against the member's
/// depth templates from earlier visits and against everyone else's, and the
/// trace gets the distances, counts and names. A face recognition settled as
/// a stranger is scored against every member, which is the evidence for how
/// close a stranger comes. Signatures of a confirmed member taken in light
/// become their templates (`DepthTemplatePolicy`).
///
/// The README ("Depth identity") says how to read the evaluation and what it
/// must show before depth identity may recognize anyone on its own.
@MainActor
final class DepthIdentityEvaluator {
    /// Whose face the signature is, as RGB recognition decided on this look.
    enum Subject: Equatable {
        case member(UUID)
        case stranger

        var memberID: UUID? {
            if case .member(let id) = self { return id }
            return nil
        }
    }

    private(set) var templates: [UUID: MemberDepthTemplates] = [:]
    let policy: DepthTemplatePolicy
    private let store: FaceTemplateStore?
    /// The face track the per-track counts below belong to.
    private var track: UUID?
    private var keptOnTrack = 0
    private var lastKeptAt: Date?
    /// Templates kept on this track, left out of its own scores, so a visit is
    /// only ever compared with other visits.
    private var keptThisTrack: Set<Date> = []

    init(store: FaceTemplateStore?, policy: DepthTemplatePolicy = DepthTemplatePolicy()) {
        self.store = store
        self.policy = policy
    }

    var hasTemplates: Bool { templates.values.contains { !$0.templates.isEmpty } }

    // MARK: Storage

    /// Loads the depth templates of members who are enrolled.
    func load(enrolled: Set<UUID>) throws {
        let loaded = try store?.loadDepth() ?? []
        let kept = loaded.filter { enrolled.contains($0.memberID) }
        templates = Dictionary(kept.map { ($0.memberID, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    /// Deletes a member's depth templates, file and memory.
    func reset(memberID: UUID) {
        try? store?.deleteDepth(memberID: memberID)
        templates[memberID] = nil
        endTrack()
    }

    /// Forgets a member whose files the store already deleted.
    func forget(memberID: UUID) {
        templates[memberID] = nil
        endTrack()
    }

    /// Follows a member's move to a new ID. The store moved the file.
    func move(from old: UUID, to new: UUID) {
        guard var moved = templates.removeValue(forKey: old) else { return }
        moved.memberID = new
        templates[new] = moved
    }

    // MARK: Evaluation

    /// Scores one signature and traces the result, then keeps it as a
    /// template when the policy allows. `names` are only for the trace.
    func consider(
        _ signature: DepthSignature, expression: Double, subject: Subject, track newTrack: UUID?,
        light: AmbientLight?, names: [UUID: String], at time: Date
    ) {
        if newTrack != track { startTrack(newTrack) }
        let member = subject.memberID
        let comparable = templates.mapValues { stored in
            stored.templates.filter { !keptThisTrack.contains($0.learnedAt) }.map(\.signature)
        }
        let score = DepthIdentityScore.score(signature, member: member, templates: comparable)
        PresenceTrace.trace.log(Self.describe(score, member: member, light: light, expression: expression, names: names))
        if let member, newTrack != nil, policy.mayKeep(light: light, keptOnTrack: keptOnTrack, lastKeptAt: lastKeptAt, at: time) {
            keep(signature, for: member, at: time, names: names)
        }
    }

    private func keep(_ signature: DepthSignature, for member: UUID, at time: Date, names: [UUID: String]) {
        var updated = templates[member] ?? MemberDepthTemplates(memberID: member, templates: [])
        updated.append(DepthTemplate(signature: signature, learnedAt: time), cap: policy.capPerMember)
        do {
            try store?.saveDepth(updated)
        } catch {
            // Complete protection: nothing can be written while the iPad is locked.
            PresenceTrace.trace.log("depth template not saved: \(error.localizedDescription)")
            return
        }
        templates[member] = updated
        keptOnTrack += 1
        lastKeptAt = time
        keptThisTrack.insert(time)
        PresenceTrace.trace.log("depth template added for \(names[member] ?? "?"), "
            + "\(updated.templates.count) of \(policy.capPerMember)")
    }

    private func startTrack(_ newTrack: UUID?) {
        track = newTrack
        keptOnTrack = 0
        lastKeptAt = nil
        keptThisTrack.removeAll()
    }

    private func endTrack() {
        startTrack(nil)
    }

    /// "depth identity Kyle, light dim, expression 0.12: own 1.42mm nearest of 8,
    /// others 2.95mm nearest of 6 (Sam)". Distances, counts and names only.
    nonisolated static func describe(
        _ score: DepthIdentityScore, member: UUID?, light: AmbientLight?, expression: Double, names: [UUID: String]
    ) -> String {
        let who = member.map { names[$0] ?? "?" } ?? "stranger"
        let lightText = light.map { "\($0)" } ?? "unknown"
        var text = "depth identity \(who), light \(lightText), expression \(String(format: "%.2f", expression)): "
        if member != nil {
            text += score.own.map { "own \(millimeters($0)) nearest of \(score.ownCount), " } ?? "no own templates yet, "
        }
        let otherName = score.otherMember.map { names[$0] ?? "?" } ?? "-"
        text += score.other.map { "others \(millimeters($0)) nearest of \(score.otherCount) (\(otherName))" } ?? "no others"
        return text
    }

    nonisolated private static func millimeters(_ value: Double) -> String { String(format: "%.2fmm", value) }
}
