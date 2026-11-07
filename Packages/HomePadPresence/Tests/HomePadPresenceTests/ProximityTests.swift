import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

@Suite struct ProximityMathTests {
    @Test func focalLengthFromFieldOfView() throws {
        // 90 degrees across 1000 px puts the focal length at half the width.
        let focal = try #require(ProximityMath.focalLengthPixels(imageWidth: 1000, horizontalFOVDegrees: 90))
        #expect(abs(focal - 500) < 0.001)
        #expect(ProximityMath.focalLengthPixels(imageWidth: 1000, horizontalFOVDegrees: 0) == nil)
    }

    @Test func distanceFromFaceWidth() throws {
        // A 16 cm face spanning 80 px with a 500 px focal length is 1 m away.
        let distance = try #require(ProximityMath.distanceMeters(faceWidthPixels: 80, focalLengthPixels: 500))
        #expect(abs(distance - 1.0) < 0.001)
        // Half the width means twice the distance.
        let farther = try #require(ProximityMath.distanceMeters(faceWidthPixels: 40, focalLengthPixels: 500))
        #expect(abs(farther - 2.0) < 0.001)
        #expect(ProximityMath.distanceMeters(faceWidthPixels: 0, focalLengthPixels: 500) == nil)
    }

    @Test func sharedThresholds() {
        #expect(ProximityLevel.from(distanceMeters: 0.5) == .near)
        #expect(ProximityLevel.from(distanceMeters: 1.5) == .mid)
        #expect(ProximityLevel.from(distanceMeters: 3.5) == .far)
    }

    @Test func hysteresisHoldsLevelNearBoundary() {
        // Standing just past the 1 m boundary does not flip mid to near.
        #expect(ProximityMath.level(for: 0.95, current: .mid, margin: 0.15) == .mid)
        // Clearly inside does.
        #expect(ProximityMath.level(for: 0.8, current: .mid, margin: 0.15) == .near)
        // Leaving near needs to clear the boundary by the margin too.
        #expect(ProximityMath.level(for: 1.05, current: .near, margin: 0.15) == .near)
        #expect(ProximityMath.level(for: 1.2, current: .near, margin: 0.15) == .mid)
        // From nobody the raw level applies immediately.
        #expect(ProximityMath.level(for: 0.95, current: .nobody, margin: 0.15) == .near)
    }

    @Test func smootherDampsJitterAndResetsOnJumps() {
        var smoother = DistanceSmoother(alpha: 0.5, resetJumpMeters: 1.0)
        #expect(smoother.add(2.0) == 2.0)
        #expect(abs(smoother.add(2.2) - 2.1) < 0.0001)
        // A different person much closer resets instead of averaging.
        #expect(smoother.add(0.6) == 0.6)
    }
}

