import Foundation
import Testing
@testable import HomePadCore

/// The session rules: the timeout, another member or a stranger taking over at
/// once, an undecided face moving nothing, touches, picks by hand and Face ID.
@Suite struct MemberSessionTests {
    let kyle = UUID()
    let sam = UUID()
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A session that recognized Kyle on his first look, at `t0`.
    private func kyleRecognized(timeout: TimeInterval = 30) -> MemberSession {
        var session = MemberSession(timeout: timeout)
        let look = UUID()
        session.handle(.camera(.face(look: look, identity: .unsure)), at: t0 - 1)
        session.handle(.camera(.face(look: look, identity: .member(kyle))), at: t0)
        return session
    }

    private func at(_ seconds: TimeInterval) -> Date { t0 + seconds }

    @Test func staysWhileTheFaceIsInViewAndEndsOneTimeoutAfterItLeaves() {
        var session = kyleRecognized()
        #expect(session.mode == .recognized(kyle))
        // Ten minutes in view: still Kyle.
        for second in stride(from: 1.0, through: 600, by: 1) { session.handle(.tick, at: at(second)) }
        #expect(session.mode == .recognized(kyle))
        // Walks away at 600 s. The body may still be in view, the face is not.
        session.handle(.camera(.noFace), at: at(600))
        session.handle(.tick, at: at(629))
        #expect(session.mode == .recognized(kyle))
        session.handle(.tick, at: at(631))
        #expect(session.mode == .guest)
    }

    @Test func anotherMembersFaceTakesOverAtOnce() {
        var session = kyleRecognized()
        let samLook = UUID()
        session.handle(.camera(.face(look: samLook, identity: .unsure)), at: at(5))
        #expect(session.mode == .recognized(kyle))
        session.handle(.camera(.face(look: samLook, identity: .member(sam))), at: at(5.6))
        #expect(session.mode == .recognized(sam))
    }

    @Test func aConfidentStrangerDropsToGuestAtOnce() {
        var session = kyleRecognized()
        let friend = UUID()
        session.handle(.camera(.face(look: friend, identity: .unsure)), at: at(5))
        session.handle(.camera(.face(look: friend, identity: .stranger)), at: at(6))
        #expect(session.mode == .guest)
        // Kyle coming back signs him in again.
        session.handle(.camera(.face(look: UUID(), identity: .member(kyle))), at: at(20))
        #expect(session.mode == .recognized(kyle))
    }

    @Test func anUndecidedFaceNeitherKicksOutNorKeepsTheSession() {
        var session = kyleRecognized()
        // A new look nobody could decide about: a blurry frame, a bad angle, the dark.
        session.handle(.camera(.face(look: UUID(), identity: .unsure)), at: at(10))
        session.handle(.tick, at: at(39))
        #expect(session.mode == .recognized(kyle))
        // It does not keep Kyle's profile alive either.
        session.handle(.tick, at: at(41))
        #expect(session.mode == .guest)
    }

    @Test func touchesCountOnlyWhenTheCameraCannotContradictThem() {
        var session = kyleRecognized()
        // Looking down at the iPad: no face in view, touches keep the session.
        session.handle(.camera(.noFace), at: at(1))
        for second in stride(from: 20.0, through: 200, by: 20) {
            session.handle(.touch, at: at(second))
            session.handle(.tick, at: at(second + 1))
        }
        #expect(session.mode == .recognized(kyle))
        // Someone else's face, not decided yet: their touches count for nothing.
        session.handle(.camera(.face(look: UUID(), identity: .unsure)), at: at(205))
        for second in stride(from: 210.0, through: 230, by: 10) { session.handle(.touch, at: at(second)) }
        session.handle(.tick, at: at(231))
        #expect(session.mode == .guest)
    }

    @Test func aPickByHandFollowsWhoPickedAndTheSameTimeout() {
        var session = kyleRecognized()
        session.handle(.picked(sam), at: at(10))
        #expect(session.mode == .picked(sam))
        // Kyle, who picked, looks away and back: he is recognized again, and Sam's
        // Home Screen stays.
        session.handle(.camera(.noFace), at: at(20))
        session.handle(.camera(.face(look: UUID(), identity: .member(kyle))), at: at(25))
        #expect(session.mode == .picked(sam))
        // He leaves: the pick ends one timeout later.
        session.handle(.camera(.nobody), at: at(40))
        session.handle(.tick, at: at(71))
        #expect(session.mode == .guest)

        // Picked again, then Sam herself walks up: her own session.
        session.handle(.camera(.face(look: UUID(), identity: .member(kyle))), at: at(80))
        session.handle(.picked(sam), at: at(81))
        session.handle(.camera(.face(look: UUID(), identity: .member(sam))), at: at(90))
        #expect(session.mode == .recognized(sam))
    }

    @Test func guestByHandHoldsWhileItsChooserStays() {
        var session = kyleRecognized()
        session.handle(.picked(nil), at: at(10))
        #expect(session.mode == .guest)
        // Handing the iPad over: Kyle's own face does not sign him back in.
        session.handle(.camera(.face(look: UUID(), identity: .member(kyle))), at: at(15))
        #expect(session.mode == .guest)
        // Once he has been gone a timeout, it does.
        session.handle(.camera(.nobody), at: at(20))
        session.handle(.tick, at: at(51))
        session.handle(.camera(.face(look: UUID(), identity: .member(kyle))), at: at(60))
        #expect(session.mode == .recognized(kyle))
    }

    @Test func faceIDTakesTheFaceInViewOrTheNextOne() {
        var session = MemberSession(timeout: 30)
        // Face ID while the camera paused: the next face is the one that passed it.
        session.handle(.verified(kyle), at: t0)
        let look = UUID()
        session.handle(.camera(.face(look: look, identity: .unsure)), at: at(3))
        // Recognition calls that face a stranger: Face ID wins for this look,
        // and his touches keep the session.
        session.handle(.camera(.face(look: look, identity: .stranger)), at: at(4))
        session.handle(.touch, at: at(100))
        session.handle(.tick, at: at(120))
        #expect(session.mode == .verified(kyle))
        // A new face that is confidently someone else still takes over.
        session.handle(.camera(.face(look: UUID(), identity: .stranger)), at: at(130))
        #expect(session.mode == .guest)
    }

    @Test func aRemovedMemberIsSignedOut() {
        var session = kyleRecognized()
        session.handle(.removed(kyle), at: at(1))
        #expect(session.mode == .guest)
        #expect(!session.hasOwner)
    }
}
