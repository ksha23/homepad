import CoreGraphics
import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

/// A synthetic coarse depth map: a wall with people painted on it. Points are
/// normalized with a top-left origin, sizes are in map pixels.
struct DepthScene {
    struct Head {
        var center: CGPoint
        var radiusPixels: Double
        var depth: Float
    }

    var width = 48
    var height = 36
    var wall: Float = 3.5
    var heads: [Head] = []

    func map() -> DepthMap {
        var meters = [Float](repeating: wall, count: width * height)
        for head in heads {
            let centerColumn = Double(head.center.x) * Double(width)
            let centerRow = Double(head.center.y) * Double(height)
            for row in 0..<height {
                for column in 0..<width {
                    let dx = Double(column) + 0.5 - centerColumn
                    let dy = Double(row) + 0.5 - centerRow
                    let inHead = dx * dx + dy * dy <= head.radiusPixels * head.radiusPixels
                    // The body hangs below the head, a little farther away.
                    let inBody = abs(dx) <= head.radiusPixels * 1.6 && dy > 0
                    if inHead {
                        meters[row * width + column] = min(meters[row * width + column], head.depth)
                    } else if inBody {
                        meters[row * width + column] = min(meters[row * width + column], head.depth + 0.08)
                    }
                }
            }
        }
        return DepthMap(width: width, height: height, meters: meters)
    }

    /// A head of a person `depth` meters away, its radius from the default
    /// 60 degree view of the map.
    static func head(at center: CGPoint, depth: Float, in scene: DepthScene = DepthScene()) -> Head {
        let focal = Double(scene.width) / 2 / tan(30 * Double.pi / 180)
        return Head(center: center, radiusPixels: 0.1 * focal / Double(depth), depth: depth)
    }
}

@Suite struct DepthRegistrationTests {
    /// ARKit's 16:9 image over a 4:3 depth map covers the middle three quarters of its height.
    @Test func wideImageIsTheMiddleBandOfTheDepthMap() {
        let registration = DepthRegistration(imageSize: CGSize(width: 1280, height: 720), depthSize: CGSize(width: 640, height: 480))
        #expect(abs(registration.scaleY - 0.75) < 1e-9)
        #expect(abs(registration.offsetY - 0.125) < 1e-9)
        #expect(registration.scaleX == 1)
        let top = registration.depthPoint(fromImage: CGPoint(x: 0.5, y: 0))
        #expect(abs(top.y - 0.125) < 1e-9)
        let center = registration.depthPoint(fromImage: CGPoint(x: 0.5, y: 0.5))
        #expect(abs(center.y - 0.5) < 1e-9)
    }

    @Test func matchingAspectIsOneToOne() {
        let registration = DepthRegistration(imageSize: CGSize(width: 640, height: 480), depthSize: CGSize(width: 320, height: 240))
        #expect(registration == .identity)
    }

    /// Calibrated pinhole models of a centered crop give the same mapping as the crop rule.
    @Test func pinholeModelsAgreeWithTheCrop() {
        // A 4032x3024 sensor, its 16:9 crop scaled to 1280x720, depth at full field.
        let focal = 2800.0
        let depth = PinholeIntrinsics(focalX: focal, focalY: focal, centerX: 2016, centerY: 1512, width: 4032, height: 3024)
        let scale = 1280.0 / 4032
        let image = PinholeIntrinsics(
            focalX: focal * scale, focalY: focal * scale, centerX: 640, centerY: 360, width: 1280, height: 720
        )
        let registration = DepthRegistration(image: image, depth: depth)
        #expect(abs(registration.scaleX - 1) < 1e-6)
        #expect(abs(registration.offsetX) < 1e-6)
        #expect(abs(registration.scaleY - 0.75) < 1e-6)
        #expect(abs(registration.offsetY - 0.125) < 1e-6)
    }

    @Test func rectsKeepTheBottomLeftOrigin() {
        let registration = DepthRegistration(imageSize: CGSize(width: 1280, height: 720), depthSize: CGSize(width: 640, height: 480))
        // A box at the bottom of the image is near the bottom of the band, an eighth above the depth map's bottom.
        let rect = registration.depthRect(fromImageBottomLeft: CGRect(x: 0.4, y: 0, width: 0.2, height: 0.2))
        #expect(abs(rect.minY - 0.125) < 1e-9)
        #expect(abs(rect.height - 0.15) < 1e-9)
        #expect(abs(rect.minX - 0.4) < 1e-9)
    }

    @Test func downsamplingKeepsTheFocalLengthInItsOwnPixels() {
        let map = DepthMap(width: 640, height: 480, meters: [Float](repeating: 1, count: 640 * 480), focalLength: 520)
        let coarse = map.downsampled(step: map.step(toColumns: 48))
        #expect(coarse.width == 49)
        #expect(coarse.focalLength == 40)
    }
}

