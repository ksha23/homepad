import CoreGraphics
import Foundation
import simd

/// One face ARKit tracks in a frame: its anchor and position for the face
/// track, and its point in the image for the depth person.
struct ARKitFace: Equatable, Sendable {
    var anchor: UUID
    /// Position in camera space, in meters.
    var position: SIMD3<Float>
    var image: FaceInImage

    var tracked: FaceTrackContinuity.TrackedFace {
        FaceTrackContinuity.TrackedFace(anchor: anchor, position: position)
    }
}

/// A face Vision found, where ARKit tracks none.
struct VisionFace: Equatable, Sendable {
    /// The face's center in the native image, normalized, top-left origin.
    var point: CGPoint
    /// Its distance by its size, when the field of view is known.
    var expectedMeters: Double?
}

/// Follows the face in view and the person it belongs to, frame by frame:
/// the depth person (`DepthSensing`) and the face track
/// (`FaceTrackContinuity`) that recognition's looks and learning follow.
///
/// Every ARKit frame comes through `arkitFrame`, also the frames the analyzer
/// skips. An analyzed frame on which ARKit tracks no face but Vision finds
/// one comes through `visionFaces` afterwards. Such a face seeds or confirms
/// the depth person like an ARKit face, and starts or continues the face
/// track on that person, so a look holds while someone sits with their head
/// turned and ARKit never tracks them.
///
/// Used on the analysis queue only.
struct FaceFollower {
    private(set) var tracks = FaceTrackContinuity()

    /// Notes one ARKit frame, after its depth (if any) was ingested into
    /// `depth`. Returns the face track.
    mutating func arkitFrame(_ faces: [ARKitFace], hasNewDepth: Bool, depth: inout DepthSensing, at time: TimeInterval) -> UUID? {
        let person = depth.follow(faces.map(\.image), hasNewDepth: hasNewDepth, at: time)
        let track = tracks.update(tracked: faces.map(\.tracked), depthPerson: person, at: time)
        if let gap = tracks.takeBridgedGap() {
            depth.note(TraceNote(key: "face track", text: "face back after \(String(format: "%.1f", gap)) s, "
                + "on the same depth person: the look goes on"))
        }
        return track
    }

    /// Notes the faces Vision found on an analyzed frame where ARKit tracks
    /// none. Returns the face track.
    mutating func visionFaces(_ faces: [VisionFace], depth: inout DepthSensing, at time: TimeInterval) -> UUID? {
        guard faces.count == 1, let face = faces.first else {
            return tracks.noteVisionFaces(count: faces.count, depth: .unknown, at: time)
        }
        let before = tracks.trackID
        let found = depth.followVisionFace(at: face.point, expectedMeters: face.expectedMeters, at: time)
        let track = tracks.noteVisionFaces(count: 1, depth: found, at: time)
        if track != before, let track {
            depth.note(TraceNote(key: "face track", text: "face track \(String(track.uuidString.prefix(4))) "
                + "started from a face only Vision found"))
        }
        return track
    }

    /// Starts over, as when face tracking starts.
    mutating func reset() {
        tracks = FaceTrackContinuity()
    }
}
