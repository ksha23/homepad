import Foundation
import HomePadCore

/// How one depth signature scores against the stored depth templates.
/// Distances are in millimeters, smaller is more alike. Only these numbers,
/// counts and names reach the trace.
struct DepthIdentityScore: Equatable, Sendable {
    /// Distance to the nearest template of the member RGB recognition named,
    /// nil for a stranger or a member without templates yet.
    var own: Double?
    /// Templates of that member it was compared with.
    var ownCount = 0
    /// Distance to the nearest template of anyone else, and whose it is.
    var other: Double?
    var otherMember: UUID?
    /// Templates of everyone else it was compared with.
    var otherCount = 0

    /// Scores `signature` of the face RGB recognition named `member` (nil for
    /// a stranger) against each member's templates.
    static func score(_ signature: DepthSignature, member: UUID?, templates: [UUID: [DepthSignature]]) -> DepthIdentityScore {
        var score = DepthIdentityScore()
        for (id, signatures) in templates {
            let nearest = signatures.compactMap { signature.distance(to: $0) }.min()
            if id == member {
                score.own = nearest
                score.ownCount = signatures.count
                continue
            }
            score.otherCount += signatures.count
            if let nearest, nearest < (score.other ?? .infinity) {
                score.other = nearest
                score.otherMember = id
            }
        }
        return score
    }
}

/// When depth signatures are taken, scored and kept as templates.
struct DepthTemplatePolicy: Equatable, Sendable {
    /// Seconds between two signatures of a face in view.
    var sampleInterval: TimeInterval = 3
    /// Templates kept per member. The oldest roll out.
    var capPerMember = 20
    /// Templates kept from one face track at most, so the templates come from
    /// many visits, and scoring a visit against the others is honest.
    var perTrackLimit = 3
    /// Seconds between two templates kept from one track at least.
    var minimumSpacing: TimeInterval = 10

    /// True when a signature of a member confirmed on this look may become a
    /// template. RGB recognition labels it, and it is most reliable in light.
    func mayKeep(light: AmbientLight?, keptOnTrack: Int, lastKeptAt: Date?, at time: Date) -> Bool {
        guard let light, light != .dark, keptOnTrack < perTrackLimit else { return false }
        return lastKeptAt.map { time.timeIntervalSince($0) >= minimumSpacing } ?? true
    }
}
