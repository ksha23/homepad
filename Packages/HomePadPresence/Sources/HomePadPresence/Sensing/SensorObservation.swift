import CoreGraphics
import Foundation
import HomePadCore

/// One face seen in a frame.
struct DetectedFace: Equatable, Sendable {
    /// Distance from the camera in meters, when it could be measured.
    var distanceMeters: Double?
    var isLookingAtScreen: Bool
    /// Normalized bounding box in the upright image (Vision coordinates), if known.
    var boundingBox: CGRect?

    init(distanceMeters: Double?, isLookingAtScreen: Bool, boundingBox: CGRect? = nil) {
        self.distanceMeters = distanceMeters
        self.isLookingAtScreen = isLookingAtScreen
        self.boundingBox = boundingBox
    }
}

/// What one sensing path saw at one moment. Backends produce these and
/// `PresenceFusion` turns a stream of them into a `PresenceSnapshot`.
struct SensorObservation: Sendable {
    var timestamp: Date
    var source: PresenceSource
    var faces: [DetectedFace] = []
    /// People seen without a usable face (human rectangles or a depth blob).
    var bodyCount = 0
    /// Distance to the nearest body from the depth map, if any.
    var nearestBodyMeters: Double?
    /// Frame differencing saw something move.
    var motion = false
    /// Microphone heard activity (used when cameras are off).
    var voiceActivity = false
    /// Approximate scene illuminance.
    var ambientLux: Double?
    /// The faces come from ARKit face tracking, which only follows a real 3D
    /// face, so one sighting is enough to start presence.
    var facesAreTracked = false
    /// This frame looked for people itself. A body count carried over between
    /// human checks keeps presence going but is not a new sighting.
    var isFreshSighting = true
    /// Best human rectangle confidence, for the presence trace.
    var humanConfidence: Double?
    /// Largest patch of moving depth as a share of the frame, for the presence trace.
    var depthBlobFraction: Double?
    /// Seconds since the newest depth map was captured, for the presence trace.
    var depthAgeSeconds: Double?
    /// Distance to the nearest person from the width of their upper-body box.
    /// Rough, so fusion scales it by what faces measured.
    var bodyEstimateMeters: Double?
    /// Depth of the head of the person TrueDepth follows (`DepthPersonTracker`),
    /// measured from the depth map. Holds presence while ARKit loses the face
    /// in the dark, and is the most direct distance there is.
    var depthPersonMeters: Double?
    /// The followed person, the same while they stay followed.
    var depthPersonID: UUID?

    var detectsPerson: Bool { !faces.isEmpty || bodyCount > 0 || depthPersonMeters != nil }

    /// The nearest person's distance, from the best source this frame had:
    /// depth measured at their head, then ARKit or Vision faces, then a
    /// moving depth patch, then the upper-body box.
    var nearestPersonMeters: Double? {
        depthPersonMeters ?? faces.compactMap(\.distanceMeters).min() ?? nearestBodyMeters ?? bodyEstimateMeters
    }
}
