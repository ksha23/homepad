import Foundation
import HomePadCore

/// Fuses a stream of `SensorObservation`s into one `PresenceSnapshot`.
///
/// - Starts presence only on a confirmed sighting, so one false detection does
///   not flip the screen to "someone" and back.
/// - Smooths distance and applies proximity hysteresis.
/// - Holds presence for a short time after the last detection, so a face that
///   turns away for a moment does not flip the UI to "nobody".
/// - Treats microphone activity as presence at an unknown distance, with a longer hold.
struct PresenceFusion: Sendable {
    struct Config: Sendable {
        /// Seconds a camera detection keeps someone "present".
        var holdSeconds: TimeInterval = 3
        /// Seconds a microphone detection keeps someone "present".
        var voiceHoldSeconds: TimeInterval = 45
        var hysteresisMeters = 0.15
        /// A sighting starts presence only when another follows within this many
        /// seconds. Noise in the depth map or a coat that looks like shoulders
        /// shows up for a frame, a person stays. ARKit faces start it at once.
        var confirmSeconds: TimeInterval = 2
        /// Sightings closer together than this are one moment, not a confirmation.
        var confirmGapSeconds: TimeInterval = 0.25
        /// While no camera frame arrives at all (the camera is switching paths),
        /// presence holds up to this long: no frame is not an empty room.
        var stallHoldSeconds: TimeInterval = 8
    }

    var config = Config()
    private(set) var snapshot = PresenceSnapshot.empty
    private var smoother = DistanceSmoother()
    private var lastCameraDetection: Date?
    /// Last camera observation, with or without anyone in it.
    private var lastCameraFrame: Date?
    private var unconfirmedSighting: Date?
    /// Face distance over body estimate, learned while both are seen. Kept when
    /// presence ends, since it mostly depends on this camera and its framing.
    private(set) var bodyScale = 1.0
    /// When a frame last measured the room's light.
    private(set) var lastLuxAt: Date?
    private var lastVoiceDetection: Date?

    /// Last time a camera saw a person. Drives the duty cycle.
    var lastCameraPresenceAt: Date? { lastCameraDetection }

    mutating func ingest(_ observation: SensorObservation) -> PresenceSnapshot {
        let now = observation.timestamp
        if let lux = observation.ambientLux {
            snapshot.ambientLight = AmbientLightMath.level(lux: lux, current: snapshot.ambientLight)
            let elapsed = lastLuxAt.map { now.timeIntervalSince($0) } ?? 0
            snapshot.ambientLux = AmbientLightMath.smoothed(
                lux: lux, previous: snapshot.ambientLux, elapsed: elapsed,
                timeConstant: AmbientLightMath.timeConstant(for: snapshot.proximity)
            )
            lastLuxAt = now
        }
        if observation.motion || observation.voiceActivity || observation.detectsPerson {
            snapshot.lastActivity = now
        }
        if observation.source != .microphone { lastCameraFrame = now }
        if observation.detectsPerson && (snapshot.isSomeonePresent || confirms(observation)) {
            lastCameraDetection = now
            applyDetection(observation)
        } else if observation.voiceActivity {
            lastVoiceDetection = now
            if !isCameraPresenceFresh(at: now) { applyVoice(observation) }
        }
        expireIfNeeded(now: now)
        return snapshot
    }

    /// Call when time passes without observations (sensor paused) to let
    /// presence lapse.
    mutating func tick(now: Date) -> PresenceSnapshot {
        expireIfNeeded(now: now)
        return snapshot
    }

    /// Sets the recognized member, kept until nobody is present.
    mutating func setRecognizedMember(_ id: UUID?) {
        snapshot.recognizedMemberID = id
    }

    mutating func reset() {
        let light = snapshot.ambientLight
        let activity = snapshot.lastActivity
        snapshot = PresenceSnapshot(ambientLight: light, lastActivity: activity)
        smoother.reset()
        lastCameraDetection = nil
        lastCameraFrame = nil
        unconfirmedSighting = nil
        lastVoiceDetection = nil
    }