@Suite struct DepthPersonTrackerTests {
    private let here = CGPoint(x: 0.5, y: 0.4)

    private func scene(_ heads: DepthScene.Head...) -> DepthMap {
        DepthScene(heads: heads).map()
    }

    private func faceSeed(_ point: CGPoint, expected: Double) -> [DepthPersonTracker.Seed] {
        [DepthPersonTracker.Seed(point: point, expectedMeters: expected)]
    }

    @Test func aFacePicksUpThePersonAtTheDepthOfTheirHead() throws {
        var tracker = DepthPersonTracker()
        let personSeen = tracker.update(scene(DepthScene.head(at: here, depth: 0.7)), seeds: faceSeed(here, expected: 0.75), at: 0)
        let person = try #require(personSeen)
        #expect(abs(person.distanceMeters - 0.7) < 0.02)
        #expect(tracker.events.contains { if case .started(_, true) = $0 { true } else { false } })
    }

    /// The face is lost in the dark, the person stands still: the depth keeps them, under the same ID.
    @Test func aPersonStandingStillStaysFollowedWithoutTheirFace() throws {
        var tracker = DepthPersonTracker()
        let map = scene(DepthScene.head(at: here, depth: 0.7))
        let firstSeen = tracker.update(map, seeds: faceSeed(here, expected: 0.7), at: 0)
        let first = try #require(firstSeen)
        for step in 1...200 {
            tracker.update(map, seeds: [], at: Double(step) * 0.1)
        }
        let later = try #require(tracker.person)
        #expect(later.id == first.id)
        #expect(abs(later.distanceMeters - 0.7) < 0.02)
    }

    @Test func aPersonWhoLeavesIsLost() {
        var tracker = DepthPersonTracker()
        tracker.update(scene(DepthScene.head(at: here, depth: 0.7)), seeds: faceSeed(here, expected: 0.7), at: 0)
        tracker.update(scene(), seeds: [], at: 0.1)
        #expect(tracker.person == nil)
        #expect(tracker.events.contains { if case .lost = $0 { true } else { false } })
    }

    /// Walking toward the iPad changes the depth smoothly, and the tracker follows.
    @Test func aPersonWalkingCloserIsFollowed() throws {
        var tracker = DepthPersonTracker()
        let firstSeen = tracker.update(scene(DepthScene.head(at: here, depth: 2.0)), seeds: faceSeed(here, expected: 2), at: 0)
        let first = try #require(firstSeen)
        var depth: Float = 2.0
        var time = 0.0
        while depth > 0.6 {
            depth -= 0.08
            time += 0.1
            tracker.update(scene(DepthScene.head(at: here, depth: depth)), seeds: [], at: time)
        }
        let person = try #require(tracker.person)
        #expect(person.id == first.id)
        #expect(person.distanceMeters < 0.7)
    }

    /// Something that never moves, picked up from movement, is let go once nothing confirms it.
    @Test func somethingThatNeverMovesIsLetGo() {
        var tracker = DepthPersonTracker()
        let chair = scene(DepthScene.head(at: here, depth: 1.2))
        tracker.update(chair, seeds: [DepthPersonTracker.Seed(point: here, expectedMeters: nil)], at: 0)
        tracker.update(chair, seeds: [], at: 29)
        #expect(tracker.person != nil)
        tracker.update(chair, seeds: [], at: 31)
        #expect(tracker.person == nil)
        #expect(tracker.events.contains { if case .letGo = $0 { true } else { false } })
    }

    /// A face every few seconds keeps a person followed for as long as they stay.
    @Test func faceSightingsKeepThePersonForMinutes() throws {
        var tracker = DepthPersonTracker()
        let map = scene(DepthScene.head(at: here, depth: 0.8))
        let firstSeen = tracker.update(map, seeds: faceSeed(here, expected: 0.8), at: 0)
        let first = try #require(firstSeen)
        for step in 1...1200 {
            let time = Double(step) * 0.1
            let seeds = step % 50 == 0 ? faceSeed(here, expected: 0.8) : []
            tracker.update(map, seeds: seeds, at: time)
        }
        #expect(tracker.person?.id == first.id)
    }

    /// A different face beside the followed head is someone else.
    @Test func anotherFaceStartsAnotherPerson() throws {
        var tracker = DepthPersonTracker()
        let there = CGPoint(x: 0.9, y: 0.4)
        let map = scene(DepthScene.head(at: here, depth: 0.9), DepthScene.head(at: there, depth: 0.9))
        let firstSeen = tracker.update(map, seeds: faceSeed(here, expected: 0.9), at: 0)
        let first = try #require(firstSeen)
        let secondSeen = tracker.update(map, seeds: faceSeed(there, expected: 0.9), at: 0.1)
        let second = try #require(secondSeen)
        #expect(second.id != first.id)
    }

