import Foundation
import HomePadCore

/// A depth signature of the face in view, with how far from resting its
/// expression was (the largest ARKit blend shape, eyes left out).
struct DepthSignatureSample: Sendable {
    var signature: DepthSignature
    var expression: Double
}

/// Depth identity, evaluation only (`DepthIdentityEvaluator`). Nothing here
/// changes who recognition says the face is.
extension FaceRecognitionService {
    /// True while signatures of the face in view are worth taking: RGB
    /// recognition has named it a member or settled it as a stranger, or
    /// there are depth templates to score a face it has not named against.
    var wantsDepthSignatures: Bool {
        guard isEnabled, !templates.isEmpty else { return false }
        return confirmedMemberID != nil || lookIdentity == .stranger || depthIdentity.hasTemplates
    }

    /// Scores a depth signature of the face in view on face track `track`.
    func considerDepthSignature(_ sample: DepthSignatureSample, track: UUID?, light: AmbientLight?, at time: Date = Date()) {
        guard isEnabled else { return }
        let subject: DepthIdentityEvaluator.Subject
        if let member = confirmedMemberID {
            subject = .member(member)
        } else if lookIdentity == .stranger {
            subject = .stranger
        } else if depthIdentity.hasTemplates {
            subject = .unnamed
        } else {
            return
        }
        let names = Dictionary(services.household.members.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        depthIdentity.consider(
            sample.signature, expression: sample.expression, subject: subject, track: track,
            light: light, names: names, at: time
        )
    }
}