    // MARK: Private

    /// True for an ARKit face, or for a new sighting that follows an earlier one
    /// within `confirmSeconds`. Otherwise remembers the sighting and waits.
    private mutating func confirms(_ observation: SensorObservation) -> Bool {
        if observation.facesAreTracked && !observation.faces.isEmpty { return true }
        guard observation.isFreshSighting else { return false }
        let now = observation.timestamp
        if let first = unconfirmedSighting, now.timeIntervalSince(first) <= config.confirmSeconds {
            guard now.timeIntervalSince(first) >= config.confirmGapSeconds else { return false }
            unconfirmedSighting = nil
            return true
        }
        unconfirmedSighting = now
        return false
    }

    private mutating func applyDetection(_ observation: SensorObservation) {
        snapshot.isSomeonePresent = true
        snapshot.source = observation.source
        snapshot.peopleCount = max(observation.faces.count, observation.bodyCount, 1)
        snapshot.isLookingAtScreen = observation.faces.contains { $0.isLookingAtScreen }
        let faceDistance = observation.faces.compactMap(\.distanceMeters).min()
        if let faceDistance, let body = observation.bodyEstimateMeters, body > 0 {
            bodyScale += 0.3 * (min(max(faceDistance / body, 0.4), 2.5) - bodyScale)
        }
        // Looking down or away loses the face, not the person: the body box keeps
        // the distance. Without it the face jumped to its far layout and back.
        // Depth measured at the followed head comes first: in the dark ARKit
        // loses the face and misjudges how far it is, and the depth map does not.
        let bodyDistance = observation.bodyEstimateMeters.map { $0 * bodyScale }
        if let raw = observation.depthPersonMeters ?? faceDistance ?? observation.nearestBodyMeters ?? bodyDistance {
            let smoothed = smoother.add(raw)
            snapshot.nearestDistanceMeters = smoothed
            snapshot.proximity = ProximityMath.level(
                for: smoothed, current: snapshot.proximity, margin: config.hysteresisMeters
            )
        } else {
            // Seen but too small or too far to measure.
            smoother.reset()
            snapshot.nearestDistanceMeters = nil
            snapshot.proximity = .far
        }
    }

    private mutating func applyVoice(_ observation: SensorObservation) {
        snapshot.isSomeonePresent = true
        snapshot.source = observation.source
        snapshot.peopleCount = max(snapshot.peopleCount, 1)
        snapshot.isLookingAtScreen = false
        snapshot.nearestDistanceMeters = nil
        snapshot.proximity = .far
        smoother.reset()
    }

    private func isCameraPresenceFresh(at now: Date) -> Bool {
        guard let last = lastCameraDetection else { return false }
        let age = now.timeIntervalSince(last)
        if age <= config.holdSeconds { return true }
        let stalled = (lastCameraFrame ?? .distantPast) <= last
        return stalled && age <= config.stallHoldSeconds
    }

    private func isVoicePresenceFresh(at now: Date) -> Bool {
        guard let last = lastVoiceDetection else { return false }
        return now.timeIntervalSince(last) <= config.voiceHoldSeconds
    }

    private mutating func expireIfNeeded(now: Date) {
        guard snapshot.isSomeonePresent else { return }
        if isCameraPresenceFresh(at: now) { return }
        if isVoicePresenceFresh(at: now) {
            if snapshot.source != .microphone {
                snapshot.source = .microphone
                snapshot.proximity = .far
                snapshot.nearestDistanceMeters = nil
                snapshot.isLookingAtScreen = false
                smoother.reset()
            }
            return
        }
        let light = snapshot.ambientLight
        let activity = snapshot.lastActivity
        snapshot = PresenceSnapshot(ambientLight: light, lastActivity: activity)
        smoother.reset()
    }
}
