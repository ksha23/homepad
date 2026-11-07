import Foundation
import simd

/// Follows one face through ARKit face tracking without a break, so learning
/// from use only ever sees the person who was recognized, and recognition's
/// votes for one look are all about one face.
///
/// Fed with the tracked face anchors of every ARKit frame, including the frames
/// the analyzer skips. A track lasts while exactly one face anchor is tracked
/// and it keeps its identifier.
///
/// In a dark room ARKit drops the tracked face on about half the frames, often
/// for seconds, while the TrueDepth sensor still sees the head. A gap keeps
/// the track in two cases:
///
/// - A short one: the same anchor back within `grace`, and within
///   `maximumJump` of where it was lost. ARKit may reuse an anchor for whoever
///   comes next, which is why the gap must be short and the face back in place.
/// - A longer one, up to `depthGrace`, while the depth person tracker follows
///   the same person the face belonged to without a break, and the face that
///   comes back is on that person's head (`DepthPersonTracker`). The anchor
///   may then be a new one.
///
/// Anything else ends it: a longer gap, a face back somewhere else, a second
/// face, or a different anchor without a gap.
///
/// ARKit often tracks no face at all while someone sits with their head
/// turned, and Vision still finds the face in the image. Such a face counts
/// too (`noteVisionFaces`): on the depth person it lies on, it starts a track,
/// or keeps the one that person already has. A face on another person, or
/// off the followed head, starts a new one, and two faces end it.
///
/// Used on the analysis queue only.
struct FaceTrackContinuity: Equatable, Sendable {
    /// One tracked face anchor in a frame, with its position in camera space.
    struct TrackedFace: Equatable, Sendable {
        var anchor: UUID
        var position: SIMD3<Float>
    }

    /// How long ARKit may lose the face before the track ends, in seconds.
    static let grace: TimeInterval = 0.5
    /// How long the depth of the same person can hold the track, in seconds.
    static let depthGrace: TimeInterval = 30
    /// How far the face may be from where it was lost when it comes back, in meters.
    static let maximumJump: Float = 0.15

    private var anchorID: UUID?
    private var lastPosition: SIMD3<Float>?
    private var lostAt: TimeInterval?
    /// The depth person the face belonged to when it was last seen.
    private var personAtFace: UUID?
    private(set) var trackID: UUID?
    /// How long the last gap the depth bridged lasted, until read with
    /// `takeBridgedGap()`, for the presence trace.
    private var bridgedGap: TimeInterval?

    /// Notes the faces ARKit tracks in one frame at `time` (seconds).
    /// `depthPerson` is the person the depth tracker follows, when the faces
    /// are on their head or no face is in view (`DepthSensing.follow`).
    /// Returns the current track, or nil when there is no single tracked face.
    mutating func update(tracked faces: [TrackedFace], depthPerson: UUID? = nil, at time: TimeInterval) -> UUID? {
        if faces.count > 1 {
            end()
            return nil
        }
        guard let face = faces.first else {
            return noteGap(at: time, depthPerson: depthPerson)
        }
        if continues(with: face, at: time, depthPerson: depthPerson) {
            if let lostAt, time - lostAt > Self.grace { bridgedGap = time - lostAt }
        } else {
            trackID = UUID()
        }
        anchorID = face.anchor
        lastPosition = face.position
        lostAt = nil
        personAtFace = depthPerson
        return trackID
    }

    /// What the depth says about a face only Vision found (`DepthSensing.followVisionFace`).
    enum VisionFaceDepth: Equatable, Sendable {
        /// The face is on this depth person, followed before or just picked up.
        case person(UUID)
        /// The face is not on the followed head, and the depth has no one there.
        case elsewhere
        /// The depth cannot tell: no recent depth map, or none under the face.
        case unknown
    }

    /// Notes the faces Vision found on an analyzed frame where ARKit tracks
    /// none, after `update` ran for that frame. Returns the current track.
    mutating func noteVisionFaces(count: Int, depth: VisionFaceDepth, at time: TimeInterval) -> UUID? {
        guard count == 1 else {
            if count > 1 { end() }
            return trackID
        }
        switch depth {
        case .unknown:
            return trackID
        case .elsewhere:
            end()
            return nil
        case .person(let person):
            if trackID == nil || person != personAtFace { trackID = UUID() }
            // No anchor: whichever anchor ARKit gives this face next continues
            // the track when it is on the same depth person.
            anchorID = nil
            lastPosition = nil
            lostAt = nil
            personAtFace = person
            return trackID
        }
    }

    /// The length of a gap the depth bridged since the last call, if any.
    mutating func takeBridgedGap() -> TimeInterval? {
        defer { bridgedGap = nil }
        return bridgedGap
    }

    /// No tracked face in this frame: the track holds through a short gap, or
    /// a longer one while the depth still follows the same person.
    private mutating func noteGap(at time: TimeInterval, depthPerson: UUID?) -> UUID? {
        guard trackID != nil else { return nil }
        let start = lostAt ?? time
        lostAt = start
        let gap = time - start
        if gap <= Self.grace || (isSamePerson(depthPerson) && gap <= Self.depthGrace) {
            return trackID
        }
        end()
        return nil
    }

    /// True when `face` is the face of the current track: the same anchor
    /// without a gap, and after a gap, back in time and in place, or on the
    /// head of the same person the depth followed throughout. After a face
    /// only Vision saw there is no anchor, and the depth person decides.
    private func continues(with face: TrackedFace, at time: TimeInterval, depthPerson: UUID?) -> Bool {
        guard trackID != nil else { return false }
        let gap = lostAt.map { time - $0 }
        if face.anchor == anchorID {
            guard let gap else { return true }
            if gap <= Self.grace, let lastPosition, simd_distance(face.position, lastPosition) <= Self.maximumJump {
                return true
            }
        }
        guard gap != nil || anchorID == nil else { return false }
        return isSamePerson(depthPerson) && (gap ?? 0) <= Self.depthGrace
    }

    private func isSamePerson(_ depthPerson: UUID?) -> Bool {
        guard let depthPerson else { return false }
        return depthPerson == personAtFace
    }

    private mutating func end() {
        anchorID = nil
        lastPosition = nil
        lostAt = nil
        personAtFace = nil
        trackID = nil
    }
}
