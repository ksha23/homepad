import CoreGraphics
import Foundation
import Testing
@testable import HomePadPresence

/// Kyle sits 0.6 to 0.7 m from the iPad with his head turned 60 to 85
/// degrees. ARKit tracks no face, Vision still finds it. Each such face used
/// to end the look on the next frame, so recognition's votes never got past
/// one. These replay the analyzer's frames: every frame through
/// `arkitFrame`, and the frames where Vision ran through `visionFaces`.
@Suite struct VisionFaceFollowTests {
    private let head = CGPoint(x: 0.5, y: 0.4)
    private let otherHead = CGPoint(x: 0.9, y: 0.4)

    private var map: DepthMap {
        DepthScene(heads: [DepthScene.head(at: head, depth: 0.7), DepthScene.head(at: otherHead, depth: 0.7)]).map()
    }

    private func face(at point: CGPoint) -> VisionFace {
        VisionFace(point: point, expectedMeters: 0.9)
    }

    /// Runs frames at 10 a second from `start` for `seconds`, with no ARKit
    /// face, and a Vision face on every `visionEvery`th frame. Returns each frame's track.
    private func run(
        _ follower: inout FaceFollower, _ sensing: inout DepthSensing, from start: Double, seconds: Double,
        visionEvery: Int, faces: [VisionFace]
    ) -> [UUID?] {
        var tracks: [UUID?] = []
        for frame in 0..<Int(seconds * 10) {
            let time = start + Double(frame) * 0.1
            sensing.ingest(coarse: map, at: time)
            var track = follower.arkitFrame([], hasNewDepth: true, depth: &sensing, at: time)
            if frame % visionEvery == 0 {
                track = follower.visionFaces(faces, depth: &sensing, at: time)
            }
            tracks.append(track)
        }
        return tracks
    }

    /// Samples every 0.2 s: one track throughout, so the votes add up.
    @Test func aFaceOnlyVisionSeesKeepsOneTrack() throws {
        var follower = FaceFollower()
        var sensing = DepthSensing()
        let tracks = run(&follower, &sensing, from: 0, seconds: 10, visionEvery: 2, faces: [face(at: head)])
        let first = try #require(tracks.first ?? nil)
        #expect(tracks.allSatisfy { $0 == first })
        #expect(sensing.person(at: 9.9) != nil)
    }

    /// Once recognized, Vision looks once a second. That keeps the depth person
    /// and the track for a minute, where 30 s without a face used to let go.
    @Test func aFaceOnceASecondKeepsThePersonForAMinute() throws {
        var follower = FaceFollower()
        var sensing = DepthSensing()
        let tracks = run(&follower, &sensing, from: 0, seconds: 60, visionEvery: 10, faces: [face(at: head)])
        let first = try #require(tracks.first ?? nil)
        #expect(tracks.allSatisfy { $0 == first })
        let notes = sensing.takeNotes()
        #expect(notes.contains { $0.text.contains("let go") } == false)
        #expect(notes.contains { $0.text.contains("lost") } == false)
    }

    @Test func anotherPersonsFaceStartsANewTrack() throws {
        var follower = FaceFollower()
        var sensing = DepthSensing()
        let before = run(&follower, &sensing, from: 0, seconds: 2, visionEvery: 2, faces: [face(at: head)])
        let after = run(&follower, &sensing, from: 2, seconds: 1, visionEvery: 2, faces: [face(at: otherHead)])
        let first = try #require(before.last ?? nil)
        let second = try #require(after.last ?? nil)
        #expect(first != second)
    }

    @Test func twoFacesEndTheTrack() {
        var follower = FaceFollower()
        var sensing = DepthSensing()
        _ = run(&follower, &sensing, from: 0, seconds: 1, visionEvery: 2, faces: [face(at: head)])
        sensing.ingest(coarse: map, at: 1)
        _ = follower.arkitFrame([], hasNewDepth: true, depth: &sensing, at: 1)
        let both = follower.visionFaces([face(at: head), face(at: otherHead)], depth: &sensing, at: 1)
        #expect(both == nil)
    }

    /// A face where the depth shows only the wall, off the followed head, is not this person.
    @Test func aFaceOffTheFollowedHeadEndsTheTrack() throws {
        var follower = FaceFollower()
        var sensing = DepthSensing()
        let before = run(&follower, &sensing, from: 0, seconds: 1, visionEvery: 2, faces: [face(at: head)])
        #expect(before.last != nil)
        sensing.ingest(coarse: map, at: 1)
        _ = follower.arkitFrame([], hasNewDepth: true, depth: &sensing, at: 1)
        let elsewhere = follower.visionFaces([face(at: CGPoint(x: 0.1, y: 0.1))], depth: &sensing, at: 1)
        #expect(elsewhere == nil)
    }

    /// When ARKit finds the face again, under a new anchor, it is the same track.
    @Test func arkitFindingTheFaceAgainKeepsTheTrack() throws {
        var follower = FaceFollower()
        var sensing = DepthSensing()
        let before = run(&follower, &sensing, from: 0, seconds: 2, visionEvery: 2, faces: [face(at: head)])
        let first = try #require(before.last ?? nil)
        sensing.ingest(coarse: map, at: 2.1)
        let arkit = ARKitFace(
            anchor: UUID(), position: SIMD3(0, 0, -0.7), image: FaceInImage(point: head, distanceMeters: 0.7)
        )
        let again = follower.arkitFrame([arkit], hasNewDepth: true, depth: &sensing, at: 2.1)
        #expect(again == first)
    }
}

/// The alignment line used to be written once per session and was gone by the
/// time a 32 MB trace was read.
@Suite struct AlignmentNoteTests {
    @Test func theAlignmentIsWrittenAgainHourlyAndOnEachStart() {
        var sensing = DepthSensing()
        let line = "depth map 640x480 for image 1280x720"
        sensing.noteAlignment(line, at: 0)
        sensing.noteAlignment(line, at: 10)
        #expect(sensing.takeNotes().count == 1)
        sensing.noteAlignment(line, at: 3_601)
        #expect(sensing.takeNotes().map(\.repeats) == [true])
        sensing.noteAlignmentAgain()
        sensing.noteAlignment(line, at: 3_602)
        #expect(sensing.takeNotes().count == 1)
        sensing.noteAlignment("depth map 320x240 for image 1280x720", at: 3_603)
        #expect(sensing.takeNotes().count == 1)
    }
}