    /// A face whose spot in the depth map holds only the wall did not land on the face.
    @Test func aSeedOnTheWallIsMissed() {
        var tracker = DepthPersonTracker()
        tracker.update(scene(DepthScene.head(at: here, depth: 0.7)), seeds: faceSeed(CGPoint(x: 0.1, y: 0.1), expected: 0.7), at: 0)
        #expect(tracker.person == nil)
        #expect(tracker.events.contains { if case .seedMissed = $0 { true } else { false } })
    }

    /// A hand or shoulder moving beside a face seen a moment ago is that
    /// person moving. Once the face has gone unseen for a while, movement
    /// elsewhere is someone new again.
    @Test func movementBesideAFaceSeenJustNowKeepsThePerson() throws {
        var tracker = DepthPersonTracker()
        let left = CGPoint(x: 0.3, y: 0.4)
        let right = CGPoint(x: 0.95, y: 0.4)
        let map = scene(DepthScene.head(at: left, depth: 0.7), DepthScene.head(at: right, depth: 0.7))
        let firstSeen = tracker.update(map, seeds: faceSeed(left, expected: 0.7), at: 0)
        let first = try #require(firstSeen)
        let moved = [DepthPersonTracker.Seed(point: right, expectedMeters: nil)]
        #expect(tracker.update(map, seeds: moved, at: 0.1)?.id == first.id)
        for step in 2...32 { tracker.update(map, seeds: [], at: Double(step) * 0.1) }
        let later = tracker.update(map, seeds: moved, at: 3.3)
        #expect(later != nil)
        #expect(later?.id != first.id)
    }

    /// Without depth on a frame, a face on the followed head confirms them and one elsewhere does not.
    @Test func facesWithoutDepthConfirmOnlyOnTheHead() {
        var tracker = DepthPersonTracker()
        tracker.update(scene(DepthScene.head(at: here, depth: 0.7)), seeds: faceSeed(here, expected: 0.7), at: 0)
        let onHead = tracker.confirm(face: CGPoint(x: 0.52, y: 0.41), at: 20)
        let elsewhere = tracker.confirm(face: CGPoint(x: 0.95, y: 0.9), at: 25)
        #expect(onHead)
        #expect(elsewhere == false)
        #expect(tracker.person?.confirmedAt == 20)
    }
}

@Suite struct DepthHeldFaceTrackTests {
    private let anchor = UUID()
    private let here = SIMD3<Float>(0, 0, -0.7)
    private let person = UUID()

    private func face(_ anchor: UUID, at position: SIMD3<Float>? = nil) -> FaceTrackContinuity.TrackedFace {
        FaceTrackContinuity.TrackedFace(anchor: anchor, position: position ?? here)
    }

    /// ARKit loses the face for seconds in the dark. The same depth person holds the track.
    @Test func theSamePersonInDepthHoldsALongGap() {
        var continuity = FaceTrackContinuity()
        let before = continuity.update(tracked: [face(anchor)], depthPerson: person, at: 0)
        _ = continuity.update(tracked: [], depthPerson: person, at: 0.1)
        let during = continuity.update(tracked: [], depthPerson: person, at: 6)
        let after = continuity.update(tracked: [face(anchor)], depthPerson: person, at: 8)
        #expect(during == before)
        #expect(after == before)
        let bridged = continuity.takeBridgedGap() ?? 0
        #expect(abs(bridged - 7.9) < 1e-9)
    }

    /// After a long loss ARKit may give the face a new anchor. On the same depth person it is the same face.
    @Test func aNewAnchorOnTheSamePersonKeepsTheTrack() {
        var continuity = FaceTrackContinuity()
        let before = continuity.update(tracked: [face(anchor)], depthPerson: person, at: 0)
        _ = continuity.update(tracked: [], depthPerson: person, at: 0.1)
        let after = continuity.update(tracked: [face(UUID(), at: here + SIMD3(0.3, 0, 0))], depthPerson: person, at: 3)
        #expect(after == before)
    }

    @Test func anotherDepthPersonEndsTheTrack() {
        var continuity = FaceTrackContinuity()
        let before = continuity.update(tracked: [face(anchor)], depthPerson: person, at: 0)
        _ = continuity.update(tracked: [], depthPerson: UUID(), at: 0.1)
        let gone = continuity.update(tracked: [], depthPerson: UUID(), at: 1)
        #expect(gone == nil)
        let after = continuity.update(tracked: [face(anchor)], depthPerson: UUID(), at: 1.2)
        #expect(after != nil && after != before)
    }

    @Test func depthHoldsTheTrackForThirtySecondsAtMost() {
        var continuity = FaceTrackContinuity()
        _ = continuity.update(tracked: [face(anchor)], depthPerson: person, at: 0)
        _ = continuity.update(tracked: [], depthPerson: person, at: 0.1)
        #expect(continuity.update(tracked: [], depthPerson: person, at: 29) != nil)
        #expect(continuity.update(tracked: [], depthPerson: person, at: 31) == nil)
    }