@Suite struct PresenceFusionTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func face(_ distance: Double, looking: Bool = false) -> DetectedFace {
        DetectedFace(distanceMeters: distance, isLookingAtScreen: looking)
    }

    @Test func detectionSetsPresenceAndHoldsBriefly() {
        var fusion = PresenceFusion()
        let seen = fusion.ingest(SensorObservation(timestamp: start, source: .trueDepth, faces: [face(0.7, looking: true)], facesAreTracked: true))
        #expect(seen.isSomeonePresent)
        #expect(seen.proximity == .near)
        #expect(seen.isLookingAtScreen)
        #expect(seen.peopleCount == 1)
        // The next frame sees nobody.
        _ = fusion.ingest(SensorObservation(timestamp: start.addingTimeInterval(0.5), source: .trueDepth))
        // A missed frame inside the hold keeps presence.
        let held = fusion.tick(now: start.addingTimeInterval(fusion.config.holdSeconds - 0.5))
        #expect(held.isSomeonePresent)
        // After the hold, nobody.
        let gone = fusion.tick(now: start.addingTimeInterval(fusion.config.holdSeconds + 0.5))
        #expect(gone.isSomeonePresent == false)
        #expect(gone.proximity == .nobody)
    }

    @Test func peopleWithoutMeasurableFacesAreFar() {
        var fusion = PresenceFusion()
        _ = fusion.ingest(SensorObservation(timestamp: start, source: .frontCamera, bodyCount: 2))
        let snapshot = fusion.ingest(SensorObservation(timestamp: start.addingTimeInterval(0.5), source: .frontCamera, bodyCount: 2))
        #expect(snapshot.isSomeonePresent)
        #expect(snapshot.peopleCount == 2)
        #expect(snapshot.proximity == .far)
        #expect(snapshot.nearestDistanceMeters == nil)
    }

    /// The new iPad flipped to "someone" and back when things in the room changed
    /// slightly: one frame's false detection was enough to start presence.
    @Test func oneSightingDoesNotStartPresence() {
        var fusion = PresenceFusion()
        #expect(fusion.ingest(SensorObservation(timestamp: start, source: .trueDepth, bodyCount: 1)).isSomeonePresent == false)
        // A second sighting too long after is a new first sighting, not a confirmation.
        let late = start.addingTimeInterval(fusion.config.confirmSeconds + 0.5)
        #expect(fusion.ingest(SensorObservation(timestamp: late, source: .trueDepth, bodyCount: 1)).isSomeonePresent == false)
        // Nor does a Vision face, which can be a pattern or a photo.
        var faces = PresenceFusion()
        #expect(faces.ingest(SensorObservation(timestamp: start, source: .frontCamera, faces: [face(2)])).isSomeonePresent == false)
        #expect(faces.ingest(SensorObservation(timestamp: start.addingTimeInterval(0.5), source: .frontCamera, faces: [face(2)])).isSomeonePresent)
    }

    @Test func sightingsInTheSameMomentDoNotConfirm() {
        var fusion = PresenceFusion()
        _ = fusion.ingest(SensorObservation(timestamp: start, source: .trueDepth, bodyCount: 1))
        #expect(fusion.ingest(SensorObservation(timestamp: start.addingTimeInterval(0.1), source: .trueDepth, bodyCount: 1)).isSomeonePresent == false)
        #expect(fusion.ingest(SensorObservation(timestamp: start.addingTimeInterval(0.3), source: .trueDepth, bodyCount: 1)).isSomeonePresent)
    }

    @Test func carriedBodyCountsHoldPresenceButDoNotStartIt() {
        var fusion = PresenceFusion()
        _ = fusion.ingest(SensorObservation(timestamp: start, source: .trueDepth, bodyCount: 1))
        let carried = SensorObservation(timestamp: start.addingTimeInterval(0.5), source: .trueDepth, bodyCount: 1, isFreshSighting: false)
        #expect(fusion.ingest(carried).isSomeonePresent == false)
        _ = fusion.ingest(SensorObservation(timestamp: start.addingTimeInterval(1), source: .trueDepth, bodyCount: 1))
        #expect(fusion.snapshot.isSomeonePresent)
        let held = SensorObservation(timestamp: start.addingTimeInterval(1 + fusion.config.holdSeconds - 0.5), source: .trueDepth,
                                     bodyCount: 1, isFreshSighting: false)
        _ = fusion.ingest(held)
        #expect(fusion.tick(now: start.addingTimeInterval(1 + fusion.config.holdSeconds + 1)).isSomeonePresent)
    }

    /// Looking down lost the face, and the face switched to its far layout until
    /// the face came back. The body box keeps the distance, calibrated on the face.
    @Test func losingTheFaceKeepsTheDistanceFromTheBody() {
        var fusion = PresenceFusion()
        // The face is 0.8 m away, the body box alone says 1 m.
        for step in 0..<6 {
            _ = fusion.ingest(SensorObservation(timestamp: start.addingTimeInterval(Double(step) * 0.1), source: .trueDepth,
                                                faces: [face(0.8)], bodyCount: 1, facesAreTracked: true, bodyEstimateMeters: 1))
        }
        #expect(fusion.snapshot.proximity == .near)
        let lookingDown = fusion.ingest(SensorObservation(timestamp: start.addingTimeInterval(1), source: .trueDepth, bodyCount: 1,
                                                          facesAreTracked: true, isFreshSighting: false, bodyEstimateMeters: 1))
        #expect(lookingDown.proximity == .near)
        #expect(abs((lookingDown.nearestDistanceMeters ?? 0) - 0.8) < 0.1)
        // Walking away shrinks the box: far again at once.
        let away = fusion.ingest(SensorObservation(timestamp: start.addingTimeInterval(2), source: .trueDepth, bodyCount: 1,
                                                   facesAreTracked: true, bodyEstimateMeters: 4))
        #expect(away.proximity == .far)
    }

    /// Presence lapsed right after it was noticed, because the switch from the
    /// room scan to face tracking delivered no frames for several seconds.
    @Test func noFramesIsNotAnEmptyRoom() {
        var fusion = PresenceFusion()
        _ = fusion.ingest(SensorObservation(timestamp: start, source: .trueDepth, faces: [face(1.5)], facesAreTracked: true))
        #expect(fusion.tick(now: start.addingTimeInterval(fusion.config.holdSeconds + 2)).isSomeonePresent)
        #expect(fusion.tick(now: start.addingTimeInterval(fusion.config.stallHoldSeconds + 1)).isSomeonePresent == false)
        // Frames that see nobody end it after the usual hold.
        var seen = PresenceFusion()
        _ = seen.ingest(SensorObservation(timestamp: start, source: .trueDepth, faces: [face(1.5)], facesAreTracked: true))
        _ = seen.ingest(SensorObservation(timestamp: start.addingTimeInterval(1), source: .trueDepth))
        #expect(seen.tick(now: start.addingTimeInterval(seen.config.holdSeconds + 0.5)).isSomeonePresent == false)
    }

    @Test func voiceActivityCountsAsFarPresenceWithLongerHold() {
        var fusion = PresenceFusion()
        let heard = fusion.ingest(SensorObservation(timestamp: start, source: .microphone, voiceActivity: true))
        #expect(heard.isSomeonePresent)
        #expect(heard.source == .microphone)
        #expect(heard.proximity == .far)
        #expect(fusion.tick(now: start.addingTimeInterval(10)).isSomeonePresent)
        #expect(fusion.tick(now: start.addingTimeInterval(fusion.config.voiceHoldSeconds + 1)).isSomeonePresent == false)
    }

    @Test func ambientLightUsesHysteresis() {
        var fusion = PresenceFusion()
        _ = fusion.ingest(SensorObservation(timestamp: start, source: .trueDepth, ambientLux: 200))
        #expect(fusion.snapshot.ambientLight == .normal)
        // Just under the dim boundary is not enough to switch.
        _ = fusion.ingest(SensorObservation(timestamp: start, source: .trueDepth, ambientLux: 45))
        #expect(fusion.snapshot.ambientLight == .normal)
        _ = fusion.ingest(SensorObservation(timestamp: start, source: .trueDepth, ambientLux: 20))
        #expect(fusion.snapshot.ambientLight == .dim)
        _ = fusion.ingest(SensorObservation(timestamp: start, source: .trueDepth, ambientLux: 1))
        #expect(fusion.snapshot.ambientLight == .dark)
    }

    @Test func brightnessValueToLux() {
        // EV at ISO 100 is Bv + 5, and lux is 2.5 * 2^EV: Bv 0 is 80 lux, each step doubles.
        #expect(abs(AmbientLightMath.lux(brightnessValue: 0) - 80) < 0.001)
        #expect(abs(AmbientLightMath.lux(brightnessValue: 3) - 640) < 0.001)
        // 160 lux is a normally lit room, 2.5 lux a dark one, 5,120 lux a bright one.
        #expect(AmbientLightMath.level(lux: AmbientLightMath.lux(brightnessValue: 1)) == .normal)
        #expect(AmbientLightMath.level(lux: AmbientLightMath.lux(brightnessValue: -5)) == .dark)
        #expect(AmbientLightMath.level(lux: AmbientLightMath.lux(brightnessValue: 6)) == .bright)
    }
}
