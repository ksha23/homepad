import Foundation

/// Splits what the camera sees into looks: one unbroken view of one face.
/// Recognition decides about each look from scratch, so a different person
/// stepping in front of the iPad is identified on their own votes.
///
/// - With ARKit face tracking a look is one face track (`FaceTrackContinuity`).
///   A dropout of up to half a second keeps it (ARKit drops the face often in
///   the dark), while a longer one, a second face or a new anchor starts a new one.
/// - With several faces in view, or on the RGB path, there is no single track.
///   A look then lasts while at least one face stays in view.
/// - No face in view ends the look.
struct FaceLookTracker: Equatable, Sendable {
    /// The current look, nil while no face is in view.
    private(set) var look: UUID?
    /// The face track the look follows, nil for an untracked look.
    private var track: UUID?

    /// Notes the faces of one analyzed frame. Returns true when a new look started.
    mutating func note(faceCount: Int, track newTrack: UUID?) -> Bool {
        guard faceCount > 0 || newTrack != nil else {
            end()
            return false
        }
        return follow(newTrack)
    }

    /// Notes the track of a recognition sample, for callers that do not report
    /// whole frames. Returns true when a new look started.
    mutating func noteSample(track newTrack: UUID?) -> Bool {
        guard newTrack != nil || look == nil else { return false }
        return follow(newTrack)
    }

    mutating func end() {
        look = nil
        track = nil
    }

    private mutating func follow(_ newTrack: UUID?) -> Bool {
        if look != nil, newTrack == track { return false }
        look = UUID()
        track = newTrack
        return true
    }
}