    /// Without a depth person the old half-second rule applies.
    @Test func withoutDepthALongGapStillEndsTheTrack() {
        var continuity = FaceTrackContinuity()
        _ = continuity.update(tracked: [face(anchor)], at: 0)
        _ = continuity.update(tracked: [], at: 0.1)
        #expect(continuity.update(tracked: [], at: 0.7) == nil)
    }
}

@Suite struct DepthPresenceFusionTests {
    private let start = Date(timeIntervalSince1970: 2_000_000)

    private func observation(at seconds: Double, faceMeters: Double?, depthMeters: Double?) -> SensorObservation {
        var observation = SensorObservation(timestamp: start.addingTimeInterval(seconds), source: .trueDepth)
        if let faceMeters {
            observation.faces = [DetectedFace(distanceMeters: faceMeters, isLookingAtScreen: true)]
        }
        observation.facesAreTracked = true
        observation.depthPersonMeters = depthMeters
        observation.isFreshSighting = faceMeters != nil
        return observation
    }

    /// In the dark ARKit loses the face for seconds and misjudges its distance.
    /// The depth of the followed head keeps the person present and near.
    @Test func depthKeepsANearPersonPresentThroughAFaceGap() {
        var fusion = PresenceFusion()
        var snapshot = fusion.ingest(observation(at: 0, faceMeters: 1.4, depthMeters: 0.7))
        #expect(snapshot.proximity == .near)
        for step in 1...100 {
            snapshot = fusion.ingest(observation(at: Double(step) * 0.1, faceMeters: nil, depthMeters: 0.7))
        }
        #expect(snapshot.isSomeonePresent)
        #expect(snapshot.proximity == .near)
    }

    /// The depth person only holds presence: it never starts it on its own.
    @Test func depthAloneDoesNotStartPresence() {
        var fusion = PresenceFusion()
        let first = fusion.ingest(observation(at: 0, faceMeters: nil, depthMeters: 0.8))
        let second = fusion.ingest(observation(at: 0.5, faceMeters: nil, depthMeters: 0.8))
        #expect(first.isSomeonePresent == false)
        #expect(second.isSomeonePresent == false)
    }
}

/// Should ARKit's projection put faces the other way round in the depth map
/// on one of the iPads, the mirror that alone finds them is used after five maps.
@Suite struct DepthFaceSeedTests {
    /// In the dark a face found in the depth map is the only thing that
    /// shows someone sitting still, so it starts the person.
    @Test func aDepthFaceStartsThePersonWithNoOneFollowed() throws {
        var sensing = DepthSensing()
        let here = CGPoint(x: 0.5, y: 0.4)
        sensing.ingest(coarse: DepthScene(heads: [DepthScene.head(at: here, depth: 0.6)]).map(), at: 0)
        sensing.noteFace(at: here, meters: 0.6, time: 0)
        let person = try #require(sensing.people.person)
        #expect(abs(person.distanceMeters - 0.6) < 0.02)
        #expect(sensing.takeNotes().contains { $0.text.contains("from a face") })
    }
}

@Suite struct FaceFlipTests {
    @Test func facesFoundOnlyMirroredAcrossSwitchTheMirrorOn() {
        var sensing = DepthSensing()
        let headInDepth = CGPoint(x: 0.8, y: 0.4)
        let map = DepthScene(heads: [DepthScene.head(at: headInDepth, depth: 0.7)]).map()
        let face = FaceInImage(point: CGPoint(x: 0.2, y: 0.4), distanceMeters: 0.7)
        var followed: [UUID?] = []
        for step in 0..<6 {
            sensing.ingest(coarse: map, at: Double(step) * 0.1)
            followed.append(sensing.follow([face], hasNewDepth: true, at: Double(step) * 0.1))
        }
        #expect(followed.prefix(4).allSatisfy { $0 == nil })
        #expect(followed[4] != nil)
        #expect(followed[5] == followed[4])
        #expect(sensing.flip == .across)
        let notes = sensing.takeNotes()
        #expect(notes.contains { $0.key == "depth flip" })
    }

    @Test func facesFoundAsProjectedKeepNoFlip() {
        var sensing = DepthSensing()
        let map = DepthScene(heads: [DepthScene.head(at: CGPoint(x: 0.3, y: 0.4), depth: 0.7)]).map()
        let face = FaceInImage(point: CGPoint(x: 0.3, y: 0.4), distanceMeters: 0.7)
        sensing.ingest(coarse: map, at: 0)
        let followed = sensing.follow([face], hasNewDepth: true, at: 0)
        #expect(followed != nil)
        #expect(sensing.flip == .none)
    }
}
