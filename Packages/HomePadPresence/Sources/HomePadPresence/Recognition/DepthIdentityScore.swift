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
    /// Distance to the nearest template of a third member, after `otherMember`.
    var runnerUp: Double?

    /// Scores `signature` of the face RGB recognition named `member` (nil for
    /// a stranger) against each member's templates.
    static func score(_ signature: DepthSignature, member: UUID?, templates: [UUID: [DepthSignature]]) -> DepthIdentityScore {
        var score = DepthIdentityScore()
        var others: [(member: UUID, distance: Double)] = []
        for (id, signatures) in templates {
            let nearest = signatures.compactMap { signature.distance(to: $0) }.min()
            if id == member {
                score.own = nearest
                score.ownCount = signatures.count
                continue
            }
            score.otherCount += signatures.count
            if let nearest { others.append((id, nearest)) }
        }
        others.sort { $0.distance < $1.distance }
        score.other = others.first?.distance
        score.otherMember = others.first?.member
        score.runnerUp = others.dropFirst().first?.distance
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
    /// Templates a member needs before depth may name them (`DepthCalibration`).
    var minimumTemplates = 3
    /// With templates from one sitting only, the limit is this times the
    /// largest distance between them, at least `oneSittingFloor`. One sitting
    /// shows less of how a face varies than several do. The owner's face in
    /// the dark came 0.8 mm from his templates from light.
    var oneSittingFactor = 2.0
    var oneSittingFloor = 1.0
    /// Templates further apart in time than this are from different visits:
    /// separate sittings. At 60 s one evening counted as 6 visits, which makes
    /// a face look steadier than it is.
    var visitGap: TimeInterval = 600
    /// The match limit is this times the 95th percentile of a member's own
    /// distances across visits, never more than `maximumThreshold`.
    var thresholdFactor = 1.25
    /// Millimeters. Templates from builds with the nose tip off the nose
    /// once set a limit of 7.5 mm, which anyone would pass. The owner's own
    /// face in the dark came 0.8 mm from his templates.
    var maximumThreshold = 1.5
    /// Depth names a member when this many of the last `depthWindow`
    /// signatures came under their limit.
    var requiredDepthVotes = 3
    var depthWindow = 4
    /// And the nearest other member is at least this many times farther.
    var marginFactor = 1.25
    /// Seconds between signatures while a face just set up is learned
    /// (`DepthIdentityEvaluator.learnQuickly`).
    var quickInterval: TimeInterval = 1

    /// While a member's face is being set up: more templates from the one
    /// look, closer together.
    var quick: DepthTemplatePolicy {
        var rules = self
        rules.perTrackLimit = minimumTemplates * 2
        rules.minimumSpacing = 3
        return rules
    }

    /// True when a signature of a member confirmed on this look may become a
    /// template. RGB recognition labels it, and it is most reliable in light.
    func mayKeep(light: AmbientLight?, keptOnTrack: Int, lastKeptAt: Date?, at time: Date) -> Bool {
        guard let light, light != .dark, keptOnTrack < perTrackLimit else { return false }
        return lastKeptAt.map { time.timeIntervalSince($0) >= minimumSpacing } ?? true
    }
}
